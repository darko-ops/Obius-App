import Foundation
import Combine
import Supabase

// MARK: - Tier

enum Tier: String, CaseIterable {
    case free
    case pro
    case founding
}

// MARK: - TierLimits

struct TierLimits {
    let maxNotes: Int?          // nil = unlimited
    let maxSectionsPerNote: Int?
    let maxModules: Int?
    let maxHandles: Int?
    let maxEchoes: Int?
    let maxAIActionsPerDay: Int
    let cloudSync: Bool
    let commits: Bool
    let shareLinks: Bool
    let semanticSearch: Bool
    let fullInsights: Bool
    let aiWorkspace: Bool

    static let free = TierLimits(
        maxNotes: 25,
        maxSectionsPerNote: 50,
        maxModules: 2,
        maxHandles: 3,
        maxEchoes: 3,
        maxAIActionsPerDay: 10,
        cloudSync: false,
        commits: false,
        shareLinks: false,
        semanticSearch: false,
        fullInsights: false,
        aiWorkspace: false
    )

    static let pro = TierLimits(
        maxNotes: nil,
        maxSectionsPerNote: nil,
        maxModules: nil,
        maxHandles: nil,
        maxEchoes: nil,
        maxAIActionsPerDay: 100,
        cloudSync: true,
        commits: true,
        shareLinks: true,
        semanticSearch: true,
        fullInsights: true,
        aiWorkspace: true
    )

    static let founding = TierLimits(
        maxNotes: nil,
        maxSectionsPerNote: nil,
        maxModules: nil,
        maxHandles: nil,
        maxEchoes: nil,
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
    case modules
    case handles
    case echoes
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
        case .modules: return "Projects"
        case .handles: return "Loops"
        case .echoes: return "Echoes"
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
        case .notes: return "You've reached the free limit of 25 notes. Upgrade to create unlimited notes."
        case .modules: return "Free accounts can create up to 2 projects. Upgrade for unlimited projects."
        case .handles: return "Free accounts can create up to 3 loops. Upgrade for unlimited loops."
        case .echoes: return "Free accounts can set up to 3 echoes. Upgrade for unlimited echoes."
        case .aiActions: return "You've used all your AI actions for today. Upgrade for more."
        case .aiWorkspace: return "The AI workspace is a Pro feature. Upgrade to unlock it."
        case .cloudSync: return "Cloud sync is a Pro feature. Upgrade to sync across devices."
        case .commits: return "Saving versions is a Pro feature. Upgrade to track your note history."
        case .shareLinks: return "Sharing is a Pro feature. Upgrade to share your notes."
        case .semanticSearch: return "Semantic search is a Pro feature. Upgrade for AI-powered search."
        case .fullInsights: return "Advanced insights are a Pro feature. Upgrade to see all insight types."
        }
    }

    var icon: String {
        switch self {
        case .notes: return "note.text"
        case .modules: return "folder"
        case .handles: return "at"
        case .echoes: return "bell"
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

    @Published private(set) var currentTier: Tier = .free
    @Published var showPaywall = false
    @Published var paywallFeature: GatedFeature?
    @Published private(set) var aiActionsUsedToday: Int = 0
    @Published private(set) var isFoundingMember: Bool = false

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

                // During beta: founding members get Pro for free
                if currentTier == .free {
                    updateTier(.founding)
                }
            }
        } catch {
            print("[TierManager] Failed to check founding member status: \(error)")
        }
    }

    // MARK: - Gate Checks

    func canCreateNote(currentCount: Int) -> Bool {
        guard let max = limits.maxNotes else { return true }
        return currentCount < max
    }

    func canCreateModule(currentCount: Int) -> Bool {
        guard let max = limits.maxModules else { return true }
        return currentCount < max
    }

    func canCreateHandle(currentCount: Int) -> Bool {
        guard let max = limits.maxHandles else { return true }
        return currentCount < max
    }

    func canCreateEcho(activeCount: Int) -> Bool {
        guard let max = limits.maxEchoes else { return true }
        return activeCount < max
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

    /// Returns true if allowed. If blocked, shows paywall and returns false.
    @discardableResult
    func requireFeature(_ feature: GatedFeature) -> Bool {
        if canUseFeature(feature) { return true }
        paywallFeature = feature
        showPaywall = true
        return false
    }

    /// Returns true if allowed. If blocked, shows paywall and returns false.
    @discardableResult
    func requireNoteCreation(currentCount: Int) -> Bool {
        if canCreateNote(currentCount: currentCount) { return true }
        paywallFeature = .notes
        showPaywall = true
        return false
    }

    @discardableResult
    func requireModuleCreation(currentCount: Int) -> Bool {
        if canCreateModule(currentCount: currentCount) { return true }
        paywallFeature = .modules
        showPaywall = true
        return false
    }

    @discardableResult
    func requireHandleCreation(currentCount: Int) -> Bool {
        if canCreateHandle(currentCount: currentCount) { return true }
        paywallFeature = .handles
        showPaywall = true
        return false
    }

    @discardableResult
    func requireEchoCreation(activeCount: Int) -> Bool {
        if canCreateEcho(activeCount: activeCount) { return true }
        paywallFeature = .echoes
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
        case .founding: return "Founding Member"
        }
    }
}
