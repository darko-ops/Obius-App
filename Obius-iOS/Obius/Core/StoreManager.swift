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
        guard let entitlement = info.entitlements[Self.entitlementID],
              entitlement.isActive else {
            if !TierManager.shared.isFoundingMember {
                TierManager.shared.updateTier(.free)
            }
            return
        }

        // Detect Founders plan — matches the rc_lifetime package
        let productId = entitlement.productIdentifier.lowercased()
        if productId.contains("founding") || productId.contains("founder") || productId.contains("lifetime") {
            TierManager.shared.isFoundingMember = true
            UserDefaults.standard.set(true, forKey: "obius_is_founding_member")
            TierManager.shared.updateTier(.founding)
        } else {
            TierManager.shared.updateTier(.pro)
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
