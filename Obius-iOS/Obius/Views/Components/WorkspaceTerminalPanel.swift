import SwiftUI

#if os(macOS)
/// A terminal-style bottom panel for the AI workspace on macOS.
/// Sits below the editor content like an IDE terminal pane.
struct WorkspaceTerminalPanel: View {
    let handles: [Handle]
    var preselectedPageId: String?
    let onDismiss: () -> Void

    @State private var panelHeight: CGFloat = 300
    @State private var isDragging = false

    private let minHeight: CGFloat = 200
    private let maxHeight: CGFloat = 600

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle + toolbar
            panelToolbar

            Divider()
                .background(Color(white: 0.2))

            // Workspace content (reuses WorkspaceSheet in embedded mode)
            WorkspaceSheet(handles: handles, preselectedPageId: preselectedPageId, embedded: true)
                .frame(height: panelHeight)
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.04))
    }

    private var panelToolbar: some View {
        HStack(spacing: 8) {
            // Drag handle
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .shadow(color: .green.opacity(0.7), radius: 4)
                .padding(.leading, 8)

            Text("WORKSPACE")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(white: 0.5))
                    .frame(width: 20, height: 20)
                    .background(Color(white: 0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.06, green: 0.06, blue: 0.06))
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    let newHeight = panelHeight - value.translation.height
                    panelHeight = min(max(newHeight, minHeight), maxHeight)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .cursor(.resizeUpDown)
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
#endif
