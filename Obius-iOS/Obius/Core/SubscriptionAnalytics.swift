import Foundation

/// Lightweight subscription funnel event logger.
/// Posts events to the log-event Edge Function fire-and-forget.
@MainActor
final class SubscriptionAnalytics {
    static let shared = SubscriptionAnalytics()
    private init() {}

    // MARK: - Events

    func paywallShown(feature: GatedFeature?) {
        log("paywall_shown", triggerFeature: feature?.rawValue)
    }

    func paywallDismissed(feature: GatedFeature?) {
        log("paywall_dismissed", triggerFeature: feature?.rawValue)
    }

    func trialStarted(productId: String?) {
        log("trial_started", productId: productId, tierBefore: currentTier, tierAfter: "pro")
    }

    func purchaseCompleted(productId: String?) {
        log("purchase_completed", productId: productId, tierBefore: currentTier, tierAfter: "pro")
    }

    func purchaseFailed(productId: String?, error: String?) {
        log("purchase_failed", productId: productId, metadata: error.map { ["error": $0] })
    }

    func restoreCompleted() {
        log("restore_completed", tierBefore: currentTier, tierAfter: TierManager.shared.currentTier.rawValue)
    }

    // MARK: - Internal

    private var currentTier: String {
        TierManager.shared.currentTier.rawValue
    }

    private func log(
        _ event: String,
        triggerFeature: String? = nil,
        productId: String? = nil,
        tierBefore: String? = nil,
        tierAfter: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        guard AppConfiguration.isAnalyticsEnabled else { return }

        var body: [String: Any] = ["event": event]
        if let f = triggerFeature { body["triggerFeature"] = f }
        if let p = productId { body["productId"] = p }
        if let tb = tierBefore { body["tierBefore"] = tb }
        if let ta = tierAfter { body["tierAfter"] = ta }
        if let m = metadata { body["metadata"] = m }

        // Fire-and-forget — never blocks UX
        Task.detached(priority: .utility) {
            guard let url = URL(string: "\(AppConfiguration.supabaseURL)/functions/v1/log-event") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(AppConfiguration.supabaseAnonKey)", forHTTPHeaderField: "apikey")

            // Attach user JWT if available
            if let session = try? await SupabaseManager.shared.client.auth.session {
                request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            }

            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}
