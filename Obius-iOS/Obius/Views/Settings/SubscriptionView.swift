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

            // Usage
            SwiftUI.Section {
                usageRow("AI Actions Today",
                         icon: "sparkles",
                         used: tierManager.aiActionsUsedToday,
                         limit: tierManager.limits.maxAIActionsPerDay)

                if let maxNotes = tierManager.limits.maxNotes {
                    featureRow("Notes", icon: "note.text", detail: "of \(maxNotes)")
                } else {
                    featureRow("Notes", icon: "note.text", detail: "Unlimited")
                }

                if let maxLoops = tierManager.limits.maxHandles {
                    featureRow("Loops", icon: "at", detail: "of \(maxLoops)")
                } else {
                    featureRow("Loops", icon: "at", detail: "Unlimited")
                }

                if let maxEchoes = tierManager.limits.maxEchoes {
                    featureRow("Echoes", icon: "bell", detail: "of \(maxEchoes)")
                } else {
                    featureRow("Echoes", icon: "bell", detail: "Unlimited")
                }
            } header: {
                Text("Usage")
            }

            // Features
            SwiftUI.Section {
                featureToggle("Cloud Sync", icon: "icloud", enabled: tierManager.limits.cloudSync)
                featureToggle("Version History", icon: "arrow.down.doc", enabled: tierManager.limits.commits)
                featureToggle("Share Links", icon: "square.and.arrow.up", enabled: tierManager.limits.shareLinks)
                featureToggle("AI Workspace", icon: "brain", enabled: tierManager.limits.aiWorkspace)
                featureToggle("Semantic Search", icon: "magnifyingglass", enabled: tierManager.limits.semanticSearch)
                featureToggle("Full Insights", icon: "lightbulb", enabled: tierManager.limits.fullInsights)
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
    }

    // MARK: - Plan Row

    private var planRow: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFree ? Color.gray.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: isFree ? "person" : "crown.fill")
                    .font(.title3)
                    .foregroundStyle(isFree ? Color.secondary : Color.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tierManager.tierDisplayName)
                    .font(.headline)
                if isFree {
                    Text("Upgrade to unlock all features")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if tierManager.isFoundingMember {
                    Text("Thank you for being an early supporter")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("All features unlocked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Rows

    private func usageRow(_ title: String, icon: String, used: Int, limit: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text("\(used) / \(limit)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func featureRow(_ title: String, icon: String, detail: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(detail)
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
