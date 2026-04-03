import XCTest
@testable import Obius

final class TierGatingTests: XCTestCase {

    // MARK: - Tier Limits

    func testFreeTier_limits() {
        let limits = TierLimits.free
        XCTAssertEqual(limits.maxNotes, 50)
        XCTAssertNil(limits.maxSectionsPerNote)
        XCTAssertEqual(limits.maxTokensPerDay, 50_000)
        XCTAssertFalse(limits.cloudSync)
        XCTAssertFalse(limits.commits)
        XCTAssertFalse(limits.shareLinks)
        XCTAssertFalse(limits.semanticSearch)
        XCTAssertFalse(limits.fullInsights)
        XCTAssertFalse(limits.aiWorkspace)
    }

    func testProTier_limits() {
        let limits = TierLimits.pro
        XCTAssertNil(limits.maxNotes, "Pro should have unlimited notes")
        XCTAssertEqual(limits.maxTokensPerDay, 500_000)
        XCTAssertTrue(limits.cloudSync)
        XCTAssertTrue(limits.commits)
        XCTAssertTrue(limits.shareLinks)
        XCTAssertTrue(limits.semanticSearch)
        XCTAssertTrue(limits.fullInsights)
        XCTAssertTrue(limits.aiWorkspace)
    }

    func testFoundingTier_limits() {
        let limits = TierLimits.founding
        XCTAssertNil(limits.maxNotes, "Founding should have unlimited notes")
        XCTAssertEqual(limits.maxTokensPerDay, 500_000)
        XCTAssertTrue(limits.cloudSync)
        XCTAssertTrue(limits.commits)
        XCTAssertTrue(limits.shareLinks)
        XCTAssertTrue(limits.semanticSearch)
        XCTAssertTrue(limits.fullInsights)
        XCTAssertTrue(limits.aiWorkspace)
    }

    func testFoundingTier_matchesPro() {
        // Founding members get all Pro features
        let pro = TierLimits.pro
        let founding = TierLimits.founding
        XCTAssertEqual(pro.maxNotes, founding.maxNotes)
        XCTAssertEqual(pro.maxTokensPerDay, founding.maxTokensPerDay)
        XCTAssertEqual(pro.cloudSync, founding.cloudSync)
        XCTAssertEqual(pro.commits, founding.commits)
        XCTAssertEqual(pro.shareLinks, founding.shareLinks)
        XCTAssertEqual(pro.semanticSearch, founding.semanticSearch)
        XCTAssertEqual(pro.fullInsights, founding.fullInsights)
        XCTAssertEqual(pro.aiWorkspace, founding.aiWorkspace)
    }

    // MARK: - Note Creation Gating

    func testFree_canCreateNote_underLimit() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)
        let result = await manager.canCreateNote(currentCount: 10)
        XCTAssertTrue(result)
    }

    func testFree_canCreateNote_atLimit() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)
        let result = await manager.canCreateNote(currentCount: 50)
        XCTAssertFalse(result, "Free tier should block note creation at 50 notes")
    }

    func testFree_canCreateNote_overLimit() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)
        let result = await manager.canCreateNote(currentCount: 100)
        XCTAssertFalse(result)
    }

    func testPro_canCreateNote_noLimit() async {
        let manager = TierManager.shared
        await manager.updateTier(.pro)
        let result = await manager.canCreateNote(currentCount: 1000)
        XCTAssertTrue(result, "Pro tier should allow unlimited notes")
    }

    func testFounding_canCreateNote_noLimit() async {
        let manager = TierManager.shared
        await manager.updateTier(.founding)
        let result = await manager.canCreateNote(currentCount: 9999)
        XCTAssertTrue(result, "Founding tier should allow unlimited notes")
    }

    // MARK: - Feature Gating

    func testFree_cannotUseCloudSync() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)
        let result = await manager.canUseFeature(.cloudSync)
        XCTAssertFalse(result)
    }

    func testFree_cannotUseCommits() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)
        let result = await manager.canUseFeature(.commits)
        XCTAssertFalse(result)
    }

    func testFree_cannotUseShareLinks() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)
        let result = await manager.canUseFeature(.shareLinks)
        XCTAssertFalse(result)
    }

    func testFree_cannotUseSemanticSearch() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)
        let result = await manager.canUseFeature(.semanticSearch)
        XCTAssertFalse(result)
    }

    func testFree_cannotUseAIWorkspace() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)
        let result = await manager.canUseFeature(.aiWorkspace)
        XCTAssertFalse(result)
    }

    func testFree_cannotUseFullInsights() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)
        let result = await manager.canUseFeature(.fullInsights)
        XCTAssertFalse(result)
    }

    func testPro_canUseAllFeatures() async {
        let manager = TierManager.shared
        await manager.updateTier(.pro)

        let features: [GatedFeature] = [.cloudSync, .commits, .shareLinks, .semanticSearch, .aiWorkspace, .fullInsights]
        for feature in features {
            let result = await manager.canUseFeature(feature)
            XCTAssertTrue(result, "Pro should have access to \(feature.rawValue)")
        }
    }

    func testFounding_canUseAllFeatures() async {
        let manager = TierManager.shared
        await manager.updateTier(.founding)

        let features: [GatedFeature] = [.cloudSync, .commits, .shareLinks, .semanticSearch, .aiWorkspace, .fullInsights]
        for feature in features {
            let result = await manager.canUseFeature(feature)
            XCTAssertTrue(result, "Founding should have access to \(feature.rawValue)")
        }
    }

    // MARK: - AI Token Gating

    func testFree_canUseAI_beforeLimit() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)
        // Reset tokens for clean state
        UserDefaults.standard.set(0, forKey: "obius_tokens_today")
        await manager.resetIfNewDay()

        let result = await manager.canUseAI()
        XCTAssertTrue(result)
    }

    func testTokenUsage_recordsCorrectly() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)
        UserDefaults.standard.set(0, forKey: "obius_tokens_today")

        await manager.recordTokenUsage(1000)
        let used = await manager.tokensUsedToday
        XCTAssertEqual(used, 1000)

        await manager.recordTokenUsage(500)
        let usedAfter = await manager.tokensUsedToday
        XCTAssertEqual(usedAfter, 1500)
    }

    // MARK: - Paywall Trigger

    func testRequireFeature_showsPaywall_whenGated() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)

        let result = await manager.requireFeature(.cloudSync)
        XCTAssertFalse(result)

        let showsPaywall = await manager.showPaywall
        XCTAssertTrue(showsPaywall, "requireFeature should trigger paywall for gated feature")

        let feature = await manager.paywallFeature
        XCTAssertEqual(feature, .cloudSync)
    }

    func testRequireFeature_doesNotShowPaywall_whenAllowed() async {
        let manager = TierManager.shared
        await manager.updateTier(.pro)
        await MainActor.run { manager.showPaywall = false }

        let result = await manager.requireFeature(.cloudSync)
        XCTAssertTrue(result)

        let showsPaywall = await manager.showPaywall
        XCTAssertFalse(showsPaywall)
    }

    func testRequireNoteCreation_showsPaywall_atLimit() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)

        let result = await manager.requireNoteCreation(currentCount: 50)
        XCTAssertFalse(result)

        let feature = await manager.paywallFeature
        XCTAssertEqual(feature, .notes)
    }

    // MARK: - Tier Enum

    func testTier_allCases() {
        XCTAssertEqual(Tier.allCases.count, 3)
        XCTAssertTrue(Tier.allCases.contains(.free))
        XCTAssertTrue(Tier.allCases.contains(.pro))
        XCTAssertTrue(Tier.allCases.contains(.founding))
    }

    func testTier_rawValues() {
        XCTAssertEqual(Tier.free.rawValue, "free")
        XCTAssertEqual(Tier.pro.rawValue, "pro")
        XCTAssertEqual(Tier.founding.rawValue, "founding")
    }

    // MARK: - GatedFeature Enum

    func testGatedFeature_allCases() {
        XCTAssertEqual(GatedFeature.allCases.count, 8)
    }

    func testGatedFeature_hasDisplayNames() {
        for feature in GatedFeature.allCases {
            XCTAssertFalse(feature.displayName.isEmpty, "\(feature.rawValue) should have a display name")
        }
    }

    func testGatedFeature_hasUpgradeMessages() {
        for feature in GatedFeature.allCases {
            XCTAssertFalse(feature.upgradeMessage.isEmpty, "\(feature.rawValue) should have an upgrade message")
        }
    }

    func testGatedFeature_hasIcons() {
        for feature in GatedFeature.allCases {
            XCTAssertFalse(feature.icon.isEmpty, "\(feature.rawValue) should have an icon")
        }
    }

    // MARK: - Founders Spots

    func testFoundersSpotsCap_is200() {
        XCTAssertEqual(TierManager.foundersSpotsCap, 200)
    }

    // MARK: - Tier Update Persistence

    func testUpdateTier_changesToPro() async {
        let manager = TierManager.shared
        await manager.updateTier(.pro)
        let tier = await manager.currentTier
        XCTAssertEqual(tier, .pro)
    }

    func testUpdateTier_changesToFree() async {
        let manager = TierManager.shared
        await manager.updateTier(.free)
        let tier = await manager.currentTier
        XCTAssertEqual(tier, .free)
    }

    func testUpdateTier_changesToFounding() async {
        let manager = TierManager.shared
        await manager.updateTier(.founding)
        let tier = await manager.currentTier
        XCTAssertEqual(tier, .founding)
    }
}
