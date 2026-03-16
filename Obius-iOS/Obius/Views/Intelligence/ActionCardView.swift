import SwiftUI

struct ActionCardView: View {
    let action: SuggestedAction
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var isExpanded: Bool = false

    private var isResolved: Bool {
        action.status != .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Type badge + expand toggle for resolved cards
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: action.icon)
                        .font(.caption2)
                    Text(action.toolName.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(action.tintColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(action.tintColor.opacity(0.15))
                .clipShape(Capsule())

                Spacer()

                if isResolved && action.fullContent != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Title
            Text(action.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.lightGray))
                .lineLimit(2)

            // Content area
            if let full = action.fullContent {
                if !isResolved {
                    // Pending: show full content so user can review before accepting
                    Text(full)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if isExpanded {
                    // Resolved + expanded: show full content
                    Text(full)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                // Non-content actions: show description
                Text(action.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isResolved ? 2 : nil)
            }

            // Action row
            statusRow
        }
        .padding(14)
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(action.tintColor.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusRow: some View {
        switch action.status {
        case .pending:
            HStack(spacing: 10) {
                Button {
                    onAccept()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                        Text("Accept")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(action.tintColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(action.tintColor.opacity(0.12))
                    .clipShape(Capsule())
                }

                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                        Text("Dismiss")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }

                Spacer()
            }

        case .accepted:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                Text("Accepted")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.green)

        case .dismissed:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                Text("Dismissed")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)

        case .failed(let reason):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text("Failed: \(reason)")
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
            }
            .foregroundStyle(.red)
        }
    }
}
