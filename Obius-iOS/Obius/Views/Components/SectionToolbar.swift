import SwiftUI

/// Floating toolbar that appears when a section is focused
struct SectionToolbar: View {
    let section: Section
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onToggleCollapse: () -> Void
    let onToggleLock: () -> Void
    let onDelete: () -> Void
    let onIntentChange: (IntentType) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Move buttons
            Group {
                toolbarButton(icon: "arrow.up", action: onMoveUp)
                toolbarButton(icon: "arrow.down", action: onMoveDown)
            }

            Divider()
                .frame(height: 20)

            // Indent buttons
            Group {
                toolbarButton(icon: "decrease.indent", action: onOutdent)
                    .disabled(section.indentLevel == 0)
                toolbarButton(icon: "increase.indent", action: onIndent)
                    .disabled(section.indentLevel >= 5)
            }

            Divider()
                .frame(height: 20)

            // Collapse
            toolbarButton(
                icon: section.isCollapsed ? "chevron.right.circle" : "chevron.down.circle",
                action: onToggleCollapse
            )
            
            // Lock
            toolbarButton(
                icon: section.isLocked ? "lock.fill" : "lock.open",
                tint: section.isLocked ? .orange : .primary,
                action: onToggleLock
            )

            // Intent picker
            Menu {
                ForEach(IntentType.allCases, id: \.self) { intent in
                    Button {
                        onIntentChange(intent)
                    } label: {
                        Label {
                            HStack {
                                Text(intent.displayName)
                                if section.intent == intent {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        } icon: {
                            Image(systemName: intent.icon)
                        }
                    }
                }
            } label: {
                Image(systemName: section.intent.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(section.intent.color)
                    .frame(width: 32, height: 32)
            }

            Divider()
                .frame(height: 20)

            // Delete
            toolbarButton(icon: "trash", tint: .red, action: onDelete)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
    }

    private func toolbarButton(
        icon: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticFeedback.selection()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }
}

/// Compact inline toolbar that shows on long press
struct InlineSectionToolbar: View {
    let section: Section
    let onAction: (SectionAction) -> Void

    enum SectionAction {
        case indent
        case outdent
        case collapse
        case lock
        case delete
        case intent(IntentType)
        case moveUp
        case moveDown
        case duplicate
    }

    var body: some View {
        HStack(spacing: 16) {
            actionButton(.outdent, icon: "arrow.left.to.line", disabled: section.indentLevel == 0)
            actionButton(.indent, icon: "arrow.right.to.line", disabled: section.indentLevel >= 5)
            actionButton(.collapse, icon: section.isCollapsed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            actionButton(.lock, icon: section.isLocked ? "lock.fill" : "lock.open", tint: section.isLocked ? .orange : .primary)
            actionButton(.duplicate, icon: "doc.on.doc")
            actionButton(.delete, icon: "trash", tint: .red)
        }
        .padding()
    }

    private func actionButton(
        _ action: SectionAction,
        icon: String,
        tint: Color = .primary,
        disabled: Bool = false
    ) -> some View {
        Button {
            HapticFeedback.impact(.light)
            onAction(action)
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(disabled ? Color.gray.opacity(0.3) : tint)
        }
        .disabled(disabled)
    }
}

#Preview {
    VStack(spacing: 40) {
        SectionToolbar(
            section: Section(noteId: "1", orderKey: "A", indentLevel: 1, intent: .task),
            onIndent: {},
            onOutdent: {},
            onToggleCollapse: {},
            onToggleLock: {},
            onDelete: {},
            onIntentChange: { _ in },
            onMoveUp: {},
            onMoveDown: {}
        )

        InlineSectionToolbar(
            section: Section(noteId: "1", orderKey: "A"),
            onAction: { _ in }
        )
    }
    .padding()
}
