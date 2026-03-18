import SwiftUI
import RevenueCat
import RevenueCatUI

struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tierManager = TierManager.shared

    private var feature: GatedFeature? {
        tierManager.paywallFeature
    }

    var body: some View {
        PaywallView()
            .onPurchaseCompleted { customerInfo in
                StoreManager.shared.syncTier(from: customerInfo)
                dismiss()
            }
            .onRestoreCompleted { customerInfo in
                StoreManager.shared.syncTier(from: customerInfo)
                dismiss()
            }
    }
}
