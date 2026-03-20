import SwiftUI
import RevenueCat
import RevenueCatUI

// MARK: - Soft Paywall (Bottom Sheet)

struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tierManager = TierManager.shared
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var selectedPlan: PlanChoice = .yearly
    @State private var isPurchasing = false
    @State private var purchaseError: String?

    private var feature: GatedFeature? {
        tierManager.paywallFeature
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 20) {
                        featureHeader
                        planPicker
                        featureComparison
                        purchaseButton
                        footerLinks
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(.systemBackground))
            .presentationDetents([.large, .medium])
            .presentationDragIndicator(.hidden)
            .overlay {
                if isPurchasing {
                    ProgressView()
                        .scaleEffect(1.3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .onAppear {
                SubscriptionAnalytics.shared.paywallShown(feature: feature)
            }
            .onDisappear {
                SubscriptionAnalytics.shared.paywallDismissed(feature: feature)
            }
        }
    }

    // MARK: - Feature Header

    @ViewBuilder
    private var featureHeader: some View {
        VStack(spacing: 8) {
            if let feature {
                Image(systemName: feature.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text(feature.softMessage)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "crown.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text("Obius Pro")
                    .font(.title3.weight(.semibold))
            }
            Text("Unlock the full power of Obius")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Plan Picker

    private var planPicker: some View {
        VStack(spacing: 10) {
            // Monthly / Yearly / Lifetime toggle
            HStack(spacing: 8) {
                planTab(.monthly, "Monthly")
                planTab(.yearly, "Yearly")
                if storeManager.lifetimePackage != nil {
                    planTab(.lifetime, "Lifetime")
                }
            }

            // Selected plan card
            if let package = selectedPackage {
                planCard(package)
            }
        }
    }

    private func planTab(_ plan: PlanChoice, _ label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedPlan = plan }
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(selectedPlan == plan ? .semibold : .regular))
                    .foregroundStyle(selectedPlan == plan ? .primary : .secondary)

                if plan == .yearly {
                    Text("SAVE ~38%")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.orange)
                } else if plan == .lifetime {
                    Text("BEST VALUE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.orange)
                } else {
                    Text(" ")
                        .font(.system(size: 8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedPlan == plan ? Color.orange.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedPlan == plan ? Color.orange.opacity(0.4) : Color(.separator).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func planCard(_ package: Package) -> some View {
        VStack(spacing: 4) {
            Text(package.storeProduct.localizedPriceString)
                .font(.title2.weight(.bold))

            Text(priceSubtext(for: selectedPlan, package: package))
                .font(.caption)
                .foregroundStyle(.secondary)

            if package.storeProduct.introductoryDiscount != nil {
                Text("7-day free trial")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func priceSubtext(for plan: PlanChoice, package: Package) -> String {
        switch plan {
        case .monthly: return "per month"
        case .yearly:
            let monthlyEquiv = package.storeProduct.price / 12
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = package.storeProduct.priceFormatter?.locale ?? .current
            let perMonth = formatter.string(from: monthlyEquiv as NSDecimalNumber) ?? ""
            return "\(perMonth)/mo billed yearly"
        case .lifetime: return "one-time purchase, forever"
        }
    }

    // MARK: - Feature Comparison

    private var featureComparison: some View {
        VStack(spacing: 0) {
            comparisonHeader
            Divider()
            comparisonRow("Notes", free: "25", pro: "Unlimited")
            comparisonRow("Projects", free: "2", pro: "Unlimited")
            comparisonRow("Loops", free: "3", pro: "Unlimited")
            comparisonRow("AI actions / day", free: "10", pro: "100")
            comparisonRow("Cloud Sync", free: nil, pro: "checkmark")
            comparisonRow("Version History", free: nil, pro: "checkmark")
            comparisonRow("AI Workspace", free: nil, pro: "checkmark")
            comparisonRow("Share Links", free: nil, pro: "checkmark")
            comparisonRow("Semantic Search", free: nil, pro: "checkmark")
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var comparisonHeader: some View {
        HStack {
            Text("")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Free")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 60)
            Text("Pro")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 60)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func comparisonRow(_ label: String, free: String?, pro: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Free column
                Group {
                    if let free {
                        Text(free)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                .frame(width: 60)

                // Pro column
                Group {
                    if pro == "checkmark" {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                    } else {
                        Text(pro)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(width: 60)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)

            Divider().padding(.leading, 14)
        }
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        VStack(spacing: 8) {
            Button {
                guard let package = selectedPackage else { return }
                purchasePackage(package)
            } label: {
                Text(purchaseButtonLabel)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isPurchasing || selectedPackage == nil)

            if let error = purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var purchaseButtonLabel: String {
        guard let package = selectedPackage else { return "Subscribe" }
        if package.storeProduct.introductoryDiscount != nil {
            return "Start Free Trial"
        }
        return selectedPlan == .lifetime ? "Buy Lifetime" : "Subscribe"
    }

    // MARK: - Footer

    private var footerLinks: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    purchaseError = nil
                    do {
                        _ = try await storeManager.restorePurchases()
                        if storeManager.hasProEntitlement { dismiss() }
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
                Link("Terms", destination: URL(string: "https://obius.io/terms")!)
                    .font(.caption2).foregroundStyle(.tertiary)
                Link("Privacy", destination: URL(string: "https://obius.io/privacy")!)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private var selectedPackage: Package? {
        switch selectedPlan {
        case .monthly: return storeManager.monthlyPackage
        case .yearly: return storeManager.yearlyPackage
        case .lifetime: return storeManager.lifetimePackage
        }
    }

    private func purchasePackage(_ package: Package) {
        isPurchasing = true
        purchaseError = nil
        Task {
            do {
                _ = try await storeManager.purchase(package)
                dismiss()
            } catch {
                purchaseError = error.localizedDescription
            }
            isPurchasing = false
        }
    }
}

// MARK: - Plan Choice

enum PlanChoice {
    case monthly, yearly, lifetime
}

// MARK: - Soft Message Extension

extension GatedFeature {
    var softMessage: String {
        switch self {
        case .notes: return "Unlock unlimited notes"
        case .modules: return "Unlock unlimited projects"
        case .handles: return "Unlock unlimited loops"
        case .echoes: return "Unlock unlimited echoes"
        case .aiActions: return "Get more AI actions"
        case .aiWorkspace: return "Unlock the AI workspace"
        case .cloudSync: return "Sync across all your devices"
        case .commits: return "Unlock version history"
        case .shareLinks: return "Share your notes with anyone"
        case .semanticSearch: return "Search smarter with AI"
        case .fullInsights: return "See the full picture"
        }
    }
}
