import SwiftUI
import RevenueCat
import RevenueCatUI

// MARK: - Soft Paywall (Bottom Sheet)
// Shown inline when a user hits a limit. Not a fullscreen blocker.
// Shows what they unlock with Pro, not what they can't do.

struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tierManager = TierManager.shared
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var showFullPaywall = false
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
                    VStack(spacing: 24) {
                        featureHeader
                        proUnlocks
                        trialCTA
                        restoreLink
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(.systemBackground))
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
            .sheet(isPresented: $showFullPaywall) {
                PaywallView()
                    .onPurchaseCompleted { customerInfo in
                        StoreManager.shared.syncTier(from: customerInfo)
                        showFullPaywall = false
                        dismiss()
                    }
                    .onRestoreCompleted { customerInfo in
                        StoreManager.shared.syncTier(from: customerInfo)
                        showFullPaywall = false
                        dismiss()
                    }
            }
        }
    }

    // MARK: - Feature Header

    @ViewBuilder
    private var featureHeader: some View {
        VStack(spacing: 12) {
            if let feature {
                Image(systemName: feature.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)

                Text(feature.softMessage)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)

                Text("Do more with Obius Pro")
                    .font(.title3.weight(.semibold))
            }
        }
    }

    // MARK: - What Pro Unlocks

    private var proUnlocks: some View {
        VStack(alignment: .leading, spacing: 10) {
            unlockRow("note.text", "Unlimited notes & projects")
            unlockRow("sparkles", "100 AI actions per day")
            unlockRow("brain", "AI workspace")
            unlockRow("icloud", "Cloud sync across devices")
            unlockRow("arrow.down.doc", "Version history")
            unlockRow("square.and.arrow.up", "Share links")
            unlockRow("magnifyingglass", "Semantic search")
            unlockRow("lightbulb", "Full insights")
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func unlockRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Trial CTA

    private var trialCTA: some View {
        VStack(spacing: 12) {
            Button {
                showFullPaywall = true
            } label: {
                Text("Start 7-Day Free Trial")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text("Try everything free for 7 days, then choose a plan.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Restore

    private var restoreLink: some View {
        Button {
            Task {
                do {
                    let info = try await storeManager.restorePurchases()
                    if StoreManager.shared.hasProEntitlement {
                        dismiss()
                    }
                } catch {
                    purchaseError = error.localizedDescription
                }
            }
        } label: {
            Text("Restore Purchases")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Soft Message Extension

extension GatedFeature {
    /// Positive framing — what they unlock, not what they can't do.
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
