import Foundation
import RevenueCat

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    // MARK: - Constants

    static let entitlementID = "Obius Pro"

    // MARK: - Product Identifiers
    //
    // App Store product IDs we ship. Exact-match detection takes precedence over
    // the substring-based fallback in `syncTier(from:)`, so a future product
    // named e.g. `pro_monthly_promo` doesn't get mis-bucketed.
    static let monthlyProductID = "pro_monthly"
    static let foundersProductID = "pro_founder"
    /// Power Pack — a *consumable* IAP (no entitlement, no auto-renewal).
    /// Each purchase grants +1,000 Credits for the current monthly cycle.
    /// Detected via `CustomerInfo.nonSubscriptionTransactions`.
    static let extraCreditsProductID = "credits_pack_10"

    // MARK: - State

    @Published private(set) var currentOffering: Offering?
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var isLoading = false

    /// Standalone fallback for the Power Pack consumable, fetched directly from
    /// StoreKit when the active RevenueCat offering doesn't include it as a
    /// Package. Consumables are commonly *not* bundled into the subscription
    /// offering, so the offering-based lookup alone leaves the paywall stuck on
    /// "Loading pricing…". This keeps the sheet functional regardless of how
    /// the dashboard is configured.
    @Published private(set) var powerAddonProductFallback: StoreProduct?

    var hasProEntitlement: Bool {
        customerInfo?.entitlements[Self.entitlementID]?.isActive == true
    }

    /// All Power Pack consumable purchases the user has ever made on this RC
    /// account (any month). Use `hasPurchasedPowerPackThisCycle` for the
    /// "did they buy one in the current month?" question.
    var powerPackTransactions: [NonSubscriptionTransaction] {
        (customerInfo?.nonSubscriptions ?? []).filter {
            $0.productIdentifier == Self.extraCreditsProductID
        }
    }

    /// Whether the user has at least one Power Pack purchase whose purchase
    /// date falls inside the current UTC month. Drives the "Buy another"
    /// label on the Settings row.
    var hasPurchasedPowerPackThisCycle: Bool {
        powerPackTransactions.contains(where: Self.isInCurrentUTCMonth)
    }

    private init() {}

    // MARK: - Initialization

    func initialize() async {
        Purchases.shared.delegate = RCDelegateProxy.shared
        await loadOfferings()
        // If the consumable isn't part of the offering, fetch it directly so
        // the Power Pack paywall has a price to render.
        if powerAddonPackage == nil {
            await loadPowerAddonProductFallback()
        }
        await refreshCustomerInfo()
    }

    // MARK: - Offerings

    private func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current

            #if DEBUG
            let allOfferingIds = offerings.all.keys.joined(separator: ", ")
            print("[StoreManager] RC offerings loaded — all: [\(allOfferingIds)], current: \(offerings.current?.identifier ?? "nil")")
            if let current = offerings.current {
                let pkgSummary = current.availablePackages.map { pkg in
                    "\(pkg.identifier) → \(pkg.storeProduct.productIdentifier) (\(pkg.storeProduct.localizedPriceString))"
                }
                if pkgSummary.isEmpty {
                    print("[StoreManager] Current offering has 0 packages")
                } else {
                    print("[StoreManager] Current offering packages:\n  - \(pkgSummary.joined(separator: "\n  - "))")
                }
            } else if offerings.all.isEmpty {
                print("[StoreManager] No offerings configured in RevenueCat for this project/key")
            } else {
                print("[StoreManager] Offerings exist but none is marked Current — set one in RevenueCat dashboard")
            }
            #endif
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

    /// The Power Pack consumable package, looked up on the active offering.
    /// Matches `credits_pack_10` exactly, or any package whose identifier /
    /// product ID flags it as a credit top-up.
    var powerAddonPackage: Package? {
        guard let offering = currentOffering else { return nil }
        return offering.availablePackages.first { pkg in
            let id = pkg.identifier.lowercased()
            let prod = pkg.storeProduct.productIdentifier.lowercased()
            return prod == Self.extraCreditsProductID
                || id.contains("power")
                || id.contains("credits_pack")
                || prod.contains("credits_pack")
        }
    }

    /// Unified accessor for the Power Pack `StoreProduct` regardless of source.
    /// Prefers the offering-attached Package, falls back to the standalone
    /// product fetched in `loadPowerAddonProductFallback()`. The paywall uses
    /// this for price display.
    var powerAddonStoreProduct: StoreProduct? {
        powerAddonPackage?.storeProduct ?? powerAddonProductFallback
    }

    /// Fetch the Power Pack consumable as a standalone product. Called when
    /// the offering doesn't include it as a Package. Safe to re-run.
    private func loadPowerAddonProductFallback() async {
        let products = await Purchases.shared.products([Self.extraCreditsProductID])
        powerAddonProductFallback = products.first { $0.productIdentifier == Self.extraCreditsProductID }
        #if DEBUG
        if let p = powerAddonProductFallback {
            print("[StoreManager] Power Pack fallback product loaded: \(p.productIdentifier) (\(p.localizedPriceString))")
        } else {
            print("[StoreManager] Power Pack fallback product NOT found for id '\(Self.extraCreditsProductID)' — check App Store Connect / sandbox")
        }
        #endif
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

    /// Buy the Power Pack consumable. Prefers the offering-attached Package
    /// (so RevenueCat attributes the purchase to the offering) and falls back
    /// to the standalone `StoreProduct` when the consumable isn't bundled.
    func purchasePowerPack() async throws -> CustomerInfo {
        if let pkg = powerAddonPackage {
            return try await purchase(pkg)
        }
        guard let product = powerAddonProductFallback else {
            throw NSError(
                domain: "StoreManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Power Pack is unavailable right now. Please try again in a moment."]
            )
        }

        isLoading = true
        defer { isLoading = false }

        let result: PurchaseResultData
        do {
            result = try await Purchases.shared.purchase(product: product)
        } catch {
            SubscriptionAnalytics.shared.purchaseFailed(productId: product.productIdentifier, error: error.localizedDescription)
            throw error
        }

        if !result.userCancelled {
            customerInfo = result.customerInfo
            syncTier(from: result.customerInfo)
            SubscriptionAnalytics.shared.purchaseCompleted(productId: product.productIdentifier)
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
        let nonSubs = info.nonSubscriptions.map { "\($0.productIdentifier)@\($0.purchaseDate)" }
        print("[StoreManager] Non-sub transactions: \(nonSubs.isEmpty ? "(none)" : nonSubs.joined(separator: ", "))")
        #endif

        // Power Pack purchases are consumables — process any new transactions
        // independently of the Pro/Founder entitlement state. Idempotent: each
        // RC transaction is credited at most once via the processed-ID set.
        let granted = processPowerPackTransactions(in: info)

        guard let entitlement = info.entitlements[Self.entitlementID],
              entitlement.isActive else {
            // Don't downgrade if Supabase already confirmed a paid tier
            // (handles macOS where StoreKit may not have an active account)
            if !TierManager.shared.isFoundingMember &&
               TierManager.shared.serverConfirmedTier == nil {
                TierManager.shared.updateTier(.free)
            }
            // Push bonus balance to server if we just credited a top-up.
            if granted > 0 {
                Task { await Self.syncBonusCreditsToServer() }
            }
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
                productId: entitlement.productIdentifier,
                expiresAt: entitlement.expirationDate
            )
            if granted > 0 {
                await Self.syncBonusCreditsToServer()
            }
        }
    }

    // MARK: - Power Pack (Consumable) Processing

    /// UserDefaults key for the set of RevenueCat transaction IDs we've already
    /// credited locally. Scoped per Supabase user to survive account switches.
    private static func processedKey(for userId: String?) -> String {
        "obius_power_pack_processed_\(userId ?? "anon")"
    }

    /// Inspect `nonSubscriptionTransactions` and credit any unseen Power Pack
    /// purchase whose `purchaseDate` falls inside the current UTC month.
    /// Transactions outside the current cycle are marked processed (so they
    /// don't keep being inspected) but do NOT add Credits — the cycle has
    /// already rolled over.
    ///
    /// Returns the total Credits granted on this call (0 if nothing new).
    @discardableResult
    private func processPowerPackTransactions(in info: CustomerInfo) -> Int {
        let userId = SupabaseManager.shared.currentUser?.id.uuidString.lowercased()
        let key = Self.processedKey(for: userId)
        var processed = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        var granted = 0

        for txn in info.nonSubscriptions where txn.productIdentifier == Self.extraCreditsProductID {
            let id = txn.transactionIdentifier
            guard !processed.contains(id) else { continue }

            if Self.isInCurrentUTCMonth(txn) {
                TierManager.shared.addBonusCredits(TierManager.powerPackCreditsPerPurchase)
                granted += TierManager.powerPackCreditsPerPurchase
                print("[StoreManager] Credited Power Pack tx \(id) (purchased \(txn.purchaseDate)) → +\(TierManager.powerPackCreditsPerPurchase) Credits")
            } else {
                print("[StoreManager] Skipping Power Pack tx \(id) — purchased \(txn.purchaseDate), outside current cycle")
            }
            processed.insert(id)
        }

        if granted > 0 || !processed.isEmpty {
            UserDefaults.standard.set(Array(processed), forKey: key)
        }
        return granted
    }

    /// Check if a non-subscription transaction's purchase date lands in the
    /// current UTC month. Power Pack credits expire when that month ends, so
    /// transactions from prior months don't carry over.
    private static func isInCurrentUTCMonth(_ txn: NonSubscriptionTransaction) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal.isDate(txn.purchaseDate, equalTo: Date(), toGranularity: .month)
    }

    /// Push the locally-confirmed tier to Supabase user_profiles.
    /// Acts as a client-side fallback for the RevenueCat webhook.
    private static func syncTierToServer(
        tier: Tier,
        period: ProPeriod?,
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

        do {
            try await SupabaseManager.shared.client
                .from("user_profiles")
                .update(update)
                .eq("id", value: userId)
                .execute()
            print("[StoreManager] Synced tier '\(tier.rawValue)' (period=\(period?.rawValue ?? "n/a")) to server for \(userId)")
        } catch {
            print("[StoreManager] Failed to sync tier to server: \(error)")
        }
    }

    /// Push the current cycle's Power Pack bonus balance to Supabase.
    /// Client-side fallback for the RevenueCat webhook — the webhook is the
    /// authoritative writer in production; this keeps the row coherent if
    /// webhook delivery is delayed or unconfigured. Last-write-wins is fine
    /// here because both paths converge on the same value.
    static func syncBonusCreditsToServer() async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id.uuidString.lowercased() else {
            return
        }
        let bonus = await MainActor.run { TierManager.shared.bonusCreditsThisMonth }
        let monthKey = await MainActor.run { TierManager.currentMonthKeyForBonus() }
        do {
            try await SupabaseManager.shared.client
                .from("user_profiles")
                .update([
                    "bonus_credits_this_month": "\(bonus)",
                    "bonus_credits_month_key": monthKey,
                    "updated_at": ISO8601DateFormatter().string(from: Date()),
                ])
                .eq("id", value: userId)
                .execute()
            print("[StoreManager] Synced bonus credits \(bonus) (month \(monthKey)) for \(userId)")
        } catch {
            print("[StoreManager] Failed to sync bonus credits: \(error)")
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
