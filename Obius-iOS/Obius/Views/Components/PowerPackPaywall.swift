import SwiftUI
import RevenueCat

// MARK: - Power Pack Paywall
//
// Single-product paywall for the Power Pack (`credits_pack_10`) — a
// *consumable* IAP that grants a one-time +1,000 Credits. It is NOT an
// auto-renewing add-on to the user's subscription. Shown when a Pro/Founder
// user runs out of monthly Credits, and when they tap "Buy" on the Power
// Pack row in Settings → Subscription.

struct PowerPackPaywall: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tierManager = TierManager.shared
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var isPurchasing = false
    @State private var purchaseError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    pricingCard
                    benefits
                    purchaseButton
                    footerLinks
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color.systemBackground)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .overlay {
                if isPurchasing {
                    ProgressView()
                        .scaleEffect(1.3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .onAppear {
                SubscriptionAnalytics.shared.paywallShown(feature: .aiActions)
            }
            .onDisappear {
                SubscriptionAnalytics.shared.paywallDismissed(feature: .aiActions)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.yellow)
            }
            Text(headerTitle)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var headerTitle: String {
        outOfCredits ? "You're out of Credits" : "Need more Credits?"
    }

    private var headerSubtitle: String {
        if outOfCredits {
            return "Top up with 1,000 Credits to keep going — your plan's Credits refill on \(refillDateString)."
        }
        return "Grab a one-time pack of 1,000 Credits for when the AI workspace is doing the heavy lifting."
    }

    private var outOfCredits: Bool {
        tierManager.creditsRemaining <= 0
    }

    private var refillDateString: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: tierManager.creditsRefillDate)
    }

    // MARK: - Pricing Card

    @ViewBuilder
    private var pricingCard: some View {
        if let product = storeManager.powerAddonStoreProduct {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Power Pack")
                        .font(.headline)
                    Text("ONE-TIME")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.yellow))
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(product.localizedPriceString)
                        .font(.system(size: 30, weight: .bold))
                    Text("one-time")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Adds 1,000 AI Credits to this month. Doesn't auto-renew — buy again whenever you need more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.yellow.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.yellow.opacity(0.45), lineWidth: 1.5)
            )
        } else {
            // Offering hasn't loaded yet — show placeholder so the sheet isn't empty.
            HStack {
                ProgressView()
                Text("Loading pricing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondarySystemBackground)
            )
        }
    }

    // MARK: - Benefits

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow(icon: "sparkles", title: "+1,000 Credits",
                       detail: "Added on top of your plan's Credits for this month.")
            benefitRow(icon: "hand.tap", title: "One-time purchase",
                       detail: "No auto-renewal — buy another pack any time you need.")
            benefitRow(icon: "bolt.horizontal", title: "Activates instantly",
                       detail: "Credits land the moment your purchase completes.")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondarySystemBackground)
        )
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.yellow)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Purchase

    private var purchaseButton: some View {
        VStack(spacing: 8) {
            Button {
                purchase()
            } label: {
                Text("Add Power Pack")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isPurchasing || storeManager.powerAddonStoreProduct == nil)

            if let error = purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func purchase() {
        isPurchasing = true
        purchaseError = nil
        Task {
            do {
                _ = try await storeManager.purchasePowerPack()
                dismiss()
            } catch {
                purchaseError = error.localizedDescription
            }
            isPurchasing = false
        }
    }

    // MARK: - Footer

    private var footerLinks: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    purchaseError = nil
                    let creditsBefore = tierManager.bonusCreditsThisMonth
                    do {
                        _ = try await storeManager.restorePurchases()
                        // If the restore credited any new Power Pack purchase
                        // for this cycle, the user has what they came for.
                        if tierManager.bonusCreditsThisMonth > creditsBefore { dismiss() }
                    } catch {
                        purchaseError = error.localizedDescription
                    }
                }
            } label: {
                Text("Restore Purchases")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Link("Terms", destination: URL(string: "https://docs.google.com/document/d/e/2PACX-1vRq_bt_Z_V7ci7lS3hHLzq4QjRrDFJsJu6Ab-oedeeSakGPGcx_dJlG3EDAzdetptd21GPyEtzTxKbg/pub")!)
                    .font(.caption2).foregroundStyle(.tertiary)
                Link("Privacy", destination: URL(string: "https://docs.google.com/document/d/e/2PACX-1vRbJ9cYTWnyQSYeL8JrTOizC0eC-f8rhoicqh3GttTDIrbNlesR-_auwkFz2OLsTTzguDG3YLtzwnEY/pub")!)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
