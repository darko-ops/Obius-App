import SwiftUI

/// Section view with swipe gestures for indent/outdent
struct SwipeableSectionView: View {
    let section: Section
    let isFocused: Bool
    let onContentChange: (String) -> Void
    let onReturn: () -> Void
    let onBackspaceEmpty: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onToggleCollapse: () -> Void
    let onDelete: () -> Void
    let onFocus: () -> Void

    @State private var content: String
    @State private var swipeOffset: CGFloat = 0
    @State private var showingToolbar = false
    @GestureState private var isDragging = false

    private let swipeThreshold: CGFloat = 60
    private let maxSwipe: CGFloat = 100

    init(
        section: Section,
        isFocused: Bool,
        onContentChange: @escaping (String) -> Void,
        onReturn: @escaping () -> Void,
        onBackspaceEmpty: @escaping () -> Void,
        onIndent: @escaping () -> Void,
        onOutdent: @escaping () -> Void,
        onToggleCollapse: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onFocus: @escaping () -> Void
    ) {
        self.section = section
        self.isFocused = isFocused
        self.onContentChange = onContentChange
        self.onReturn = onReturn
        self.onBackspaceEmpty = onBackspaceEmpty
        self.onIndent = onIndent
        self.onOutdent = onOutdent
        self.onToggleCollapse = onToggleCollapse
        self.onDelete = onDelete
        self.onFocus = onFocus
        _content = State(initialValue: section.content)
    }

    var body: some View {
        ZStack {
            // Background actions
            HStack {
                // Left side - Outdent
                if swipeOffset > 0 {
                    outdentIndicator
                }

                Spacer()

                // Right side - Indent
                if swipeOffset < 0 {
                    indentIndicator
                }
            }

            // Main content
            mainContent
                .offset(x: swipeOffset)
                .gesture(swipeGesture)
        }
        .animation(.spring(response: 0.3), value: swipeOffset)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                // Intent indicator (using the new IntentType)
                Circle()
                    .fill(section.intent.color)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)

                // Content
                VStack(alignment: .leading, spacing: 0) {
                    if section.isCollapsed {
                        HStack {
                            Text(section.preview)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer()

                            // Expand button on the right
                            Button {
                                onToggleCollapse()
                                HapticFeedback.selection()
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.gray.opacity(0.15))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        // Expand is handled by the expand button only to avoid double-toggle
                    } else {
                        TextEditor(text: $content)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 24)
                            .fixedSize(horizontal: false, vertical: true)
                            .onChange(of: content) { _, newValue in
                                // Allow all content including newlines
                                onContentChange(newValue)
                            }
                            .onTapGesture {
                                onFocus()
                            }
                    }
                }

                Spacer(minLength: 0)
            }

            // Collapse button at bottom right (only when expanded)
            if !section.isCollapsed {
                HStack {
                    Spacer()

                    Button {
                        onToggleCollapse()
                        HapticFeedback.selection()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.gray.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
        }
        .padding(.leading, CGFloat(section.indentLevel) * 20)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isFocused ? Color.focusedBackground : section.intent.backgroundTint)
        )
        .contentShape(Rectangle())
        .onLongPressGesture {
            showingToolbar = true
            HapticFeedback.impact(.medium)
        }
        .sheet(isPresented: $showingToolbar) {
            toolbarSheet
                .presentationDetents([.height(80)])
                .presentationDragIndicator(.visible)
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                let translation = value.translation.width

                // Limit swipe amount
                if translation > 0 && section.indentLevel > 0 {
                    // Can outdent
                    swipeOffset = min(translation, maxSwipe)
                } else if translation < 0 && section.indentLevel < 5 {
                    // Can indent
                    swipeOffset = max(translation, -maxSwipe)
                }
            }
            .onEnded { value in
                if swipeOffset > swipeThreshold && section.indentLevel > 0 {
                    // Outdent
                    HapticFeedback.impact(.medium)
                    onOutdent()
                } else if swipeOffset < -swipeThreshold && section.indentLevel < 5 {
                    // Indent
                    HapticFeedback.impact(.medium)
                    onIndent()
                }

                swipeOffset = 0
            }
    }

    private var outdentIndicator: some View {
        HStack {
            Image(systemName: "arrow.left.to.line")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(.leading, 20)

            Spacer()
        }
        .frame(maxWidth: abs(swipeOffset))
        .background(Color.orange)
        .opacity(swipeOffset > swipeThreshold ? 1 : 0.5)
    }

    private var indentIndicator: some View {
        HStack {
            Spacer()

            Image(systemName: "arrow.right.to.line")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(.trailing, 20)
        }
        .frame(maxWidth: abs(swipeOffset))
        .background(Color.blue)
        .opacity(abs(swipeOffset) > swipeThreshold ? 1 : 0.5)
    }

    private var toolbarSheet: some View {
        InlineSectionToolbar(section: section) { action in
            switch action {
            case .indent:
                onIndent()
            case .outdent:
                onOutdent()
            case .collapse:
                onToggleCollapse()
            case .delete:
                onDelete()
            case .duplicate:
                break // TODO: Implement duplicate
            case .intent(_):
                break // Intent changes handled via context menu
            case .lock:
                break // Lock toggle handled via context menu
            case .moveUp, .moveDown:
                break // Handled by drag
            }
            showingToolbar = false
        }
    }
}

#Preview {
    VStack {
        SwipeableSectionView(
            section: Section(
                noteId: "1",
                content: "Swipe left to indent, right to outdent",
                orderKey: "A",
                indentLevel: 1,
                intent: .idea
            ),
            isFocused: false,
            onContentChange: { _ in },
            onReturn: {},
            onBackspaceEmpty: {},
            onIndent: {},
            onOutdent: {},
            onToggleCollapse: {},
            onDelete: {},
            onFocus: {}
        )

        SwipeableSectionView(
            section: Section(
                noteId: "1",
                content: "This section is focused",
                orderKey: "B",
                indentLevel: 0,
                intent: .task
            ),
            isFocused: true,
            onContentChange: { _ in },
            onReturn: {},
            onBackspaceEmpty: {},
            onIndent: {},
            onOutdent: {},
            onToggleCollapse: {},
            onDelete: {},
            onFocus: {}
        )
    }
    .padding()
}
