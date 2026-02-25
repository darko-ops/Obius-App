import SwiftUI

/// Badge displayed on sections that are linked to a handle (portals)
struct HandleBadge: View {
    let handle: Handle
    var showUnlinkAction: Bool = false
    var onUnlink: (() -> Void)?

    private let loopColor: Color = .purple

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(.caption2)

            Text(handle.formattedName)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(loopColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(loopColor.opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(loopColor.opacity(0.3), lineWidth: 0.5)
        )
        .contextMenu {
            if showUnlinkAction, let onUnlink = onUnlink {
                Button(role: .destructive) {
                    onUnlink()
                } label: {
                    Label("Unlink from \(handle.formattedName)", systemImage: "link.badge.minus")
                }
            }

            Button {
                // Copy handle name to clipboard
                #if os(iOS)
                UIPasteboard.general.string = handle.formattedName
                #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(handle.formattedName, forType: .string)
                #endif
            } label: {
                Label("Copy Loop Name", systemImage: "doc.on.doc")
            }
        }
    }
}

/// Compact badge for tight spaces
struct HandleBadgeCompact: View {
    let handle: Handle

    private let loopColor: Color = .purple

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "link")
                .font(.system(size: 8))

            Text("@")
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(loopColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(loopColor.opacity(0.15))
        )
    }
}

// MARK: - Preview

#Preview("Handle Badges") {
    VStack(spacing: 20) {
        HandleBadge(
            handle: Handle(name: "jokes", displayName: "Jokes", content: "Sample content", intent: .idea),
            showUnlinkAction: true,
            onUnlink: { print("Unlink") }
        )

        HandleBadge(
            handle: Handle(name: "todos", displayName: "TODOs", content: "Sample content", intent: .task)
        )

        HandleBadge(
            handle: Handle(name: "research", displayName: "Research", content: "Sample content", intent: .evidence)
        )

        HandleBadge(
            handle: Handle(name: "questions", displayName: "Questions", content: "Sample content", intent: .question)
        )

        Divider()

        HStack(spacing: 12) {
            HandleBadgeCompact(handle: Handle(name: "jokes", intent: .idea))
            HandleBadgeCompact(handle: Handle(name: "todos", intent: .task))
            HandleBadgeCompact(handle: Handle(name: "research", intent: .evidence))
        }
    }
    .padding()
}
