import Foundation
import Combine
import Supabase

// MARK: - Tier

enum Tier: String, CaseIterable {
    case free
    case pro       // Monthly ($5.99) or Annual ($47.99/yr)
    case founding  // Founders Plan ($3.99/mo forever, 200 spots)
}

// MARK: - TierLimits

struct TierLimits {
    let maxNotes: Int?          // nil = unlimited
    let maxSectionsPerNote: Int?
    let maxAIActionsPerDay: Int
    let cloudSync: Bool
    let commits: Bool
    let shareLinks: Bool
    let semanticSearch: Bool
    let fullInsights: Bool
    let aiWorkspace: Bool

    // Free: core app, single device, 50 notes
    static let free = TierLimits(
        maxNotes: 50,
        maxSectionsPerNote: nil,
        maxAIActionsPerDay: 10,
        cloudSync: false,
        commits: false,
        shareLinks: false,
        semanticSearch: false,
        fullInsights: false,
        aiWorkspace: false
    )

    // Pro: full access (Monthly or Annual billing)
    static let pro = TierLimits(
        maxNotes: nil,
        maxSectionsPerNote: nil,
        maxAIActionsPerDay: 100,
        cloudSync: true,
        commits: true,
        shareLinks: true,
        semanticSearch: true,
        fullInsights: true,
        aiWorkspace: true
    )

    // Founding: same as Pro + early access, badge, direct line
    static let founding = TierLimits(
        maxNotes: nil,
        maxSectionsPerNote: nil,
        maxAIActionsPerDay: 100,
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
        case .aiActions: return "AI Actions"
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
        case .aiActions: return "You've used all your AI actions for today. Upgrade for more."
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

    /// Total founders spots available
    static let foundersSpotsCap = 200

    @Published private(set) var currentTier: Tier = .free
    @Published var showPaywall = false
    @Published var paywallFeature: GatedFeature?
    @Published private(set) var aiActionsUsedToday: Int = 0
    @Published private(set) var isFoundingMember: Bool = false
    @Published private(set) var foundersSpotsTaken: Int = 0

    var foundersSpotsRemaining: Int {
        max(0, Self.foundersSpotsCap - foundersSpotsTaken)
    }

    var limits: TierLimits {
        switch currentTier {
        case .free: return .free
        case .pro: return .pro
        case .founding: return .founding
        }
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let tier = "obius_tier"
        static let isFoundingMember = "obius_is_founding_member"
        static let aiActionsToday = "obius_ai_actions_today"
        static let aiActionsDate = "obius_ai_actions_date"
    }

    private init() {
        loadPersistedState()
    }

    // MARK: - Initialization

    func initialize() async {
        loadPersistedState()
        resetIfNewDay()

        // Check RevenueCat entitlements
        await StoreManager.shared.refreshCustomerInfo()

        // Check founding member status from Supabase
        await checkFoundingMemberStatus()
        await fetchFoundersSpotsCount()
    }

    private func loadPersistedState() {
        if let rawTier = UserDefaults.standard.string(forKey: Keys.tier),
           let tier = Tier(rawValue: rawTier) {
            currentTier = tier
        }
        isFoundingMember = UserDefaults.standard.bool(forKey: Keys.isFoundingMember)
        aiActionsUsedToday = UserDefaults.standard.integer(forKey: Keys.aiActionsToday)
    }

    // MARK: - Tier Updates

    func updateTier(_ tier: Tier) {
        currentTier = tier
        UserDefaults.standard.set(tier.rawValue, forKey: Keys.tier)
    }

    // MARK: - Founding Member

    private func checkFoundingMemberStatus() async {
        guard SupabaseManager.shared.isAuthenticated else { return }

        do {
            struct ProfileRow: Decodable {
                let is_founding_member: Bool?
            }

            guard let userId = SupabaseManager.shared.currentUser?.id.uuidString.lowercased() else { return }

            let profiles: [ProfileRow] = try await SupabaseManager.shared.client
                .from("user_profiles")
                .select("is_founding_member")
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value

            if let profile = profiles.first, profile.is_founding_member == true {
                isFoundingMember = true
                UserDefaults.standard.set(true, forKey: Keys.isFoundingMember)

                if currentTier == .free {
                    updateTier(.founding)
                }
            }
        } catch {
            print("[TierManager] Failed to check founding member status: \(error)")
        }
    }

    private func fetchFoundersSpotsCount() async {
        do {
            struct CountResult: Decodable {
                let count: Int
            }

            let result: [CountResult] = try await SupabaseManager.shared.client
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
        resetIfNewDay()
        return aiActionsUsedToday < limits.maxAIActionsPerDay
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

    // MARK: - AI Action Counting

    func recordAIAction() {
        resetIfNewDay()
        aiActionsUsedToday += 1
        UserDefaults.standard.set(aiActionsUsedToday, forKey: Keys.aiActionsToday)
    }

    func resetIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let todayString = ISO8601DateFormatter().string(from: today)

        let storedDate = UserDefaults.standard.string(forKey: Keys.aiActionsDate) ?? ""
        if storedDate != todayString {
            aiActionsUsedToday = 0
            UserDefaults.standard.set(0, forKey: Keys.aiActionsToday)
            UserDefaults.standard.set(todayString, forKey: Keys.aiActionsDate)
        }
    }

    // MARK: - Display Helpers

    var aiActionsRemaining: Int {
        max(0, limits.maxAIActionsPerDay - aiActionsUsedToday)
    }

    var tierDisplayName: String {
        switch currentTier {
        case .free: return "Free"
        case .pro: return "Pro"
        case .founding: return "Founder"
        }
    }
}
