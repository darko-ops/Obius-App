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
        withAnimation(.easeInOut(duration: 0.2)) {
            draggingSection = section
        }
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
        }
        .background(rowBackground)
        .overlay(insightHighlightOverlay)
        .overlay(dropIndicator)
        .clipped()  // Prevent gesture recognizers from extending beyond row bounds
        .contentShape(Rectangle())  // Constrain hit-testing to the row's frame
        .offset(y: isDragging ? dragAmount.height : 0)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .opacity(isDragging ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        // Use simultaneousGesture so the parent ScrollView's scroll gesture
        // isn't blocked. The long press (0.3s) naturally fails during a scroll
        // because the finger moves, so only a deliberate hold activates reorder.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture())
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
                .onEnded { value in
                    dragAmount = .zero
                    if isDragging {
                        onDragEnd()
                    }
                }
        )
        .transaction { transaction in
            if !isDragging {
                transaction.animation = nil
            }
        }
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
            // Sync text when the underlying model changes (e.g. content merged during section deletion)
            if newContent != text {
                isExternalUpdate = true
                text = newContent
                // Delay reset to absorb the write-back cascade from the text view
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isExternalUpdate = false
                }
            }
        }
    }
}

#if os(iOS)
/// Keyboard toolbar with formatting buttons and dismiss for interstitial text
private class InterstitialKeyboardToolbar: UIToolbar {
    weak var textView: UITextView?
    var onDismiss: (() -> Void)?

    private var titleButton: UIBarButtonItem?
    private var boldButton: UIBarButtonItem?
    private var italicButton: UIBarButtonItem?
    private var underlineButton: UIBarButtonItem?

    // Track active formatting states for typing
    private var isTitleActive = false
    private var isBoldActive = false
    private var isItalicActive = false
    private var isUnderlineActive = false

    private var normalFontSize: CGFloat {
        UIFont.preferredFont(forTextStyle: .body).pointSize
    }

    private var titleFontSize: CGFloat {
        UIFont.preferredFont(forTextStyle: .body).pointSize * 2
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupToolbar()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupToolbar()
    }

    convenience init() {
        self.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
    }

    private func setupToolbar() {
        barStyle = .default
        isTranslucent = true
        sizeToFit()

        var items: [UIBarButtonItem] = []

        // Indent/Outdent buttons (visual consistency, no action for interstitials)
        let outdentButton = UIBarButtonItem(
            image: UIImage(systemName: "decrease.indent"),
            style: .plain,
            target: nil,
            action: nil
        )
        outdentButton.isEnabled = false
        items.append(outdentButton)

        let indentButton = UIBarButtonItem(
            image: UIImage(systemName: "increase.indent"),
            style: .plain,
            target: nil,
            action: nil
        )
        indentButton.isEnabled = false
        items.append(indentButton)

        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        items.append(flexSpace)

        // Title size button
        let title = UIBarButtonItem(
            image: UIImage(systemName: "textformat.size"),
            style: .plain,
            target: self,
            action: #selector(titleTapped)
        )
        titleButton = title
        items.append(title)

        // Formatting buttons: Bold, Italic, Underline
        let bold = UIBarButtonItem(
            image: UIImage(systemName: "bold"),
            style: .plain,
            target: self,
            action: #selector(boldTapped)
        )
        boldButton = bold
        items.append(bold)

        let italic = UIBarButtonItem(
            image: UIImage(systemName: "italic"),
            style: .plain,
            target: self,
            action: #selector(italicTapped)
        )
        italicButton = italic
        items.append(italic)

        let underline = UIBarButtonItem(
            image: UIImage(systemName: "underline"),
            style: .plain,
            target: self,
            action: #selector(underlineTapped)
        )
        underlineButton = underline
        items.append(underline)

        // Add spacing
        let fixedSpace = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpace.width = 12
        items.append(fixedSpace)

        // Dismiss button (far right)
        let dismissButton = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .plain,
            target: self,
            action: #selector(dismissTapped)
        )
        items.append(dismissButton)

        setItems(items, animated: false)
    }

    private func updateButtonAppearance() {
        titleButton?.tintColor = isTitleActive ? .systemPurple : nil
        boldButton?.tintColor = isBoldActive ? .systemPurple : nil
        italicButton?.tintColor = isItalicActive ? .systemPurple : nil
        underlineButton?.tintColor = isUnderlineActive ? .systemPurple : nil
    }

    /// Sync button states with the text view's current typing attributes
    func syncWithTypingAttributes() {
        guard let textView = textView else { return }
        let attrs = textView.typingAttributes
        let font = (attrs[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
        let traits = font.fontDescriptor.symbolicTraits

        isTitleActive = font.pointSize >= titleFontSize && traits.contains(.traitBold)
        isBoldActive = traits.contains(.traitBold) && !isTitleActive
        isItalicActive = traits.contains(.traitItalic)
        isUnderlineActive = (attrs[.underlineStyle] as? Int) != nil && (attrs[.underlineStyle] as? Int) != 0

        updateButtonAppearance()
    }

    @objc private func titleTapped() {
        guard let textView = textView else { return }
        isTitleActive.toggle()
        let range = textView.selectedRange

        if range.length > 0 {
            let mutableAttrString = NSMutableAttributedString(attributedString: textView.attributedText)
            mutableAttrString.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let currentFont = (value as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
                let size = isTitleActive ? titleFontSize : normalFontSize
                var traits = currentFont.fontDescriptor.symbolicTraits
                if isTitleActive { traits.insert(.traitBold) }
                if let desc = currentFont.fontDescriptor.withSymbolicTraits(traits) {
                    let newFont = UIFont(descriptor: desc, size: size)
                    mutableAttrString.addAttribute(.font, value: newFont, range: subRange)
                }
            }
            textView.attributedText = mutableAttrString
            textView.selectedRange = range
            notifyContentChanged()
        } else {
            var attrs = textView.typingAttributes
            let currentFont = (attrs[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
            let size = isTitleActive ? titleFontSize : normalFontSize
            var traits = currentFont.fontDescriptor.symbolicTraits
            if isTitleActive { traits.insert(.traitBold) } else if !isBoldActive { traits.remove(.traitBold) }
            if let desc = currentFont.fontDescriptor.withSymbolicTraits(traits) {
                attrs[.font] = UIFont(descriptor: desc, size: size)
                textView.typingAttributes = attrs
            }
        }

        updateButtonAppearance()
    }

    @objc private func boldTapped() {
        guard let textView = textView else { return }
        let range = textView.selectedRange

        if range.length > 0 {
            applyFontTraitToSelection(.traitBold, in: textView)
        } else {
            isBoldActive.toggle()
            applyFontTraitToTyping(.traitBold, isActive: isBoldActive, in: textView)
        }
        updateButtonAppearance()
    }

    @objc private func italicTapped() {
        guard let textView = textView else { return }
        let range = textView.selectedRange

        if range.length > 0 {
            applyFontTraitToSelection(.traitItalic, in: textView)
        } else {
            isItalicActive.toggle()
            applyFontTraitToTyping(.traitItalic, isActive: isItalicActive, in: textView)
        }
        updateButtonAppearance()
    }

    @objc private func underlineTapped() {
        guard let textView = textView else { return }
        let range = textView.selectedRange

        if range.length > 0 {
            let mutableAttrString = NSMutableAttributedString(attributedString: textView.attributedText)

            var isUnderlined = false
            mutableAttrString.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
                if let style = value as? Int, style != 0 {
                    isUnderlined = true
                }
            }

            if isUnderlined {
                mutableAttrString.removeAttribute(.underlineStyle, range: range)
            } else {
                mutableAttrString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }

            textView.attributedText = mutableAttrString
            textView.selectedRange = range
            notifyContentChanged()
        } else {
            isUnderlineActive.toggle()
            var attrs = textView.typingAttributes
            if isUnderlineActive {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                attrs.removeValue(forKey: .underlineStyle)
            }
            textView.typingAttributes = attrs
        }
        updateButtonAppearance()
    }

    private func applyFontTraitToSelection(_ trait: UIFontDescriptor.SymbolicTraits, in textView: UITextView) {
        let range = textView.selectedRange
        guard range.length > 0 else { return }

        let mutableAttrString = NSMutableAttributedString(attributedString: textView.attributedText)

        mutableAttrString.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let currentFont = (value as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
            var newTraits = currentFont.fontDescriptor.symbolicTraits

            if newTraits.contains(trait) {
                newTraits.remove(trait)
            } else {
                newTraits.insert(trait)
            }

            if let newDescriptor = currentFont.fontDescriptor.withSymbolicTraits(newTraits) {
                let newFont = UIFont(descriptor: newDescriptor, size: currentFont.pointSize)
                mutableAttrString.addAttribute(.font, value: newFont, range: subRange)
            }
        }

        textView.attributedText = mutableAttrString
        textView.selectedRange = range
        notifyContentChanged()
    }

    private func applyFontTraitToTyping(_ trait: UIFontDescriptor.SymbolicTraits, isActive: Bool, in textView: UITextView) {
        var attrs = textView.typingAttributes
        let currentFont = (attrs[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
        var newTraits = currentFont.fontDescriptor.symbolicTraits

        if isActive {
            newTraits.insert(trait)
        } else {
            newTraits.remove(trait)
        }

        if let newDescriptor = currentFont.fontDescriptor.withSymbolicTraits(newTraits) {
            let newFont = UIFont(descriptor: newDescriptor, size: currentFont.pointSize)
            attrs[.font] = newFont
            textView.typingAttributes = attrs
        }
    }

    /// Notify the delegate that content changed so rich text formatting is persisted.
    /// UIKit does NOT call textViewDidChange when attributedText is set programmatically,
    /// so we must trigger the save manually after formatting changes.
    private func notifyContentChanged() {
        guard let textView = textView else { return }
        textView.delegate?.textViewDidChange?(textView)
    }

    @objc private func dismissTapped() {
        onDismiss?()
    }
}

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
        textView.font = UIFont.preferredFont(forTextStyle: .body)
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

        // Add keyboard accessory toolbar with formatting and dismiss buttons
        let toolbar = InterstitialKeyboardToolbar()
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
            if let toolbar = textView.inputAccessoryView as? InterstitialKeyboardToolbar {
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
            if let toolbar = textView.inputAccessoryView as? InterstitialKeyboardToolbar {
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
