import Foundation
import Combine
import Supabase

// MARK: - Tier

enum Tier: String, CaseIterable {
    case free
    case pro       // Monthly ($9.99) or Annual ($79/yr) — period stored separately on TierManager
    case founding  // Founders Plan ($5.99/mo locked forever, 300 spots)
}

enum ProPeriod: String, Codable {
    case monthly
    case annual
}

// MARK: - Credit Economics
//
// 1 Credit = 1,000 tokens (input + output combined). All AI calls log raw tokens
// to `usage_log`; the client and server divide by 1,000 for caps and display.

enum Credits {
    static let tokensPerCredit = 1_000

    static func credits(fromTokens tokens: Int) -> Int {
        max(0, tokens) / tokensPerCredit
    }
}

// MARK: - TierLimits

struct TierLimits {
    let maxNotes: Int?              // nil = unlimited
    let maxSectionsPerNote: Int?
    let baseCreditsPerMonth: Int    // does NOT include Power Add-on
    let cloudSync: Bool
    let commits: Bool
    let shareLinks: Bool
    let semanticSearch: Bool
    let fullInsights: Bool
    let aiWorkspace: Bool

    // Free: core app, single device, 50 notes, 5 Credits/month
    static let free = TierLimits(
        maxNotes: 50,
        maxSectionsPerNote: nil,
        baseCreditsPerMonth: 5,
        cloudSync: false,
        commits: false,
        shareLinks: false,
        semanticSearch: false,
        fullInsights: false,
        aiWorkspace: false
    )

    // Pro Monthly: 200 Credits/month
    static let proMonthly = TierLimits(
        maxNotes: nil,
        maxSectionsPerNote: nil,
        baseCreditsPerMonth: 200,
        cloudSync: true,
        commits: true,
        shareLinks: true,
        semanticSearch: true,
        fullInsights: true,
        aiWorkspace: true
    )

    // Pro Annual: 250 Credits/month (annual gets a small bonus)
    static let proAnnual = TierLimits(
        maxNotes: nil,
        maxSectionsPerNote: nil,
        baseCreditsPerMonth: 250,
        cloudSync: true,
        commits: true,
        shareLinks: true,
        semanticSearch: true,
        fullInsights: true,
        aiWorkspace: true
    )

    // Founding: same Pro features, 200 Credits/month (matches Pro Monthly)
    static let founding = TierLimits(
        maxNotes: nil,
        maxSectionsPerNote: nil,
        baseCreditsPerMonth: 200,
        cloudSync: true,
        commits: true,
        shareLinks: true,
        semanticSearch: true,
        fullInsights: true,
        aiWorkspace: true
    )
}

// MARK: - GatedFeature

enum GatedFeature: String, CaseIterable {
    case notes
    case aiActions
    case aiWorkspace
    case cloudSync
    case commits
    case shareLinks
    case semanticSearch
    case fullInsights

    var displayName: String {
        switch self {
        case .notes: return "Notes"
        case .aiActions: return "AI Credits"
        case .aiWorkspace: return "AI Workspace"
        case .cloudSync: return "Cloud Sync"
        case .commits: return "Versions"
        case .shareLinks: return "Share Links"
        case .semanticSearch: return "Semantic Search"
        case .fullInsights: return "Full Insights"
        }
    }

    var upgradeMessage: String {
        switch self {
        case .notes: return "You've reached the free limit of 50 notes. Upgrade to create unlimited notes."
        case .aiActions: return "You've used all your AI Credits this month. Upgrade — or add the Power pack — for more."
        case .aiWorkspace: return "The AI workspace is available on paid plans. Upgrade to unlock it."
        case .cloudSync: return "Multi-device sync is available on paid plans. Upgrade to sync everywhere."
        case .commits: return "Version history is available on paid plans. Upgrade to track your note history."
        case .shareLinks: return "Sharing is available on paid plans. Upgrade to share your notes."
        case .semanticSearch: return "AI-powered search is available on paid plans. Upgrade for smarter search."
        case .fullInsights: return "Advanced insights are available on paid plans. Upgrade to see the full picture."
        }
    }

    var icon: String {
        switch self {
        case .notes: return "note.text"
        case .aiActions: return "sparkles"
        case .aiWorkspace: return "brain"
        case .cloudSync: return "icloud"
        case .commits: return "arrow.down.doc"
        case .shareLinks: return "square.and.arrow.up"
        case .semanticSearch: return "magnifyingglass"
        case .fullInsights: return "lightbulb"
        }
    }
}

// MARK: - TierManager

@MainActor
final class TierManager: ObservableObject {
    static let shared = TierManager()

    /// Total founders spots available (raised from 200 to 300 at unit-economics rework)
    static let foundersSpotsCap = 300

    /// Power Add-on grants this many additional Credits/month on top of the base tier.
    static let powerAddonCredits = 1_000

    @Published private(set) var currentTier: Tier = .free
    @Published private(set) var proPeriod: ProPeriod? = nil
    @Published private(set) var hasPowerAddon: Bool = false
    @Published var showPaywall = false
    @Published var paywallFeature: GatedFeature?
    @Published private(set) var creditsUsedThisMonth: Int = 0
    @Published var isFoundingMember: Bool = false
    @Published private(set) var foundersSpotsTaken: Int = 0

    /// Set when Supabase `user_profiles.subscription_tier` confirms a paid tier.
    /// Prevents RevenueCat/StoreKit failures from downgrading the tier on platforms
    /// where StoreKit may not be available (e.g., macOS development builds).
    private(set) var serverConfirmedTier: Tier?

    var foundersSpotsRemaining: Int {
        max(0, Self.foundersSpotsCap - foundersSpotsTaken)
    }

    var limits: TierLimits {
        switch currentTier {
        case .free: return .free
        case .pro: return proPeriod == .annual ? .proAnnual : .proMonthly
        case .founding: return .founding
        }
    }

    /// Effective monthly credit cap, including the Power Add-on if active.
    var maxCreditsPerMonth: Int {
        limits.baseCreditsPerMonth + (hasPowerAddon ? Self.powerAddonCredits : 0)
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let tier = "obius_tier"
        static let proPeriod = "obius_pro_period"
        static let hasPowerAddon = "obius_has_power_addon"
        static let isFoundingMember = "obius_is_founding_member"
        static let creditsThisMonth = "obius_credits_this_month"
        static let creditsMonth = "obius_credits_month_key"
    }

    private init() {
        loadPersistedState()
    }

    // MARK: - Initialization

    func initialize() async {
        loadPersistedState()
        resetIfNewMonth()

        // Wait for AuthManager to finish restoring session so that
        // StoreManager is identified with the correct RevenueCat user
        // before we check entitlements.
        while AuthManager.shared.isLoading {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        // Check Supabase first — this is the server-side source of truth
        // and prevents StoreKit failures on macOS from blocking sync
        await checkFoundingMemberStatus()

        // Then check RevenueCat entitlements (may override with more recent data)
        await StoreManager.shared.refreshCustomerInfo()

        await fetchFoundersSpotsCount()

        // Sync credit usage from the server
        await syncCreditUsage()
    }

    /// Wipe per-user tier state on sign-out / account switch. Without this, the
    /// previous user's tier sits in UserDefaults (and `serverConfirmedTier` blocks
    /// the StoreManager downgrade), so the next account flickers between Pro and
    /// Free until the server check completes — and stays Pro entirely if the new
    /// account is on Free, since the "no entitlement" path is short-circuited.
    func logout() {
        currentTier = .free
        proPeriod = nil
        hasPowerAddon = false
        isFoundingMember = false
        creditsUsedThisMonth = 0
        foundersSpotsTaken = 0
        serverConfirmedTier = nil

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.tier)
        defaults.removeObject(forKey: Keys.proPeriod)
        defaults.removeObject(forKey: Keys.hasPowerAddon)
        defaults.removeObject(forKey: Keys.isFoundingMember)
        defaults.removeObject(forKey: Keys.creditsThisMonth)
        defaults.removeObject(forKey: Keys.creditsMonth)
    }

    private func loadPersistedState() {
        if let rawTier = UserDefaults.standard.string(forKey: Keys.tier),
           let tier = Tier(rawValue: rawTier) {
            currentTier = tier
        }
        if let rawPeriod = UserDefaults.standard.string(forKey: Keys.proPeriod),
           let period = ProPeriod(rawValue: rawPeriod) {
            proPeriod = period
        }
        hasPowerAddon = UserDefaults.standard.bool(forKey: Keys.hasPowerAddon)
        isFoundingMember = UserDefaults.standard.bool(forKey: Keys.isFoundingMember)
        creditsUsedThisMonth = UserDefaults.standard.integer(forKey: Keys.creditsThisMonth)
    }

    // MARK: - Tier Updates

    func updateTier(_ tier: Tier, period: ProPeriod? = nil) {
        currentTier = tier
        proPeriod = (tier == .pro) ? period : nil
        UserDefaults.standard.set(tier.rawValue, forKey: Keys.tier)
        if let period, tier == .pro {
            UserDefaults.standard.set(period.rawValue, forKey: Keys.proPeriod)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.proPeriod)
        }
    }

    func updatePowerAddon(_ active: Bool) {
        hasPowerAddon = active
        UserDefaults.standard.set(active, forKey: Keys.hasPowerAddon)
    }

    // MARK: - Founding Member

    private func checkFoundingMemberStatus() async {
        guard SupabaseManager.shared.isAuthenticated else {
            print("[TierManager] Skipping server check — not authenticated")
            return
        }

        do {
            struct ProfileRow: Decodable {
                let is_founding_member: Bool?
                let subscription_tier: String?
                let subscription_period: String?
                let has_power_addon: Bool?
            }

            guard let userId = SupabaseManager.shared.currentUser?.id.uuidString.lowercased() else {
                print("[TierManager] No current user ID")
                return
            }

            print("[TierManager] Checking subscription for user: \(userId)")

            let profiles: [ProfileRow] = try await SupabaseManager.shared.client
                .from("user_profiles")
                .select("is_founding_member, subscription_tier, subscription_period, has_power_addon")
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value

            guard let profile = profiles.first else {
                print("[TierManager] No profile row found in user_profiles")
                return
            }

            print("[TierManager] Server tier: \(profile.subscription_tier ?? "nil"), period: \(profile.subscription_period ?? "nil"), founding: \(profile.is_founding_member ?? false), power: \(profile.has_power_addon ?? false)")

            if profile.is_founding_member == true {
                isFoundingMember = true
                UserDefaults.standard.set(true, forKey: Keys.isFoundingMember)
            }

            // Use server-side subscription_tier as source of truth
            // (kept up-to-date by RevenueCat webhook)
            if let serverTier = profile.subscription_tier,
               let tier = Tier(rawValue: serverTier), tier != .free {
                serverConfirmedTier = tier
                let period = profile.subscription_period.flatMap { ProPeriod(rawValue: $0) }
                updateTier(tier, period: period)
                print("[TierManager] Updated tier to \(tier.rawValue) (period: \(period?.rawValue ?? "n/a")) from server")
            } else {
                print("[TierManager] Server tier is free or nil — no upgrade")
            }

            updatePowerAddon(profile.has_power_addon ?? false)
        } catch {
            print("[TierManager] Failed to check subscription status: \(error)")
        }
    }

    private func fetchFoundersSpotsCount() async {
        do {
            struct CountResult: Decodable {
                let count: Int
            }

            let _: [CountResult] = try await SupabaseManager.shared.client
                .from("user_profiles")
                .select("*", head: true, count: .exact)
                .eq("is_founding_member", value: true)
                .execute()
                .value

            // The count comes from the response header, not the body
            // For now, use a simple query
        } catch {
            // Non-critical — UI will show "limited spots" without exact count
        }
    }

    // MARK: - Gate Checks

    func canCreateNote(currentCount: Int) -> Bool {
        guard let max = limits.maxNotes else { return true }
        return currentCount < max
    }

    func canUseAI() -> Bool {
        resetIfNewMonth()
        return creditsUsedThisMonth < maxCreditsPerMonth
    }

    func canUseFeature(_ feature: GatedFeature) -> Bool {
        switch feature {
        case .aiWorkspace: return limits.aiWorkspace
        case .cloudSync: return limits.cloudSync
        case .commits: return limits.commits
        case .shareLinks: return limits.shareLinks
        case .semanticSearch: return limits.semanticSearch
        case .fullInsights: return limits.fullInsights
        default: return true
        }
    }

    @discardableResult
    func requireFeature(_ feature: GatedFeature) -> Bool {
        if canUseFeature(feature) { return true }
        paywallFeature = feature
        showPaywall = true
        return false
    }

    @discardableResult
    func requireNoteCreation(currentCount: Int) -> Bool {
        if canCreateNote(currentCount: currentCount) { return true }
        paywallFeature = .notes
        showPaywall = true
        return false
    }

    @discardableResult
    func requireAI() -> Bool {
        if canUseAI() { return true }
        paywallFeature = .aiActions
        showPaywall = true
        return false
    }

    // MARK: - Credit Counting

    /// Record a raw token count from an AI call. Converted to Credits using
    /// `Credits.tokensPerCredit`. This is a local optimistic update; the
    /// authoritative value is reconciled from `usage_log` via `syncCreditUsage`.
    func recordTokenUsage(_ tokens: Int) {
        resetIfNewMonth()
        let credits = Credits.credits(fromTokens: tokens)
        guard credits > 0 else { return }
        creditsUsedThisMonth += credits
        UserDefaults.standard.set(creditsUsedThisMonth, forKey: Keys.creditsThisMonth)
    }

    /// Returns the canonical "month key" for the current calendar month in UTC
    /// (e.g. `"2026-04"`). Resets fire when this key changes.
    private static func currentMonthKey(for date: Date = Date()) -> String {
        let cal = Calendar(identifier: .gregorian)
        var c = cal
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        let comps = c.dateComponents([.year, .month], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        return String(format: "%04d-%02d", y, m)
    }

    func resetIfNewMonth() {
        let nowKey = Self.currentMonthKey()
        let storedKey = UserDefaults.standard.string(forKey: Keys.creditsMonth) ?? ""
        if storedKey != nowKey {
            creditsUsedThisMonth = 0
            UserDefaults.standard.set(0, forKey: Keys.creditsThisMonth)
            UserDefaults.standard.set(nowKey, forKey: Keys.creditsMonth)
        }
    }

    /// Sync credit usage from the server (`usage_log` table, summed for the current month).
    func syncCreditUsage() async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id.uuidString.lowercased() else { return }

        resetIfNewMonth()

        // Start of current month, UTC
        let cal = Calendar(identifier: .gregorian)
        var utc = cal
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let comps = utc.dateComponents([.year, .month], from: Date())
        guard let monthStart = utc.date(from: comps) else { return }
        let monthStartISO = ISO8601DateFormatter().string(from: monthStart)

        do {
            struct UsageRow: Decodable {
                let input_tokens: Int
                let output_tokens: Int
            }

            let rows: [UsageRow] = try await SupabaseManager.shared.client
                .from("usage_log")
                .select("input_tokens, output_tokens")
                .eq("user_id", value: userId)
                .gte("created_at", value: monthStartISO)
                .execute()
                .value

            let totalTokens = rows.reduce(0) { $0 + $1.input_tokens + $1.output_tokens }
            let totalCredits = Credits.credits(fromTokens: totalTokens)
            creditsUsedThisMonth = totalCredits
            UserDefaults.standard.set(totalCredits, forKey: Keys.creditsThisMonth)
        } catch {
            print("[TierManager] Failed to sync credit usage: \(error)")
        }
    }

    // MARK: - Display Helpers

    var creditsRemaining: Int {
        max(0, maxCreditsPerMonth - creditsUsedThisMonth)
    }

    /// Date the credit meter refills (the 1st of next month, UTC).
    var creditsRefillDate: Date {
        let cal = Calendar(identifier: .gregorian)
        var utc = cal
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        var comps = utc.dateComponents([.year, .month], from: Date())
        comps.month = (comps.month ?? 1) + 1
        comps.day = 1
        return utc.date(from: comps) ?? Date()
    }

    static func formatCreditCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let value = Double(count) / 1_000_000.0
            return String(format: "%.1fM", value)
        } else if count >= 10_000 {
            let value = Double(count) / 1_000.0
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(value))K"
                : String(format: "%.1fK", value)
        }
        return "\(count)"
    }

    var tierDisplayName: String {
        switch currentTier {
        case .free: return "Free"
        case .pro:
            switch proPeriod {
            case .annual: return "Pro (Annual)"
            case .monthly, .none: return "Pro"
            }
        case .founding: return "Founder"
        }
    }
}
