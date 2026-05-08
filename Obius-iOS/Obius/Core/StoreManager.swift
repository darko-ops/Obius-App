import Foundation
import RevenueCat

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    // MARK: - Constants

    static let entitlementID = "Obius Pro"
    /// Separately-sold add-on that grants an extra 1,000 Credits/month on top of Pro.
    /// Configure in RevenueCat as a non-blocking entitlement on a $9.99/mo product
    /// (suggested product ID prefix: `obius_power_addon`).
    static let powerAddonEntitlementID = "Obius Power"

    // MARK: - Product Identifiers
    //
    // App Store product IDs we ship. Exact-match detection takes precedence over
    // the substring-based fallback in `syncTier(from:)`, so a future product
    // named e.g. `pro_monthly_promo` doesn't get mis-bucketed.
    static let monthlyProductID = "pro_monthly"
    static let foundersProductID = "pro_founder"

    // MARK: - State

    @Published private(set) var currentOffering: Offering?
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var isLoading = false

    var hasProEntitlement: Bool {
        customerInfo?.entitlements[Self.entitlementID]?.isActive == true
    }

    var hasPowerAddonEntitlement: Bool {
        customerInfo?.entitlements[Self.powerAddonEntitlementID]?.isActive == true
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

    /// The Power Add-on package — looked up by custom identifier on the active
    /// offering. Set the package identifier to `power_addon` (or include the
    /// substring "power") in RevenueCat.
    var powerAddonPackage: Package? {
        guard let offering = currentOffering else { return nil }
        return offering.availablePackages.first { pkg in
            let id = pkg.identifier.lowercased()
            let prod = pkg.storeProduct.productIdentifier.lowercased()
            return id.contains("power") || prod.contains("power_addon") || prod.contains("power-addon")
        }
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

        // Power Add-on is independent of Pro/Founders — sync it regardless.
        let powerActive = info.entitlements[Self.powerAddonEntitlementID]?.isActive == true
        TierManager.shared.updatePowerAddon(powerActive)

        guard let entitlement = info.entitlements[Self.entitlementID],
              entitlement.isActive else {
            // Don't downgrade if Supabase already confirmed a paid tier
            // (handles macOS where StoreKit may not have an active account)
            if !TierManager.shared.isFoundingMember &&
               TierManager.shared.serverConfirmedTier == nil {
                TierManager.shared.updateTier(.free)
            }
            // Push add-on state in case it changed independently
            Task { await Self.syncAddonToServer(active: powerActive) }
            return
        }

        // Detect Founders plan — exact-match our shipped ID first, then fall
        // back to substring detection for legacy / sandbox / lifetime SKUs.
        let productId = entitlement.productIdentifier.lowercased()
        let tier: Tier
        var period: ProPeriod? = nil
        if productId == Self.foundersProductID
            || productId.contains("founding")
            || productId.contains("founder")
            || productId.contains("lifetime") {
            TierManager.shared.isFoundingMember = true
            UserDefaults.standard.set(true, forKey: "obius_is_founding_member")
            tier = .founding
        } else {
            tier = .pro
            // Exact-match our shipped product IDs first, then fall back to
            // substring detection for legacy / sandbox / future test SKUs.
            if productId == Self.monthlyProductID {
                period = .monthly
            } else if productId.contains("annual") || productId.contains("yearly") || productId.contains("year") {
                period = .annual
            } else {
                period = .monthly
            }
        }
        TierManager.shared.updateTier(tier, period: period)

        // Write confirmed tier to Supabase so other devices (macOS) can read it
        // even if the RevenueCat webhook hasn't fired
        Task {
            await Self.syncTierToServer(
                tier: tier,
                period: period,
                hasPowerAddon: powerActive,
                productId: entitlement.productIdentifier,
                expiresAt: entitlement.expirationDate
            )
        }
    }

    /// Push the locally-confirmed tier to Supabase user_profiles.
    /// Acts as a client-side fallback for the RevenueCat webhook.
    private static func syncTierToServer(
        tier: Tier,
        period: ProPeriod?,
        hasPowerAddon: Bool,
        productId: String,
        expiresAt: Date?
    ) async {
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

        if let period, tier == .pro {
            update["subscription_period"] = period.rawValue
        }

        update["has_power_addon"] = hasPowerAddon ? "true" : "false"

        do {
            try await SupabaseManager.shared.client
                .from("user_profiles")
                .update(update)
                .eq("id", value: userId)
                .execute()
            print("[StoreManager] Synced tier '\(tier.rawValue)' (period=\(period?.rawValue ?? "n/a"), power=\(hasPowerAddon)) to server for \(userId)")
        } catch {
            print("[StoreManager] Failed to sync tier to server: \(error)")
        }
    }

    /// Push only the Power Add-on state (used when the user is on Free/grandfathered
    /// and toggles the add-on without changing their main entitlement).
    private static func syncAddonToServer(active: Bool) async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id.uuidString.lowercased() else {
            return
        }
        do {
            try await SupabaseManager.shared.client
                .from("user_profiles")
                .update([
                    "has_power_addon": active ? "true" : "false",
                    "updated_at": ISO8601DateFormatter().string(from: Date()),
                ])
                .eq("id", value: userId)
                .execute()
        } catch {
            print("[StoreManager] Failed to sync add-on state: \(error)")
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
