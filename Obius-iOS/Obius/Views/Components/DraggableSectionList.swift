import SwiftUI

/// A draggable list of sections with visual feedback during reordering and drag-to-indent
struct DraggableSectionList: View {
    @Binding var sections: [Section]
    let focusedSectionId: String?
    let isAuthenticated: (String) -> Bool  // Check if locked section is authenticated
    let hasChildren: (String) -> Bool
    let getHandle: (String) -> Handle?  // Get handle for section (Handle Loop support)
    let getDisplayContent: (Section) -> String  // Get display content (handle content if portal)
    let onMove: (Int, Int) -> Void
    let onContentChange: (String, String) -> Void
    let onReturn: (String) -> Void
    let onBackspaceEmpty: (String) -> Void
    let onIndent: (String) -> Void
    let onOutdent: (String) -> Void
    let onSetParent: (String, String?) -> Void  // Set parentSectionId for drag-to-indent
    let onToggleCollapse: (String) -> Void
    let onToggleLock: (String) -> Void
    let onUnlockRequest: (String) -> Void
    let onIntentChange: (String, IntentType) -> Void
    let onDelete: (String) -> Void
    let onFocus: (String) -> Void
    let onDrillIn: (String) -> Void  // Möbius navigation
    let onApplyTemplate: (String) -> Void  // Apply template to section
    let onCreateLoop: (String) -> Void  // Handle Loop: Create new handle from section
    let onUnlinkHandle: (String) -> Void  // Handle Loop: Unlink section from handle
    let getInterstitialContent: (String?) -> String  // Get text after section (nil = end)
    let onInterstitialContentChange: (String?, String) -> Void  // Update text after section

    @State private var draggingSection: Section?
    @State private var dragOffset: CGFloat = 0
    @State private var dropTargetIndex: Int?
    @State private var horizontalDragOffset: CGFloat = 0
    @State private var indentCandidate: String?  // Section ID that would become parent
    @GestureState private var isDragging = false

    private let indentThreshold: CGFloat = 50  // Pixels to drag right to trigger indent
    private let outdentThreshold: CGFloat = -50  // Pixels to drag left to trigger outdent
    private let rowHeight: CGFloat = 60  // Approximate row height for calculating drop position
    
    /// Progress of horizontal drag (0 to 1 for indent, -1 to 0 for outdent)
    private var dragProgress: CGFloat {
        if horizontalDragOffset > 0 {
            return min(horizontalDragOffset / indentThreshold, 1.0)
        } else {
            return max(horizontalDragOffset / abs(outdentThreshold), -1.0)
        }
    }
    
    /// Whether currently dragging past indent threshold
    private var isPastIndentThreshold: Bool {
        horizontalDragOffset > indentThreshold
    }
    
    /// Whether currently dragging past outdent threshold
    private var isPastOutdentThreshold: Bool {
        horizontalDragOffset < outdentThreshold
    }

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    // Section row
                    DraggableSectionRow(
                        section: section,
                        index: index,
                        isFocused: focusedSectionId == section.id,
                        isAuthenticated: isAuthenticated(section.id),
                        hasChildren: hasChildren(section.id),
                        handle: getHandle(section.id),
                        displayContent: getDisplayContent(section),
                        isDragging: draggingSection?.id == section.id,
                        isDropTarget: dropTargetIndex == index,
                        isIndentCandidate: indentCandidate == section.id,
                        horizontalOffset: draggingSection?.id == section.id ? horizontalDragOffset : 0,
                        onDragStart: { startDragging(section) },
                        onDragChanged: { translation in
                            handleDragChanged(section: section, index: index, translation: translation)
                        },
                        onDragEnd: { endDragging(section: section, at: index) },
                        onContentChange: { content in onContentChange(section.id, content) },
                        onReturn: { onReturn(section.id) },
                        onBackspaceEmpty: { onBackspaceEmpty(section.id) },
                        onIndent: { onIndent(section.id) },
                        onOutdent: { onOutdent(section.id) },
                        onToggleCollapse: { onToggleCollapse(section.id) },
                        onToggleLock: { onToggleLock(section.id) },
                        onUnlockRequest: { onUnlockRequest(section.id) },
                        onIntentChange: { intent in onIntentChange(section.id, intent) },
                        onDelete: { onDelete(section.id) },
                        onFocus: { onFocus(section.id) },
                        onDrillIn: { onDrillIn(section.id) },
                        onApplyTemplate: { onApplyTemplate(section.id) },
                        onCreateLoop: { onCreateLoop(section.id) },
                        onUnlinkHandle: { onUnlinkHandle(section.id) }
                    )
                    .zIndex(draggingSection?.id == section.id ? 1 : 0)
                    .onDrop(of: [.text], delegate: SectionDropDelegate(
                        item: section,
                        items: $sections,
                        draggedItem: $draggingSection,
                        dropTargetIndex: $dropTargetIndex,
                        onMove: onMove
                    ))

                    // Interstitial text field after this section
                    InterstitialTextField(
                        afterSectionId: section.id,
                        getContent: getInterstitialContent,
                        onContentChange: onInterstitialContentChange
                    )
                }

                // Interstitial text field at the end (after all sections)
                if !sections.isEmpty {
                    InterstitialTextField(
                        afterSectionId: nil,
                        getContent: getInterstitialContent,
                        onContentChange: onInterstitialContentChange
                    )
                }
            }
            
            // Drag-to-indent feedback overlay
            if draggingSection != nil && abs(horizontalDragOffset) > 20 {
                DragIndentFeedback(
                    isIndenting: horizontalDragOffset > 0,
                    progress: abs(dragProgress)
                )
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.15), value: dragProgress)
            }
        }
    }

    private func startDragging(_ section: Section) {
        withAnimation(.easeInOut(duration: 0.2)) {
            draggingSection = section
        }
        HapticFeedback.impact(.medium)
    }

    private func handleDragChanged(section: Section, index: Int, translation: CGSize) {
        guard draggingSection?.id == section.id else { return }

        horizontalDragOffset = translation.width

        // Calculate target index based on vertical translation
        let rowsMoved = Int(round(translation.height / rowHeight))
        let newTargetIndex = max(0, min(sections.count - 1, index + rowsMoved))

        if newTargetIndex != dropTargetIndex {
            dropTargetIndex = newTargetIndex
            HapticFeedback.selection()
        }

        // Check for indent candidate (section above that could become parent)
        if translation.width > indentThreshold && index > 0 {
            let potentialParent = sections[index - 1]
            if potentialParent.id != section.parentSectionId {
                if indentCandidate != potentialParent.id {
                    indentCandidate = potentialParent.id
                    HapticFeedback.selection()
                }
            }
        } else if translation.width < outdentThreshold {
            // Show outdent visual feedback
            indentCandidate = nil
        } else {
            indentCandidate = nil
        }
    }

    private func endDragging(section: Section, at index: Int) {
        // Handle drag-to-indent
        if horizontalDragOffset > indentThreshold && index > 0 {
            let potentialParent = sections[index - 1]
            if potentialParent.id != section.parentSectionId {
                // Set parent to section above
                onSetParent(section.id, potentialParent.id)
                HapticFeedback.impact(.light)
            }
        } else if horizontalDragOffset < outdentThreshold {
            // Outdent - remove parent
            if section.parentSectionId != nil {
                onSetParent(section.id, nil)
                HapticFeedback.impact(.light)
            }
        }
        
        // Handle vertical reordering
        if let targetIndex = dropTargetIndex, let draggedSection = draggingSection {
            if let fromIndex = sections.firstIndex(where: { $0.id == draggedSection.id }) {
                if fromIndex != targetIndex {
                    onMove(fromIndex, targetIndex)
                    HapticFeedback.impact(.light)
                }
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            draggingSection = nil
            dropTargetIndex = nil
            horizontalDragOffset = 0
            indentCandidate = nil
        }
    }
}

// MARK: - Draggable Section Row

struct DraggableSectionRow: View {
    let section: Section
    let index: Int
    let isFocused: Bool
    let isAuthenticated: Bool
    let hasChildren: Bool
    let handle: Handle?  // Handle Loop support
    let displayContent: String  // Handle Loop: content to display
    let isDragging: Bool
    let isDropTarget: Bool
    let isIndentCandidate: Bool  // This section might become a parent
    let horizontalOffset: CGFloat
    let onDragStart: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnd: () -> Void
    let onContentChange: (String) -> Void
    let onReturn: () -> Void
    let onBackspaceEmpty: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onToggleCollapse: () -> Void
    let onToggleLock: () -> Void
    let onUnlockRequest: () -> Void
    let onIntentChange: (IntentType) -> Void
    let onDelete: () -> Void
    let onFocus: () -> Void
    let onDrillIn: () -> Void
    let onApplyTemplate: () -> Void
    let onCreateLoop: () -> Void  // Handle Loop support
    let onUnlinkHandle: () -> Void  // Handle Loop support

    @State private var dragAmount = CGSize.zero
    @GestureState private var isLongPressing = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Section content using SectionView (centered)
            SectionView(
                section: section,
                isFocused: isFocused,
                isAuthenticated: isAuthenticated,
                hasChildren: hasChildren,
                handle: handle,
                displayContent: displayContent,
                onContentChange: onContentChange,
                onReturn: onReturn,
                onBackspaceEmpty: onBackspaceEmpty,
                onIndent: onIndent,
                onOutdent: onOutdent,
                onToggleCollapse: onToggleCollapse,
                onToggleLock: onToggleLock,
                onUnlockRequest: onUnlockRequest,
                onIntentChange: onIntentChange,
                onFocus: onFocus,
                onDelete: onDelete,
                onApplyTemplate: onApplyTemplate,
                onCreateLoop: onCreateLoop,
                onUnlinkHandle: onUnlinkHandle
            )

            // Drill-in button for sections with children
            if hasChildren {
                DrillInButton(
                    hasChildren: true,
                    childCount: 0,  // Count will be determined by parent
                    onDrillIn: onDrillIn
                )
                .padding(.trailing, 8)
            }
        }
        .background(rowBackground)
        .overlay(dropIndicator)
        .overlay(indentIndicator)
        .offset(x: horizontalOffset * 0.3)  // Partial horizontal offset for visual feedback
        .offset(y: isDragging ? dragAmount.height : 0)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .opacity(isDragging ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture())
                .onChanged { value in
                    switch value {
                    case .first(true):
                        // Long press recognized, but not yet completed
                        break
                    case .second(true, let drag):
                        // Long press completed, now dragging
                        if !isDragging {
                            onDragStart()
                            HapticFeedback.impact(.medium)
                        }
                        if let drag = drag {
                            dragAmount = drag.translation
                            onDragChanged(drag.translation)
                        }
                    default:
                        break
                    }
                }
                .onEnded { value in
                    dragAmount = .zero
                    if isDragging {
                        onDragEnd()
                    }
                }
        )
        .draggable(section.id) {
            DragPreview(section: section)
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(backgroundColor)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
            .animation(.easeInOut(duration: 0.15), value: isIndentCandidate)
    }
    
    private var backgroundColor: Color {
        if isDragging {
            // Dragging state - blue tint
            return Color.accentColor.opacity(0.15)
        } else if isIndentCandidate {
            // This section will become a parent - green glow
            return Color.green.opacity(0.2)
        } else {
            return Color.clear
        }
    }

    @ViewBuilder
    private var dropIndicator: some View {
        if isDropTarget && !isDragging {
            VStack {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .padding(.horizontal, 8)
                Spacer()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
        }
    }
    
    @ViewBuilder
    private var indentIndicator: some View {
        if isIndentCandidate {
            HStack {
                Spacer()
                VStack {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption.weight(.semibold))
                        Text("Nest here")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.2))
                    )
                    Spacer()
                }
                .padding(.top, 6)
                .padding(.trailing, 6)
            }
            .transition(.scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity))
        }
    }
}

// MARK: - Drag Preview

struct DragPreview: View {
    let section: Section

    var body: some View {
        HStack(spacing: 8) {
            // Intent rail
            RoundedRectangle(cornerRadius: 2)
                .fill(section.intent.color)
                .frame(width: 3, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                if let title = section.title, !title.isEmpty {
                    Text(title)
                        .font(.caption.weight(.semibold))
                }
                Text(section.preview)
                    .font(.body)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .shadow(radius: 4)
        )
        .frame(maxWidth: 280)
    }
}

// MARK: - Drop Delegate

struct SectionDropDelegate: DropDelegate {
    let item: Section
    @Binding var items: [Section]
    @Binding var draggedItem: Section?
    @Binding var dropTargetIndex: Int?
    let onMove: (Int, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        dropTargetIndex = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              draggedItem.id != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        dropTargetIndex = toIndex

        if fromIndex != toIndex {
            withAnimation(.easeInOut(duration: 0.2)) {
                items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }

    func dropExited(info: DropInfo) {
        // Keep the drop target visible until drop completes
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Interstitial Text Field

/// A multi-line text editor that appears between sections for free-form text
struct InterstitialTextField: View {
    let afterSectionId: String?  // nil means "at end"
    let getContent: (String?) -> String
    let onContentChange: (String?, String) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .foregroundStyle(.primary)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .frame(minHeight: text.isEmpty && !isFocused ? 28 : 40)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .onChange(of: text) { _, newValue in
                onContentChange(afterSectionId, newValue)
            }
            .onAppear {
                text = getContent(afterSectionId)
            }
    }
}

// MARK: - Haptic Feedback

#if os(iOS)
import UIKit

enum HapticFeedback {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
#else
// macOS stub for HapticFeedback
enum HapticFeedback {
    enum FeedbackStyle { case light, medium, heavy, rigid, soft }
    enum FeedbackType { case success, warning, error }
    
    static func impact(_ style: FeedbackStyle) {}
    static func notification(_ type: FeedbackType) {}
    static func selection() {}
}
#endif

// MARK: - Preview

#Preview {
    struct PreviewContainer: View {
        @State private var sections: [Section] = [
            Section(noteId: "1", content: "First section with some content", orderKey: "A", intent: .idea),
            Section(noteId: "1", content: "Second section - a task", orderKey: "B", intent: .task),
            Section(noteId: "1", content: "Third section - a question", orderKey: "C", indentLevel: 1, intent: .question),
            Section(noteId: "1", content: "Fourth section - evidence", orderKey: "D", intent: .evidence),
        ]
        @State private var focusedId: String?
        
        var body: some View {
            ScrollView {
                DraggableSectionList(
                    sections: $sections,
                    focusedSectionId: focusedId,
                    isAuthenticated: { _ in true },
                    hasChildren: { _ in false },
                    getHandle: { _ in nil },
                    getDisplayContent: { $0.content },
                    onMove: { from, to in
                        sections.move(fromOffsets: IndexSet(integer: from), toOffset: to)
                    },
                    onContentChange: { _, _ in },
                    onReturn: { _ in },
                    onBackspaceEmpty: { _ in },
                    onIndent: { _ in },
                    onOutdent: { _ in },
                    onSetParent: { _, _ in },
                    onToggleCollapse: { _ in },
                    onToggleLock: { _ in },
                    onUnlockRequest: { _ in },
                    onIntentChange: { _, _ in },
                    onDelete: { _ in },
                    onFocus: { id in focusedId = id },
                    onDrillIn: { _ in },
                    onApplyTemplate: { _ in },
                    onCreateLoop: { _ in },
                    onUnlinkHandle: { _ in },
                    getInterstitialContent: { _ in "" },
                    onInterstitialContentChange: { _, _ in }
                )
                .padding()
            }
        }
    }
    
    return PreviewContainer()
}
