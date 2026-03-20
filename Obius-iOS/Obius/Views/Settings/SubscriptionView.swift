import SwiftUI
import RevenueCat
import RevenueCatUI

struct SubscriptionView: View {
    @ObservedObject private var tierManager = TierManager.shared
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var showingCustomerCenter = false
    @State private var showingPaywall = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private var isFree: Bool { tierManager.currentTier == .free }

    var body: some View {
        List {
            // Current Plan
            SwiftUI.Section {
                planRow
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
                usageRow("AI Actions Today",
                         icon: "sparkles",
                         value: "\(tierManager.aiActionsUsedToday) / \(tierManager.limits.maxAIActionsPerDay)")

                if let maxNotes = tierManager.limits.maxNotes {
                    usageRow("Notes", icon: "note.text", value: "\(maxNotes) limit")
                } else {
                    usageRow("Notes", icon: "note.text", value: "Unlimited")
                }
            } header: {
                Text("Usage")
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
            CustomerCenterView()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet()
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
        case .free: return "Core app · Single device · 50 notes"
        case .pro: return "Unlimited · Multi-device · Full AI"
        case .founding: return "All Pro features · Locked rate · Early access"
        }
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
