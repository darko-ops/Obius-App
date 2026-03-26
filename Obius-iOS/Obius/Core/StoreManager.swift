import Foundation
import RevenueCat

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    // MARK: - Constants

    static let entitlementID = "Obius Pro"

    // MARK: - State

    @Published private(set) var currentOffering: Offering?
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var isLoading = false

    var hasProEntitlement: Bool {
        customerInfo?.entitlements[Self.entitlementID]?.isActive == true
    }

    private init() {}

    // MARK: - Initialization

    func initialize() async {
        Purchases.shared.delegate = RCDelegateProxy.shared
        await loadOfferings()
        await refreshCustomerInfo()
    }

    // MARK: - Offerings

    private func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
        } catch {
            print("[StoreManager] Failed to load offerings: \(error)")
        }
    }

    // MARK: - Packages

    var monthlyPackage: Package? {
        currentOffering?.monthly
    }

    var yearlyPackage: Package? {
        currentOffering?.annual
    }

    var lifetimePackage: Package? {
        currentOffering?.lifetime
    }

    // MARK: - Purchase

    func purchase(_ package: Package) async throws -> CustomerInfo {
        isLoading = true
        defer { isLoading = false }

        let result: PurchaseResultData
        do {
            result = try await Purchases.shared.purchase(package: package)
        } catch {
            SubscriptionAnalytics.shared.purchaseFailed(productId: package.storeProduct.productIdentifier, error: error.localizedDescription)
            throw error
        }

        if !result.userCancelled {
            customerInfo = result.customerInfo
            syncTier(from: result.customerInfo)
            SubscriptionAnalytics.shared.purchaseCompleted(productId: package.storeProduct.productIdentifier)
        }

        return result.customerInfo
    }

    // MARK: - Restore

    func restorePurchases() async throws -> CustomerInfo {
        isLoading = true
        defer { isLoading = false }

        let info = try await Purchases.shared.restorePurchases()
        customerInfo = info
        syncTier(from: info)
        if hasProEntitlement {
            SubscriptionAnalytics.shared.restoreCompleted()
        }
        return info
    }

    // MARK: - Customer Info

    func refreshCustomerInfo() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            customerInfo = info
            syncTier(from: info)
        } catch {
            print("[StoreManager] Failed to refresh customer info: \(error)")
        }
    }

    // MARK: - Identify User

    func identify(userId: String) async {
        do {
            let (info, _) = try await Purchases.shared.logIn(userId)
            customerInfo = info
            syncTier(from: info)
        } catch {
            print("[StoreManager] Failed to identify user: \(error)")
        }
    }

    func logout() async {
        let info = try? await Purchases.shared.logOut()
        customerInfo = info
        if let info { syncTier(from: info) }
    }

    // MARK: - Update from Delegate

    func handleUpdatedCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
        syncTier(from: info)
    }

    // MARK: - Tier Sync

    func syncTier(from info: CustomerInfo) {
        #if DEBUG
        let allEntitlements = info.entitlements.all.map { "\($0.key): active=\($0.value.isActive), product=\($0.value.productIdentifier)" }
        print("[StoreManager] Entitlements: \(allEntitlements.isEmpty ? "(none)" : allEntitlements.joined(separator: ", "))")
        #endif

        guard let entitlement = info.entitlements[Self.entitlementID],
              entitlement.isActive else {
            // Don't downgrade if Supabase already confirmed a paid tier
            // (handles macOS where StoreKit may not have an active account)
            if !TierManager.shared.isFoundingMember &&
               TierManager.shared.serverConfirmedTier == nil {
                TierManager.shared.updateTier(.free)
            }
            return
        }

        // Detect Founders plan — matches the rc_lifetime package
        let productId = entitlement.productIdentifier.lowercased()
        let tier: Tier
        if productId.contains("founding") || productId.contains("founder") || productId.contains("lifetime") {
            TierManager.shared.isFoundingMember = true
            UserDefaults.standard.set(true, forKey: "obius_is_founding_member")
            tier = .founding
        } else {
            tier = .pro
        }
        TierManager.shared.updateTier(tier)

        // Write confirmed tier to Supabase so other devices (macOS) can read it
        // even if the RevenueCat webhook hasn't fired
        Task {
            await Self.syncTierToServer(
                tier: tier,
                productId: entitlement.productIdentifier,
                expiresAt: entitlement.expirationDate
            )
        }
    }

    /// Push the locally-confirmed tier to Supabase user_profiles.
    /// Acts as a client-side fallback for the RevenueCat webhook.
    private static func syncTierToServer(tier: Tier, productId: String, expiresAt: Date?) async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id.uuidString.lowercased() else {
            return
        }

        var update: [String: String] = [
            "subscription_tier": tier.rawValue,
            "subscription_product_id": productId,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]

        if let expiresAt {
            update["subscription_expires_at"] = ISO8601DateFormatter().string(from: expiresAt)
        }

        if tier == .founding {
            update["is_founding_member"] = "true"
        }

        do {
            try await SupabaseManager.shared.client
                .from("user_profiles")
                .update(update)
                .eq("id", value: userId)
                .execute()
            print("[StoreManager] Synced tier '\(tier.rawValue)' to server for \(userId)")
        } catch {
            print("[StoreManager] Failed to sync tier to server: \(error)")
        }
    }
}

// MARK: - RevenueCat Delegate

private class RCDelegateProxy: NSObject, PurchasesDelegate {
    static let shared = RCDelegateProxy()

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            StoreManager.shared.handleUpdatedCustomerInfo(customerInfo)
        }
    }
}
