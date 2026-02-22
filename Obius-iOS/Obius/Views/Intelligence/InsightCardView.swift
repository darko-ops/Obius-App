import SwiftUI

struct InsightCardView: View {
    let insight: Insight
    let onTrack: () -> Void
    let onDismiss: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Type badge + timestamp
                HStack {
                    Label(insight.insightType.label, systemImage: insight.insightType.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tintColor)

                    Spacer()

                    Text(insight.createdDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Title
                Text(insight.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Body
                Text(insight.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // Action buttons
                if insight.status == .surfaced {
                    HStack(spacing: 12) {
                        Button {
                            onTrack()
                        } label: {
                            Label("Track", systemImage: "pin")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(tintColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(tintColor.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Button {
                            onDismiss()
                        } label: {
                            Label("Dismiss", systemImage: "xmark")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        Spacer()
                    }
                }
            }
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(tintColor.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var tintColor: Color {
        switch insight.insightType.tint {
        case .green:  return .green
        case .yellow: return .yellow
        case .purple: return .purple
        case .gray:   return .gray
        case .blue:   return .blue
        case .orange: return .orange
        }
    }

    private var cardBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground
                : UIColor.systemBackground
        })
    }
}

// MARK: - Tracked Insight Row (compact version for the tracked list)

struct TrackedInsightRow: View {
    let insight: Insight
    let onTap: () -> Void
    let onUntrack: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: insight.insightType.icon)
                    .font(.body)
                    .foregroundStyle(tintColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(insight.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(tintColor.opacity(0.6))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onUntrack()
            } label: {
                Label("Unpin", systemImage: "pin.slash")
            }
        }
    }

    private var tintColor: Color {
        switch insight.insightType.tint {
        case .green:  return .green
        case .yellow: return .yellow
        case .purple: return .purple
        case .gray:   return .gray
        case .blue:   return .blue
        case .orange: return .orange
        }
    }
}
