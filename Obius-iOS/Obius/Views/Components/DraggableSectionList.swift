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
    let onContentChange: (String, String, String?) -> Void
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
    let onShare: (String) -> Void  // Share this node
    let onCopy: (String) -> Void  // Copy this node to clipboard
    let onPaste: (String) -> Void  // Paste copied node after this node
    let hasCopiedSection: Bool  // Whether a section is on the clipboard
    let onImageTap: (String) -> Void  // Open image picker for section
    let mediaRepository: MediaRepository?  // For loading image data in image nodes
    var onResolveConflict: (String) -> Void = { _ in }  // Resolve sync conflict for section
    let getInterstitialContent: (String?) -> String  // Get text after section (nil = end)
    let getInterstitialRichContent: (String?) -> String?  // Get rich text after section (nil = end)
    let onInterstitialContentChange: (String?, String, String?) -> Void  // Update text after section (id, content, richText)
    let onInterstitialBackspaceEmpty: (String?) -> Void  // Backspace on empty interstitial
    var onEditWithAI: ((String) -> Void)? = nil  // Open AI Workspace focused on section
    var insightHighlights: [String: Color] = [:]  // sectionId → tint color for insight radar
    var sectionInsights: [String: [Insight]] = [:]  // sectionId → insights for inline chips
    var onInsightTap: ((Insight) -> Void)? = nil

    @State private var draggingSection: Section?
    @State private var dragOffset: CGFloat = 0
    @State private var dropTargetIndex: Int?
    @GestureState private var isDragging = false

    private let rowHeight: CGFloat = 60  // Approximate row height for calculating drop position

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    // Section row (no layout animation)
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
                        onDragStart: { startDragging(section) },
                        onDragChanged: { translation in
                            handleDragChanged(section: section, index: index, translation: translation)
                        },
                        onDragEnd: { endDragging(section: section, at: index) },
                        onContentChange: { content, richText in onContentChange(section.id, content, richText) },
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
                        onUnlinkHandle: { onUnlinkHandle(section.id) },
                        onShare: { onShare(section.id) },
                        onCopy: { onCopy(section.id) },
                        onPaste: { onPaste(section.id) },
                        hasCopiedSection: hasCopiedSection,
                        onImageTap: { onImageTap(section.id) },
                        mediaRepository: mediaRepository,
                        onResolveConflict: { onResolveConflict(section.id) },
                        onEditWithAI: onEditWithAI.map { callback in { callback(section.id) } },
                        insightTintColor: insightHighlights[section.id]
                    )
                    .id(section.id)  // For ScrollViewReader
                    .zIndex(draggingSection?.id == section.id ? 1 : 0)

                    // Inline insight chips for this section
                    if let insights = sectionInsights[section.id], !insights.isEmpty {
                        InlineInsightChips(insights: insights, onTap: onInsightTap)
                            .padding(.leading, 16)
                            .padding(.vertical, 2)
                    }

                    // Interstitial text field after this section
                    InterstitialTextField(
                        afterSectionId: section.id,
                        getContent: getInterstitialContent,
                        getRichContent: getInterstitialRichContent,
                        onContentChange: onInterstitialContentChange,
                        onBackspaceEmpty: onInterstitialBackspaceEmpty,
                        modelContent: getInterstitialContent(section.id)
                    )
                    .id("interstitial-\(section.id)")
                }
            }
            .animation(nil, value: sections.count)  // Prevent layout animations when content changes

        }
    }

    private func startDragging(_ section: Section) {
        // Setting draggingSection without withAnimation: the row's own
        // .animation(.easeInOut, value: isDragging) handles the scale/opacity
        // transition. A withAnimation here propagates a transaction into the
        // child views that bled into the row's offset updates as flicker.
        draggingSection = section
        HapticFeedback.impact(.medium)
    }

    private func handleDragChanged(section: Section, index: Int, translation: CGSize) {
        guard draggingSection?.id == section.id else { return }

        // Calculate target index based on vertical translation only
        let rowsMoved = Int(round(translation.height / rowHeight))
        let newTargetIndex = max(0, min(sections.count - 1, index + rowsMoved))

        if newTargetIndex != dropTargetIndex {
            dropTargetIndex = newTargetIndex
            HapticFeedback.selection()
        }
    }

    private func endDragging(section: Section, at index: Int) {
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
    let onDragStart: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnd: () -> Void
    let onContentChange: (String, String?) -> Void
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
    let onShare: () -> Void  // Share node
    let onCopy: () -> Void  // Copy node to clipboard
    let onPaste: () -> Void  // Paste copied node after this node
    let hasCopiedSection: Bool  // Whether a section is on the clipboard
    let onImageTap: () -> Void  // Image node tap
    let mediaRepository: MediaRepository?  // For image nodes
    var onResolveConflict: () -> Void = {}
    var onEditWithAI: (() -> Void)? = nil  // AI Workspace on this section
    var insightTintColor: Color? = nil  // Insight radar highlight

    @State private var dragAmount = CGSize.zero
    @GestureState private var isLongPressing = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
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
                onUnlinkHandle: onUnlinkHandle,
                onShare: onShare,
                onCopy: onCopy,
                onPaste: onPaste,
                hasCopiedSection: hasCopiedSection,
                onEditWithAI: onEditWithAI,
                onImageTap: onImageTap,
                mediaRepository: mediaRepository,
                onResolveConflict: onResolveConflict
            )

            if hasChildren {
                DrillInButton(
                    hasChildren: true,
                    childCount: 0,
                    onDrillIn: onDrillIn
                )
                .padding(.trailing, 8)
            }

            dragHandle
        }
        .background(rowBackground)
        .overlay(insightHighlightOverlay)
        .overlay(dropIndicator)
        .clipped()
        .offset(y: isDragging ? dragAmount.height : 0)
        // Offset must track the finger 1:1 — every implicit animation here
        // shows up as visible jitter because dragAmount updates ~60×/s and
        // any interpolation lasting more than a frame falls behind. Keep
        // the scale/opacity animation below; it only fires when isDragging
        // toggles, not when dragAmount changes.
        .animation(nil, value: dragAmount)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .opacity(isDragging ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .transaction { transaction in
            if !isDragging {
                transaction.animation = nil
            }
        }
    }

    /// Dedicated leading-edge drag affordance. The reorder gesture lives only
    /// here, not on the row body — so finger-down anywhere on the section
    /// content passes straight through to the parent ScrollView's pan and
    /// scroll (including on collapsed rows) is unimpeded.
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption.weight(.medium))
            .foregroundStyle(isDragging ? Color.accentColor : Color.secondary.opacity(0.55))
            .frame(width: 22)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        switch value {
                        case .first(true):
                            break
                        case .second(true, let drag):
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
                    .onEnded { _ in
                        dragAmount = .zero
                        if isDragging {
                            onDragEnd()
                        }
                    }
            )
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isDragging ? Color.accentColor.opacity(0.15) : Color.clear)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
    }

    @ViewBuilder
    private var insightHighlightOverlay: some View {
        if let tint = insightTintColor {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(tint)
                    .frame(width: 2.5)
                Spacer()
            }
            .allowsHitTesting(false)
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
    
}

// MARK: - Inline Insight Chips

/// Compact insight chips shown inline below a section when radar is active.
struct InlineInsightChips: View {
    let insights: [Insight]
    let onTap: ((Insight) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(insights) { insight in
                HStack(spacing: 4) {
                    Image(systemName: insight.displayIcon)
                        .font(.system(size: 8))
                    Text(insight.title)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(insight.displayTint.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(insight.displayTint.color.opacity(0.1))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(insight.displayTint.color.opacity(0.25), lineWidth: 0.5)
                )
                .contentShape(Capsule())
                .simultaneousGesture(TapGesture().onEnded { onTap?(insight) })
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Interstitial Text Field

/// A multi-line text editor that appears between sections for free-form text
struct InterstitialTextField: View {
    let afterSectionId: String?  // nil means "at end"
    let getContent: (String?) -> String
    let getRichContent: (String?) -> String?
    let onContentChange: (String?, String, String?) -> Void
    let onBackspaceEmpty: (String?) -> Void  // Called when backspace on empty field

    @State private var text: String = ""
    @State private var isExternalUpdate: Bool = false
    @FocusState private var isFocused: Bool

    /// The current model content — passed from the parent so we can observe changes
    var modelContent: String = ""

    var body: some View {
        InterstitialTextView(
            text: $text,
            isFocused: $isFocused,
            richText: getRichContent(afterSectionId),
            onContentChange: { newValue, richText in
                guard !isExternalUpdate else { return }
                onContentChange(afterSectionId, newValue, richText)
            },
            onBackspaceEmpty: {
                onBackspaceEmpty(afterSectionId)
            }
        )
        .contentShape(Rectangle())  // Ensure entire area is tappable
        .padding(.horizontal, 10)
        .animation(nil, value: text)  // Prevent layout animations
        .onAppear {
            text = getContent(afterSectionId)
        }
        .onChange(of: modelContent) { _, newContent in
            // Sync text when the underlying model changes (e.g. content merged during section deletion).
            // While the user is typing, the local @State is the source of truth — async DB writes echo
            // back out of order and would otherwise revert the text mid-keystroke and jump the caret.
            // Reconcile on blur instead (see .onChange of isFocused below).
            guard !isFocused else { return }
            if newContent != text {
                isExternalUpdate = true
                text = newContent
                // Delay reset to absorb the write-back cascade from the text view
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isExternalUpdate = false
                }
            }
        }
        .onChange(of: isFocused) { _, focused in
            // Reconcile text with the latest model on blur — observation-driven updates
            // are suppressed during typing to prevent caret jumps from stale echoes.
            if !focused, modelContent != text {
                isExternalUpdate = true
                text = modelContent
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isExternalUpdate = false
                }
            }
        }
    }
}

#if os(iOS)
// Note: the previous `InterstitialKeyboardToolbar` (UIToolbar subclass) was
// removed in favour of the shared `BodyKeyboardToolbar` (plain UIView) so
// iOS 26 stops auto-pilling each UIBarButtonItem into its own bubble.

/// Custom UITextView wrapper with proper cursor positioning and tap handling
struct InterstitialTextView: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var richText: String?
    let onContentChange: (String, String?) -> Void
    let onBackspaceEmpty: () -> Void

    func makeUIView(context: Context) -> SelfSizingTextView {
        // Use SelfSizingTextView which has proper single-tap handling
        let textView = SelfSizingTextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: RichTextHelper.bodySize)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)

        // Load rich text if available, otherwise plain text
        if let richText = richText,
           let attrText = RichTextHelper.deserialize(richText) {
            textView.attributedText = attrText
        }

        // Highlight any existing hashtags on load
        HashtagHelper.applyHighlighting(to: textView)

        // Add keyboard accessory toolbar with formatting and dismiss buttons.
        // Uses BodyKeyboardToolbar (UIView, not UIToolbar) so iOS 26 doesn't
        // auto-pill every button into its own bubble.
        let toolbar = BodyKeyboardToolbar()
        toolbar.textView = textView
        toolbar.onDismiss = { [weak textView] in
            textView?.resignFirstResponder()
        }
        textView.inputAccessoryView = toolbar

        return textView
    }

    func updateUIView(_ textView: SelfSizingTextView, context: Context) {
        if !textView.isFirstResponder, textView.text != text {
            if let richText = richText,
               let attrText = RichTextHelper.deserialize(richText) {
                textView.attributedText = attrText
            } else {
                textView.text = text
            }
        }
        textView.invalidateIntrinsicContentSize()

        if isFocused.wrappedValue && !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: InterstitialTextView

        init(_ parent: InterstitialTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = true
            // Sync toolbar button states with current typing attributes
            if let toolbar = textView.inputAccessoryView as? BodyKeyboardToolbar {
                toolbar.syncWithTypingAttributes()
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = false
            // Save rich text formatting when focus leaves
            let richText = RichTextHelper.serialize(textView.attributedText)
            parent.onContentChange(textView.text ?? "", richText)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Sync toolbar button states when cursor moves
            if let toolbar = textView.inputAccessoryView as? BodyKeyboardToolbar {
                toolbar.syncWithTypingAttributes()
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            HashtagHelper.applyHighlighting(to: textView)
            let newText = textView.text ?? ""
            let richText = RichTextHelper.serialize(textView.attributedText)
            if parent.text != newText {
                parent.text = newText
            }
            parent.onContentChange(newText, richText)
            textView.invalidateIntrinsicContentSize()
        }

        // Detect backspace on empty text
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Check if backspace was pressed (empty replacement) on empty text
            if text.isEmpty && textView.text.isEmpty {
                parent.onBackspaceEmpty()
                return false
            }
            return true
        }
    }
}
#else
/// macOS interstitial using EditableTextView (NSTextView) for rich text support
struct InterstitialTextView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var richText: String?
    let onContentChange: (String, String?) -> Void
    let onBackspaceEmpty: () -> Void

    @State private var dynamicHeight: CGFloat = 24

    var body: some View {
        EditableTextView(
            text: $text,
            isFocused: isFocused,
            richText: richText,
            onContentChange: onContentChange,
            onFocusChange: { _ in },
            dynamicHeight: $dynamicHeight
        )
        .frame(height: max(24, dynamicHeight))
    }
}
#endif

// MARK: - Haptic Feedback

#if os(iOS)
import UIKit

enum HapticFeedback {
    typealias FeedbackStyle = UIImpactFeedbackGenerator.FeedbackStyle
    typealias FeedbackType = UINotificationFeedbackGenerator.FeedbackType

    static func impact(_ style: FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func notification(_ type: FeedbackType) {
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
                    onContentChange: { _, _, _ in },
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
                    onShare: { _ in },
                    onCopy: { _ in },
                    onPaste: { _ in },
                    hasCopiedSection: false,
                    onImageTap: { _ in },
                    mediaRepository: nil,
                    getInterstitialContent: { _ in "" },
                    getInterstitialRichContent: { _ in nil },
                    onInterstitialContentChange: { _, _, _ in },
                    onInterstitialBackspaceEmpty: { _ in }
                )
                .padding()
            }
        }
    }
    
    return PreviewContainer()
}
