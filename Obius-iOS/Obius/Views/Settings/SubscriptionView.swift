import SwiftUI
import StoreKit
import RevenueCat
import RevenueCatUI
#if os(macOS)
import AppKit
#endif

struct SubscriptionView: View {
    @ObservedObject private var tierManager = TierManager.shared
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var showingCustomerCenter = false
    @State private var showingPaywall = false
    @State private var showingCancelConfirm = false
    @State private var cancelError: String?
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private var isFree: Bool { tierManager.currentTier == .free }

    /// The active "Obius Pro" entitlement (Pro or Founder), if any.
    private var activeEntitlement: EntitlementInfo? {
        guard let info = storeManager.customerInfo,
              let ent = info.entitlements[StoreManager.entitlementID],
              ent.isActive else { return nil }
        return ent
    }

    /// We can offer in-app cancel only when the entitlement is set to renew.
    /// Already-cancelled subs and true lifetime purchases shouldn't show it.
    private var canCancel: Bool {
        guard let ent = activeEntitlement else { return false }
        return ent.willRenew
    }

    var body: some View {
        List {
            // Current Plan
            SwiftUI.Section {
                planRow
                planStatusRows
            } header: {
                Text("Current Plan")
            }

            // Founders badge (if applicable)
            if tierManager.isFoundingMember {
                SwiftUI.Section {
                    HStack(spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.purple)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Founders Badge")
                                .font(.subheadline.weight(.semibold))
                            Text("Early access · Direct line to the team · Rate locked forever")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Usage
            SwiftUI.Section {
                usageRow("AI Credits",
                         icon: "sparkles",
                         value: "\(TierManager.formatCreditCount(tierManager.creditsUsedThisMonth)) / \(TierManager.formatCreditCount(tierManager.maxCreditsPerMonth))")

                if let maxNotes = tierManager.limits.maxNotes {
                    usageRow("Notes", icon: "note.text", value: "\(maxNotes) limit")
                } else {
                    usageRow("Notes", icon: "note.text", value: "Unlimited")
                }
            } header: {
                Text("This Month")
            } footer: {
                Text("Credits refill \(refillDateString). 1 Credit ≈ 1,000 tokens of AI work.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Power Add-on row — visible to anyone (active or upsell)
            if tierManager.currentTier != .free || tierManager.hasPowerAddon {
                SwiftUI.Section {
                    powerAddonRow
                } header: {
                    Text("Add-Ons")
                }
            }

            // Features
            SwiftUI.Section {
                featureToggle("Multi-device Sync", icon: "icloud", enabled: tierManager.limits.cloudSync)
                featureToggle("AI Resurfacing", icon: "brain", enabled: tierManager.limits.aiWorkspace)
                featureToggle("Version History", icon: "arrow.down.doc", enabled: tierManager.limits.commits)
                featureToggle("Share Links", icon: "square.and.arrow.up", enabled: tierManager.limits.shareLinks)
                featureToggle("Semantic Search", icon: "magnifyingglass", enabled: tierManager.limits.semanticSearch)
            } header: {
                Text("Features")
            }

            // Actions
            SwiftUI.Section {
                if isFree {
                    Button {
                        showingPaywall = true
                    } label: {
                        Label("View Plans & Pricing", systemImage: "crown")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Button {
                        showingCustomerCenter = true
                    } label: {
                        Label("Manage Subscription", systemImage: "gearshape")
                    }

                    if canCancel {
                        Button(role: .destructive) {
                            showingCancelConfirm = true
                        } label: {
                            Label("Cancel Subscription", systemImage: "xmark.circle")
                        }
                    }
                }

                Button {
                    restorePurchases()
                } label: {
                    HStack {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                        if isRestoring {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRestoring)

                if let message = restoreMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(storeManager.hasProEntitlement ? .green : .secondary)
                }
            }
        }
        .navigationTitle("Subscription")
        .sheet(isPresented: $showingCustomerCenter) {
            #if os(iOS)
            CustomerCenterView()
            #else
            Text("Manage your subscription at https://apps.apple.com/account/subscriptions")
                .padding()
                .frame(width: 400, height: 200)
            #endif
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet()
        }
        .alert("Cancel Subscription?", isPresented: $showingCancelConfirm) {
            Button("Keep Subscription", role: .cancel) {}
            Button("Continue to Cancel", role: .destructive) {
                Task { await openManageSubscriptions() }
            }
        } message: {
            Text(cancelConfirmMessage)
        }
        .alert(
            "Couldn't Open Subscriptions",
            isPresented: Binding(
                get: { cancelError != nil },
                set: { if !$0 { cancelError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { cancelError = nil }
        } message: {
            Text(cancelError ?? "")
        }
        .task {
            await storeManager.refreshCustomerInfo()
        }
        .onChange(of: showingPaywall) { isShowing in
            if !isShowing {
                Task { await storeManager.refreshCustomerInfo() }
            }
        }
        .onChange(of: showingCustomerCenter) { isShowing in
            if !isShowing {
                Task { await storeManager.refreshCustomerInfo() }
            }
        }
    }

    // MARK: - Plan Row

    private var planRow: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(planColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: planIcon)
                    .font(.title3)
                    .foregroundStyle(planColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tierManager.tierDisplayName)
                    .font(.headline)
                Text(planSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var planIcon: String {
        switch tierManager.currentTier {
        case .free: return "person"
        case .pro: return "crown.fill"
        case .founding: return "star.fill"
        }
    }

    private var planColor: Color {
        switch tierManager.currentTier {
        case .free: return .secondary
        case .pro: return .orange
        case .founding: return .purple
        }
    }

    private var planSubtitle: String {
        switch tierManager.currentTier {
        case .free:
            return "Core app · Single device · 50 notes · 5 Credits/mo"
        case .pro:
            switch tierManager.proPeriod {
            case .annual: return "Unlimited · Multi-device · 250 Credits/mo"
            case .monthly, .none: return "Unlimited · Multi-device · 200 Credits/mo"
            }
        case .founding:
            return "All Pro features · Locked rate · 200 Credits/mo"
        }
    }

    private var refillDateString: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: tierManager.creditsRefillDate)
    }

    // MARK: - Plan Status

    @ViewBuilder
    private var planStatusRows: some View {
        if let ent = activeEntitlement {
            if let date = ent.expirationDate {
                detailRow(
                    label: ent.willRenew ? "Renews" : "Ends on",
                    value: Self.longDateString(from: date),
                    valueTint: ent.willRenew ? .secondary : .orange
                )
            }
            detailRow(label: "Billing", value: billingPeriodLabel(for: ent))
            detailRow(label: "Purchased via", value: storeLabel(for: ent.store))
        }
    }

    private func detailRow(label: String, value: String, valueTint: Color = .secondary) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueTint)
        }
    }

    private func billingPeriodLabel(for ent: EntitlementInfo) -> String {
        let id = ent.productIdentifier.lowercased()
        if id == StoreManager.monthlyProductID { return "Monthly" }
        if id == StoreManager.foundersProductID { return "Monthly" }
        if id.contains("annual") || id.contains("yearly") || id.contains("year") {
            return "Annual"
        }
        if id.contains("month") { return "Monthly" }
        if id.contains("lifetime") { return "Lifetime" }
        switch tierManager.proPeriod {
        case .annual: return "Annual"
        case .monthly: return "Monthly"
        case .none: return "—"
        }
    }

    private func storeLabel(for store: Store) -> String {
        switch store {
        case .appStore: return "App Store"
        case .macAppStore: return "Mac App Store"
        case .playStore: return "Play Store"
        case .stripe: return "Stripe"
        case .promotional: return "Promotional"
        case .amazon: return "Amazon"
        case .unknownStore: return "Unknown"
        @unknown default: return "Other"
        }
    }

    private static func longDateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    // MARK: - Cancel Subscription

    private var cancelConfirmMessage: String {
        let plan = tierManager.tierDisplayName
        if let ent = activeEntitlement, let date = ent.expirationDate {
            return "You'll keep \(plan) access until \(Self.longDateString(from: date)). After that, your account will switch to the Free plan and you'll lose multi-device sync, AI workspace, and version history. Your notes are not deleted. Tap Continue to Cancel to finish in the App Store."
        }
        return "Your account will switch to the Free plan at the end of your current billing period and you'll lose multi-device sync, AI workspace, and version history. Your notes are not deleted. Tap Continue to Cancel to finish in the App Store."
    }

    @MainActor
    private func openManageSubscriptions() async {
        #if os(iOS)
        let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene

        if let scene {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
                await storeManager.refreshCustomerInfo()
                return
            } catch {
                print("[SubscriptionView] showManageSubscriptions failed: \(error)")
                // Fall through to URL fallback
            }
        }
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            await UIApplication.shared.open(url)
        } else {
            cancelError = "Couldn't open the App Store subscriptions page."
        }
        #else
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            NSWorkspace.shared.open(url)
        } else {
            cancelError = "Couldn't open the App Store subscriptions page."
        }
        #endif
    }

    @ViewBuilder
    private var powerAddonRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(tierManager.hasPowerAddon ? .yellow : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Power Pack")
                    .font(.subheadline.weight(.semibold))
                Text(tierManager.hasPowerAddon
                     ? "Active · +1,000 Credits/month"
                     : "+1,000 Credits/month for $9.99/mo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if tierManager.hasPowerAddon {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Add") { showingPaywall = true }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Rows

    private func usageRow(_ title: String, icon: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func featureToggle(_ title: String, icon: String, enabled: Bool) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "lock.fill")
                .font(.subheadline)
                .foregroundStyle(enabled ? .green : .secondary)
        }
    }

    // MARK: - Restore

    private func restorePurchases() {
        isRestoring = true
        restoreMessage = nil
        Task {
            do {
                _ = try await storeManager.restorePurchases()
                restoreMessage = storeManager.hasProEntitlement
                    ? "Subscription restored!"
                    : "No active subscription found."
            } catch {
                restoreMessage = error.localizedDescription
            }
            isRestoring = false
        }
    }
}
