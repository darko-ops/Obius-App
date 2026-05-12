import SwiftUI
import RevenueCat
import RevenueCatUI

// MARK: - Paywall Sheet

struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tierManager = TierManager.shared
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var selectedPlan: PlanChoice = .annual
    @State private var isPurchasing = false
    @State private var purchaseError: String?

    private var feature: GatedFeature? {
        tierManager.paywallFeature
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    planCards
                    featureComparison
                    purchaseButton
                    footerLinks
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color.systemBackground)
            .presentationDetents([.large, .medium])
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
                SubscriptionAnalytics.shared.paywallShown(feature: feature)
            }
            .onDisappear {
                SubscriptionAnalytics.shared.paywallDismissed(feature: feature)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
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
                Text("Choose your plan")
                    .font(.title3.weight(.semibold))
            }
        }
    }

    // MARK: - Plan Cards

    private var planCards: some View {
        VStack(spacing: 10) {
            // Monthly — $9.99/mo · 200 Credits/month · 14-day free trial
            if let monthly = storeManager.monthlyPackage {
                planCard(
                    plan: .monthly,
                    title: "Pro Monthly",
                    price: monthly.storeProduct.localizedPriceString,
                    detail: "per month · 200 Credits/mo",
                    badge: "14-DAY TRIAL",
                    subtitle: "Full access, cancel anytime"
                )
            }

            // Annual — $79/yr · 250 Credits/month · 14-day free trial
            if let annual = storeManager.yearlyPackage {
                let monthlyEquiv = formattedMonthlyPrice(from: annual)
                planCard(
                    plan: .annual,
                    title: "Pro Annual",
                    price: annual.storeProduct.localizedPriceString,
                    detail: "\(monthlyEquiv)/mo · billed yearly · 250 Credits/mo",
                    badge: "BEST VALUE",
                    subtitle: "Save ~34% vs monthly · 14-day trial"
                )
            }

            // Founders — $5.99/mo locked forever · 200 Credits/month · 300 spots
            if let founders = storeManager.lifetimePackage {
                let spotsLeft = tierManager.foundersSpotsRemaining
                planCard(
                    plan: .founders,
                    title: "Founders Plan",
                    price: founders.storeProduct.localizedPriceString,
                    detail: "per month · locked forever · 200 Credits/mo",
                    badge: spotsLeft > 0 ? "\(spotsLeft) SPOTS LEFT" : "SOLD OUT",
                    subtitle: "Locked rate forever · Early access · Founders badge",
                    isFounders: true,
                    isSoldOut: spotsLeft <= 0
                )
            }

            // Power Add-on — $9.99/mo, only relevant once user has Pro/Founders
            if tierManager.currentTier != .free, let power = storeManager.powerAddonPackage {
                powerAddonCard(package: power)
            }
        }
    }

    @ViewBuilder
    private func powerAddonCard(package: Package) -> some View {
        let active = tierManager.hasPowerAddon
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                Text("Power Add-on")
                    .font(.subheadline.weight(.semibold))
                if active {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green))
                }
            }
            Text("\(package.storeProduct.localizedPriceString)/mo · +1,000 Credits/month")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("For users hammering the AI Workspace. Stacks on top of your plan.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !active {
                Button {
                    purchasePackage(package)
                } label: {
                    Text("Add Power Pack")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.yellow))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1.5)
        )
    }

    private func planCard(
        plan: PlanChoice,
        title: String,
        price: String,
        detail: String,
        badge: String?,
        subtitle: String,
        isFounders: Bool = false,
        isSoldOut: Bool = false
    ) -> some View {
        Button {
            if !isSoldOut {
                withAnimation(.easeInOut(duration: 0.2)) { selectedPlan = plan }
            }
        } label: {
            HStack(spacing: 14) {
                // Radio indicator
                ZStack {
                    Circle()
                        .stroke(selectedPlan == plan ? Color.orange : Color.gray.opacity(0.4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if selectedPlan == plan {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSoldOut ? .secondary : .primary)

                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(
                                        isFounders ? (isSoldOut ? Color.gray : Color.purple) : Color.orange
                                    )
                                )
                        }
                    }

                    HStack(spacing: 4) {
                        Text(price)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isSoldOut ? .secondary : .primary)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(isFounders && !isSoldOut ? .purple : .secondary)
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedPlan == plan ? Color.orange.opacity(0.06) : Color.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedPlan == plan ? Color.orange.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSoldOut)
        .opacity(isSoldOut ? 0.6 : 1)
    }

    // MARK: - Feature Comparison

    private var featureComparison: some View {
        VStack(spacing: 0) {
            comparisonHeader
            Divider()
            comparisonRow("Notes", free: "50", paid: "Unlimited")
            comparisonRow("Search & capture", free: "checkmark", paid: "checkmark")
            comparisonRow("Multi-device sync", free: nil, paid: "checkmark")
            comparisonRow("AI Credits / month", free: "5", paid: paidCreditsLabel)
            comparisonRow("Semantic Search", free: nil, paid: "checkmark")
            comparisonRow("AI Workspace", free: nil, paid: "checkmark")
            comparisonRow("Version history", free: nil, paid: "checkmark")
            comparisonRow("Share links", free: nil, paid: "checkmark")
        }
        .background(Color.secondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Credit value in the "Paid" column — adjusts based on which plan the user
    /// has currently selected so the table reads as expected.
    private var paidCreditsLabel: String {
        switch selectedPlan {
        case .annual: return "250"
        case .founders, .monthly: return "200"
        }
    }

    private var comparisonHeader: some View {
        HStack {
            Text("")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Free")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 60)
            Text("Paid")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 60)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func comparisonRow(_ label: String, free: String?, paid: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)

                cellView(free)
                    .frame(width: 60)
                cellView(paid, accent: true)
                    .frame(width: 60)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)

            Divider().padding(.leading, 14)
        }
    }

    @ViewBuilder
    private func cellView(_ value: String?, accent: Bool = false) -> some View {
        if let value {
            if value == "checkmark" {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent ? .orange : .primary)
            } else {
                Text(value)
                    .font(.caption.weight(accent ? .medium : .regular))
                    .foregroundStyle(accent ? .orange : .secondary)
            }
        } else {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.4))
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
        switch selectedPlan {
        case .founders:
            // Founders is no-trial — locked rate is the offer
            return "Lock In Founders Rate"
        case .monthly, .annual:
            if package.storeProduct.introductoryDiscount != nil {
                return "Start 14-Day Free Trial"
            }
            return "Subscribe"
        }
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
                Link("Terms", destination: URL(string: "https://docs.google.com/document/d/e/2PACX-1vRq_bt_Z_V7ci7lS3hHLzq4QjRrDFJsJu6Ab-oedeeSakGPGcx_dJlG3EDAzdetptd21GPyEtzTxKbg/pub")!)
                    .font(.caption2).foregroundStyle(.tertiary)
                Link("Privacy", destination: URL(string: "https://docs.google.com/document/d/e/2PACX-1vRbJ9cYTWnyQSYeL8JrTOizC0eC-f8rhoicqh3GttTDIrbNlesR-_auwkFz2OLsTTzguDG3YLtzwnEY/pub")!)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private var selectedPackage: Package? {
        switch selectedPlan {
        case .monthly: return storeManager.monthlyPackage
        case .annual: return storeManager.yearlyPackage
        case .founders: return storeManager.lifetimePackage
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

    private func formattedMonthlyPrice(from package: Package) -> String {
        let monthly = package.storeProduct.price / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = package.storeProduct.priceFormatter?.locale ?? .current
        return formatter.string(from: monthly as NSDecimalNumber) ?? ""
    }
}

// MARK: - Plan Choice

enum PlanChoice {
    case monthly, annual, founders
}

// MARK: - Soft Message Extension

extension GatedFeature {
    var softMessage: String {
        switch self {
        case .notes: return "Unlock unlimited notes"
        case .aiActions: return "Get more AI Credits"
        case .aiWorkspace: return "Unlock the AI workspace"
        case .cloudSync: return "Sync across all your devices"
        case .commits: return "Unlock version history"
        case .shareLinks: return "Share your notes with anyone"
        case .semanticSearch: return "Search smarter with AI"
        case .fullInsights: return "See the full picture"
        }
    }
}
