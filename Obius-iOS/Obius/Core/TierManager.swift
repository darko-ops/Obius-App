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
    let baseCreditsPerMonth: Int    // does NOT include any consumable Power Pack top-ups
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

    /// Each consumable Power Pack purchase (`credits_pack_10`) grants this many
    /// extra Credits to the current monthly cycle.
    static let powerPackCreditsPerPurchase = 1_000

    @Published private(set) var currentTier: Tier = .free
    @Published private(set) var proPeriod: ProPeriod? = nil
    /// Bonus Credits granted this monthly cycle via consumable Power Pack
    /// purchases. Resets to 0 on the 1st of each UTC month alongside
    /// `creditsUsedThisMonth`. May be incremented multiple times per cycle.
    @Published private(set) var bonusCreditsThisMonth: Int = 0
    @Published var showPaywall = false
    @Published var paywallFeature: GatedFeature?
    /// Dedicated paywall for the Power Pack (`credits_pack_10`) consumable.
    /// Triggered from Settings → Subscription's "Buy" button, and from
    /// `requireAI()` once a Pro/Founder user has burned through their monthly
    /// Credits (Free users still see the standard plans paywall — they need a
    /// base plan first).
    @Published var showPowerPackPaywall = false
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

    /// Effective monthly credit cap = base tier allotment + this cycle's bonus
    /// from any Power Pack purchases.
    var maxCreditsPerMonth: Int {
        limits.baseCreditsPerMonth + bonusCreditsThisMonth
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let tier = "obius_tier"
        static let proPeriod = "obius_pro_period"
        static let bonusCredits = "obius_bonus_credits_this_month"
        static let bonusCreditsMonth = "obius_bonus_credits_month_key"
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
        bonusCreditsThisMonth = 0
        isFoundingMember = false
        creditsUsedThisMonth = 0
        foundersSpotsTaken = 0
        serverConfirmedTier = nil

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.tier)
        defaults.removeObject(forKey: Keys.proPeriod)
        defaults.removeObject(forKey: Keys.bonusCredits)
        defaults.removeObject(forKey: Keys.bonusCreditsMonth)
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
        // Bonus Credits are scoped to the current cycle — only honor the stored
        // value if it was written during the same UTC month we're in now.
        let storedBonusMonth = UserDefaults.standard.string(forKey: Keys.bonusCreditsMonth) ?? ""
        if storedBonusMonth == Self.currentMonthKey() {
            bonusCreditsThisMonth = UserDefaults.standard.integer(forKey: Keys.bonusCredits)
        } else {
            bonusCreditsThisMonth = 0
        }
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

    /// Grant a Power Pack top-up to the current cycle. Idempotency is the
    /// caller's responsibility — `StoreManager` tracks processed RevenueCat
    /// transaction IDs so a restore or re-launch won't double-credit.
    func addBonusCredits(_ amount: Int) {
        guard amount > 0 else { return }
        resetIfNewMonth()
        bonusCreditsThisMonth += amount
        UserDefaults.standard.set(bonusCreditsThisMonth, forKey: Keys.bonusCredits)
        UserDefaults.standard.set(Self.currentMonthKey(), forKey: Keys.bonusCreditsMonth)
    }

    /// Server-authoritative refresh of the cycle's bonus balance. Called after
    /// `checkFoundingMemberStatus` reads `user_profiles.bonus_credits_this_month`.
    /// If the server's month key matches the current cycle, replaces local
    /// state; otherwise treats the value as expired and zeros it locally.
    func applyServerBonusCredits(amount: Int, monthKey: String?) {
        let now = Self.currentMonthKey()
        let cycleAmount = (monthKey == now) ? max(0, amount) : 0
        bonusCreditsThisMonth = cycleAmount
        UserDefaults.standard.set(cycleAmount, forKey: Keys.bonusCredits)
        UserDefaults.standard.set(now, forKey: Keys.bonusCreditsMonth)
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
                let bonus_credits_this_month: Int?
                let bonus_credits_month_key: String?
            }

            guard let userId = SupabaseManager.shared.currentUser?.id.uuidString.lowercased() else {
                print("[TierManager] No current user ID")
                return
            }

            print("[TierManager] Checking subscription for user: \(userId)")

            let profiles: [ProfileRow] = try await SupabaseManager.shared.client
                .from("user_profiles")
                .select("is_founding_member, subscription_tier, subscription_period, bonus_credits_this_month, bonus_credits_month_key")
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value

            guard let profile = profiles.first else {
                print("[TierManager] No profile row found in user_profiles")
                return
            }

            print("[TierManager] Server tier: \(profile.subscription_tier ?? "nil"), period: \(profile.subscription_period ?? "nil"), founding: \(profile.is_founding_member ?? false), bonus: \(profile.bonus_credits_this_month ?? 0) (month \(profile.bonus_credits_month_key ?? "nil"))")

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

            applyServerBonusCredits(
                amount: profile.bonus_credits_this_month ?? 0,
                monthKey: profile.bonus_credits_month_key
            )
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
        // Pro/Founder users with a live plan don't need a plan upsell — route
        // them straight to the Power Pack consumable. Free users still need to
        // pick a base plan, so fall through to the standard paywall.
        if currentTier != .free {
            showPowerPackPaywall = true
        } else {
            paywallFeature = .aiActions
            showPaywall = true
        }
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
    /// (e.g. `"2026-04"`). Resets fire when this key changes. Exposed via
    /// `currentMonthKeyForBonus()` so the server-sync code can stamp the same
    /// key it would have read locally.
    static func currentMonthKey(for date: Date = Date()) -> String {
        let cal = Calendar(identifier: .gregorian)
        var c = cal
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        let comps = c.dateComponents([.year, .month], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        return String(format: "%04d-%02d", y, m)
    }

    /// Public accessor for the bonus-credits cycle key. `StoreManager.syncBonusCreditsToServer`
    /// writes this alongside the bonus integer so the server can decide whether
    /// the stored value still applies to the current cycle.
    static func currentMonthKeyForBonus() -> String { currentMonthKey() }

    func resetIfNewMonth() {
        let nowKey = Self.currentMonthKey()
        let storedKey = UserDefaults.standard.string(forKey: Keys.creditsMonth) ?? ""
        if storedKey != nowKey {
            creditsUsedThisMonth = 0
            UserDefaults.standard.set(0, forKey: Keys.creditsThisMonth)
            UserDefaults.standard.set(nowKey, forKey: Keys.creditsMonth)
        }
        // Power Pack top-ups are bound to the same monthly cycle.
        let storedBonusKey = UserDefaults.standard.string(forKey: Keys.bonusCreditsMonth) ?? ""
        if storedBonusKey != nowKey {
            bonusCreditsThisMonth = 0
            UserDefaults.standard.set(0, forKey: Keys.bonusCredits)
            UserDefaults.standard.set(nowKey, forKey: Keys.bonusCreditsMonth)
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
