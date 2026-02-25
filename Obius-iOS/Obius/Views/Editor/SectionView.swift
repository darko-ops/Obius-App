import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Rich Text Serialization

#if os(iOS)
/// Helper for serializing/deserializing NSAttributedString to/from base64-encoded RTF
enum RichTextHelper {
    /// Serialize NSAttributedString to base64-encoded RTF
    static func serialize(_ attributedText: NSAttributedString) -> String? {
        guard attributedText.length > 0 else { return nil }
        guard let data = try? attributedText.data(
            from: NSRange(location: 0, length: attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) else { return nil }
        return data.base64EncodedString()
    }

    /// Deserialize base64-encoded RTF to NSAttributedString
    static func deserialize(_ base64String: String) -> NSAttributedString? {
        guard let data = Data(base64Encoded: base64String) else { return nil }
        return try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }
}
#endif

/// The main section view component with Intent Rail, background tinting, and shimmer lock support
struct SectionView: View {
    let section: Section
    let isFocused: Bool
    let isAuthenticated: Bool  // Whether this locked section has been authenticated
    let hasChildren: Bool  // Whether this section has child sections

    // Handle Loop support
    let handle: Handle?  // The handle this section is linked to (if portal)
    let displayContent: String  // Content to display (handle content if portal, section content otherwise)

    let onContentChange: (String, String?) -> Void
    let onReturn: () -> Void
    let onBackspaceEmpty: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onToggleCollapse: () -> Void
    let onToggleLock: () -> Void
    let onUnlockRequest: () -> Void  // Request biometric authentication
    let onIntentChange: (IntentType) -> Void
    let onFocus: () -> Void  // Called when section gains focus
    let onDelete: () -> Void  // Delete this section
    let onApplyTemplate: () -> Void  // Apply a template to this section

    // Handle Loop callbacks
    let onCreateLoop: () -> Void  // Create a new handle from this section
    let onUnlinkHandle: () -> Void  // Unlink this section from its handle

    // Share callback
    let onShare: () -> Void  // Share this node

    // Copy/Paste callbacks
    let onCopy: () -> Void  // Copy this node to clipboard
    let onPaste: () -> Void  // Paste copied node after this node
    let hasCopiedSection: Bool  // Whether a section is on the clipboard

    // Image node callback
    let onImageTap: () -> Void  // Open image picker for this section
    let mediaRepository: MediaRepository?  // For loading image data

    @State private var content: String
    @State private var isEditing = false
    @State private var isProcessingLock = false
    @State private var imageDominantColor: Color?
    @State private var imageNodeBackground: UIImage?
    @FocusState private var textFieldFocused: Bool

    @StateObject private var biometricManager = BiometricManager.shared
    
    init(
        section: Section,
        isFocused: Bool,
        isAuthenticated: Bool = false,
        hasChildren: Bool = false,
        handle: Handle? = nil,
        displayContent: String? = nil,
        onContentChange: @escaping (String, String?) -> Void,
        onReturn: @escaping () -> Void,
        onBackspaceEmpty: @escaping () -> Void,
        onIndent: @escaping () -> Void,
        onOutdent: @escaping () -> Void,
        onToggleCollapse: @escaping () -> Void,
        onToggleLock: @escaping () -> Void = {},
        onUnlockRequest: @escaping () -> Void = {},
        onIntentChange: @escaping (IntentType) -> Void = { _ in },
        onFocus: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        onApplyTemplate: @escaping () -> Void = {},
        onCreateLoop: @escaping () -> Void = {},
        onUnlinkHandle: @escaping () -> Void = {},
        onShare: @escaping () -> Void = {},
        onCopy: @escaping () -> Void = {},
        onPaste: @escaping () -> Void = {},
        hasCopiedSection: Bool = false,
        onImageTap: @escaping () -> Void = {},
        mediaRepository: MediaRepository? = nil
    ) {
        self.section = section
        self.isFocused = isFocused
        self.isAuthenticated = isAuthenticated
        self.hasChildren = hasChildren
        self.handle = handle
        self.displayContent = displayContent ?? handle?.content ?? section.content
        self.onContentChange = onContentChange
        self.onReturn = onReturn
        self.onBackspaceEmpty = onBackspaceEmpty
        self.onIndent = onIndent
        self.onOutdent = onOutdent
        self.onToggleCollapse = onToggleCollapse
        self.onToggleLock = onToggleLock
        self.onUnlockRequest = onUnlockRequest
        self.onIntentChange = onIntentChange
        self.onFocus = onFocus
        self.onDelete = onDelete
        self.onApplyTemplate = onApplyTemplate
        self.onCreateLoop = onCreateLoop
        self.onUnlinkHandle = onUnlinkHandle
        self.onShare = onShare
        self.onCopy = onCopy
        self.onPaste = onPaste
        self.hasCopiedSection = hasCopiedSection
        self.onImageTap = onImageTap
        self.mediaRepository = mediaRepository

        // Initialize content, ensuring template prefix is included for template sections
        var initialContent = displayContent ?? handle?.content ?? section.content
        if section.isTemplateContent,
           let templatePrefix = section.templatePrefix,
           !templatePrefix.isEmpty,
           !initialContent.contains(templatePrefix) {
            initialContent = templatePrefix + initialContent
        }
        _content = State(initialValue: initialContent)
    }
    
    var body: some View {
        // Render differently based on section type
        Group {
            if section.contentType == .audio {
                audioNodeFoldView
            } else if section.contentType == .image {
                imageNodeFoldView
            } else if section.sectionType == .line {
                lineView
            } else {
                foldView
            }
        }
        .padding(.leading, CGFloat(section.indentLevel) * 24)
        .onChange(of: isFocused) { _, newValue in
            // Image/audio sections have no text field — skip focus handling
            guard section.contentType != .image && section.contentType != .audio else { return }

            if newValue && (!section.isLocked || isAuthenticated) {
                // Small delay to ensure view is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    textFieldFocused = true
                    isEditing = true
                }
            } else if !newValue && section.isLocked {
                // Auto-lock when focus leaves a locked node
                biometricManager.lockSection(section.id)
            }
        }
        .onAppear {
            // Focus immediately if this section is already marked as focused
            // Image/audio sections have no text field — skip focus handling
            if isFocused && (!section.isLocked || isAuthenticated) && section.contentType != .image && section.contentType != .audio {
                // Use a slight delay to ensure the view hierarchy is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    textFieldFocused = true
                    isEditing = true
                    onFocus()
                }
            }

            // If template prefix was added to content but not saved, save it now
            if section.isTemplateContent,
               let templatePrefix = section.templatePrefix,
               !templatePrefix.isEmpty,
               !section.content.contains(templatePrefix),
               content.contains(templatePrefix) {
                onContentChange(content, nil)
            }
        }
        .onChange(of: displayContent) { _, newValue in
            // Only sync from external source when NOT actively editing
            // to prevent cursor jumping during typing
            if !textFieldFocused && content != newValue {
                content = newValue
            }
        }
        .onChange(of: section.handleId) { _, _ in
            // When a section is linked/unlinked from a handle,
            // always sync content regardless of focus state
            if content != displayContent {
                content = displayContent
            }
        }
    }

    // MARK: - Unified Section View (consistent styling for all section types)

    /// Shape for the node body — rounded on left, flat on right where it meets the lip
    private var nodeShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 8,
            bottomLeadingRadius: 8,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        )
    }

    /// Shape for the lip tab — flat on left, rounded on right
    private var lipShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 8,
            topTrailingRadius: 8
        )
    }

    private var foldView: some View {
        // Content area with trailing padding to reserve space for the lip
        contentArea
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .padding(.trailing, 20) // Reserve space for the lip
            .background(RoundedRectangle(cornerRadius: 8).fill(section.intent.backgroundTint))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // Overlay controls at corners - don't take up content width
            .overlay(alignment: .topTrailing) {
                if section.isLocked {
                    lockBadge
                        .padding(6)
                        .padding(.trailing, 20) // Offset for lip
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !section.isCollapsed, let handle = handle {
                    // Handle name (when linked to a loop)
                    Text(handle.formattedName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.1))
                        .clipShape(Capsule())
                        .contextMenu {
                            Button(role: .destructive) {
                                onUnlinkHandle()
                            } label: {
                                Label("Unlink from Loop", systemImage: "link.badge.minus")
                            }

                            Button {
                                #if os(iOS)
                                UIPasteboard.general.string = handle.formattedName
                                #endif
                            } label: {
                                Label("Copy Loop Name", systemImage: "doc.on.doc")
                            }
                        }
                        .padding(6)
                        .padding(.trailing, 20) // Offset for lip
                }
            }
            // Only add tap gesture for locked sections - don't interfere with text view gestures
            .overlay {
                if section.isLocked && !isAuthenticated {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleTap()
                        }
                }
            }
            // Lip overlay — fills exact node height, positioned at trailing edge
            .overlay(alignment: .trailing) {
                collapseLipButton
            }
            .overlay(focusBorder)
            .contextMenu { contextMenuItems }
            .animation(nil, value: content) // Prevent layout changes from affecting siblings
    }

    // MARK: - Audio Node View (fold-styled container for audio)

    #if os(iOS)
    @ViewBuilder
    private var audioNodeFoldView: some View {
        // Content format: "hash|duration" — extract hash and duration
        let parts = section.content.split(separator: "|", maxSplits: 1)
        let audioHash = parts.count > 0 ? String(parts[0]).trimmingCharacters(in: .whitespaces) : ""
        let audioDuration: TimeInterval = parts.count > 1 ? (Double(parts[1]) ?? 0) : 0

        Group {
            if audioHash.isEmpty {
                // Empty state — tap to record
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.15))
                    .frame(height: 48)
                    .overlay {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            Text("Tap to record")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onImageTap() }
            } else if let mediaRepo = mediaRepository {
                // Filled state — playback node
                AudioNodeView(
                    audioHash: audioHash,
                    duration: audioDuration,
                    mediaRepository: mediaRepo
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.15))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())  // Constrain interaction area to prevent touch bleed into adjacent views
        .overlay(focusBorder)
        .contextMenu { contextMenuItems }
    }
    #else
    private var audioNodeFoldView: some View {
        Text("Audio nodes are only supported on iOS")
            .foregroundStyle(.secondary)
    }
    #endif

    // MARK: - Image Node View (fold-styled container for images)

    #if os(iOS)
    @ViewBuilder
    private var imageNodeFoldView: some View {
        // Content format: "hash|assetId,hash|assetId,..." — extract just the hash part
        let hashes = section.content
            .split(separator: ",")
            .map { entry -> String in
                let parts = entry.split(separator: "|", maxSplits: 1)
                return String(parts[0]).trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }

        if let mediaRepo = mediaRepository {
            ImageNodeView(
                imageHashes: hashes,
                mediaRepository: mediaRepo,
                onTap: onImageTap,
                onDominantColorChanged: { color in
                    imageDominantColor = color
                },
                onCurrentImageChanged: { image in
                    imageNodeBackground = image
                }
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                // Blurred copy of the current photo fills the entire node container
                GeometryReader { geo in
                    if let bgImage = imageNodeBackground {
                        Image(uiImage: bgImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .blur(radius: 16)
                            .saturation(1.2)
                            .clipped()
                    } else {
                        (imageDominantColor ?? Color(.systemGray5))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())  // Constrain interaction area to prevent touch bleed into adjacent views
            .overlay(focusBorder)
            .contextMenu { contextMenuItems }
        }
    }

    #else
    private var imageNodeFoldView: some View {
        Text("Image nodes are only supported on iOS")
            .foregroundStyle(.secondary)
    }
    #endif

    // MARK: - Line View (plain text without node styling)

    private var lineView: some View {
        HStack(alignment: .top, spacing: 8) {
            // Use same contentArea as foldView for consistent template behavior
            // but without the collapse button, background, or border
            lineContentArea
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            contextMenuItems
        }
        .animation(nil, value: content) // Prevent layout changes from affecting siblings
    }

    @ViewBuilder
    private var lineContentArea: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Content editor (same as foldView's contentArea)
            contentEditor
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lineContentEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(iOS)
            if section.isTemplateContent,
               let templateText = section.templatePrefix,
               !templateText.isEmpty {
                // Use template-protected text view with bold template (same as contentEditor)
                TemplateProtectedTextView(
                    text: $content,
                    templatePrefix: templateText,
                    isFocused: $textFieldFocused,
                    richText: section.richContent,
                    onContentChange: onContentChange,
                    onIndent: onIndent,
                    onOutdent: onOutdent,
                    currentStatus: section.intent,
                    onStatusChange: onIntentChange
                )
                .frame(maxWidth: .infinity, minHeight: estimatedHeight, alignment: .topLeading)
            } else {
                // Regular text editor using UITextView for proper edit menu support
                EditableTextView(
                    text: $content,
                    isFocused: $textFieldFocused,
                    richText: section.richContent,
                    onContentChange: onContentChange,
                    onFocusChange: { focused in
                        if focused {
                            isEditing = true
                            onFocus()
                        }
                    },
                    onIndent: onIndent,
                    onOutdent: onOutdent,
                    currentStatus: section.intent,
                    onStatusChange: onIntentChange
                )
                .frame(maxWidth: .infinity, minHeight: estimatedHeight, alignment: .topLeading)
            }
            #else
            // macOS fallback
            TextEditor(text: $content)
                .font(.body)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($textFieldFocused)
                .frame(maxWidth: .infinity, minHeight: 32)
                .frame(maxWidth: .infinity, minHeight: estimatedHeight)
                .onChange(of: content) { _, newValue in
                    onContentChange(newValue)
                }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(nil, value: content)
    }

    // MARK: - Tap Handler
    
    private func handleTap() {
        if section.isLocked && !isAuthenticated {
            // Request authentication for locked section
            HapticFeedback.impact(.light)
            onUnlockRequest()
        } else if section.isCollapsed {
            // Collapsed sections are expanded via the expand button only
            // Do nothing here to avoid double-toggle with button
        } else {
            // Focus for editing (template content is editable after the prefix)
            print("👆 Section tapped, calling onFocus for: \(section.id.prefix(8))")
            textFieldFocused = true
            isEditing = true
            onFocus()  // Notify parent that this section gained focus
        }
    }
    
    // MARK: - Subviews
    
    /// A thick lip on the outside right edge — darker extension of the node
    private var collapseLipButton: some View {
        lipShape
            .fill(section.intent.backgroundTint)
            .frame(width: 20)
            .overlay {
                Image(systemName: section.isCollapsed ? "chevron.right" : "chevron.left")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(section.intent.color.opacity(0.6))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggleCollapse()
                }
                HapticFeedback.selection()
            }
    }

    private var optionsMenuButton: some View {
        Menu {
            // All node options available via tap
            contextMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                )
                .contentShape(Rectangle())
        }
    }

    private var lockBadge: some View {
        Button {
            if isAuthenticated {
                // Already authenticated, re-lock (keep isLocked=true, just remove from authenticated set)
                biometricManager.lockSection(section.id)
                HapticFeedback.notification(.success)
            } else {
                // Need authentication to view content
                onUnlockRequest()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isAuthenticated ? "lock.open.fill" : biometricManager.biometricIcon)
                    .font(.caption)
                if isProcessingLock {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .foregroundStyle(isAuthenticated ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isAuthenticated ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }
    
    @ViewBuilder
    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Show title if set
            if let title = section.title, !title.isEmpty, !section.isCollapsed {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                }
            }
            
            // Content or preview
            if section.isCollapsed {
                // Ghost Summary - one line preview in secondary gray
                ghostSummary
            } else {
                // Full content editor
                contentEditor
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shimmerLocked(
            isLocked: section.isLocked,
            isAuthenticated: isAuthenticated,
            tintColor: section.intent.color,
            onUnlock: onUnlockRequest
        )
    }
    
    private var ghostSummary: some View {
        HStack(spacing: 8) {
            // Preview text - content already contains template text
            let previewText = displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? ""
            let preview = previewText.count > 80 ? String(previewText.prefix(80)) + "..." : previewText

            if let templateText = section.templatePrefix, !templateText.isEmpty,
               let range = preview.range(of: templateText) {
                // Show with bold template portion
                let beforeTemplate = String(preview[..<range.lowerBound])
                let afterTemplate = String(preview[range.upperBound...])
                (Text(beforeTemplate) + Text(templateText).bold() + Text(afterTemplate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(preview.isEmpty ? "Empty section" : preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Child count indicator
            if hasChildren {
                Text("...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Handle name (when linked to a loop)
            if let handle = handle {
                Text(handle.formattedName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.purple)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// Calculate estimated height based on content
    private var estimatedHeight: CGFloat {
        let lineCount = max(1, content.components(separatedBy: "\n").count)
        // Estimate wrapped lines: assume ~40 chars per line on average
        let avgCharsPerLine: CGFloat = 40
        let totalChars = CGFloat(content.count)
        let estimatedWrappedLines = max(1, ceil(totalChars / avgCharsPerLine))
        let visualLines = max(CGFloat(lineCount), estimatedWrappedLines)
        let lineHeight: CGFloat = 22
        let padding: CGFloat = 20
        return visualLines * lineHeight + padding
    }

    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(iOS)
            if section.isTemplateContent,
               let templateText = section.templatePrefix,
               !templateText.isEmpty {
                // Use template-protected text view with bold template
                TemplateProtectedTextView(
                    text: $content,
                    templatePrefix: templateText,
                    isFocused: $textFieldFocused,
                    richText: section.richContent,
                    onContentChange: onContentChange,
                    onIndent: onIndent,
                    onOutdent: onOutdent,
                    currentStatus: section.intent,
                    onStatusChange: onIntentChange
                )
                .frame(maxWidth: .infinity, minHeight: estimatedHeight, alignment: .topLeading)
                // Don't add contentShape - let UITextView handle all gestures natively
            } else {
                // Regular text editor using UITextView for proper edit menu support
                EditableTextView(
                    text: $content,
                    isFocused: $textFieldFocused,
                    richText: section.richContent,
                    onContentChange: onContentChange,
                    onFocusChange: { focused in
                        if focused {
                            isEditing = true
                            onFocus()
                        }
                    },
                    onIndent: onIndent,
                    onOutdent: onOutdent,
                    currentStatus: section.intent,
                    onStatusChange: onIntentChange
                )
                .frame(maxWidth: .infinity, minHeight: estimatedHeight, alignment: .topLeading)
                // Don't add contentShape - let UITextView handle all gestures natively
            }
            #else
            // macOS fallback
            TextEditor(text: $content)
                .font(.body)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($textFieldFocused)
                .frame(maxWidth: .infinity, minHeight: estimatedHeight)
                .onChange(of: content) { _, newValue in
                    onContentChange(newValue)
                }
            #endif
        }
        .animation(nil, value: content) // Prevent layout animations affecting siblings
    }
    
    @ViewBuilder
    private var focusBorder: some View {
        if isFocused {
            // Node + lip together form a standard rounded rectangle
            RoundedRectangle(cornerRadius: 8)
                .stroke(section.intent.color.opacity(0.6), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
    }
    
    @ViewBuilder
    private var contextMenuItems: some View {
        // 1. Change Status
        Menu {
            ForEach(IntentType.allCases, id: \.self) { intent in
                Button {
                    onIntentChange(intent)
                    HapticFeedback.selection()
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
            Label("Change Status", systemImage: section.intent.icon)
        }

        // 2. Share
        Button {
            onShare()
            HapticFeedback.selection()
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        // 4. Lock with Face ID
        if section.isLocked {
            // If locked, show unlock or re-lock options
            Button {
                handleLockToggle()
            } label: {
                Label(
                    isAuthenticated ? "Re-lock" : "Unlock with \(biometricManager.biometricTypeName)",
                    systemImage: isAuthenticated ? "lock.fill" : biometricManager.biometricIcon
                )
            }

            // Remove Lock option (requires Face ID)
            Button(role: .destructive) {
                handleRemoveLock()
            } label: {
                Label("Remove Lock", systemImage: "lock.slash")
            }
        } else {
            // If not locked, show option to lock
            Button {
                handleLockToggle()
            } label: {
                Label(
                    "Lock with \(biometricManager.biometricTypeName)",
                    systemImage: "lock.fill"
                )
            }
        }

        // 5. Create Loop
        if handle != nil {
            Button(role: .destructive) {
                onUnlinkHandle()
                HapticFeedback.selection()
            } label: {
                Label("Unlink from Loop", systemImage: "link.badge.minus")
            }
        } else {
            Button {
                onCreateLoop()
                HapticFeedback.selection()
            } label: {
                Label("Create Loop", systemImage: "link.badge.plus")
            }
        }

        // 6. Duplicate (copy + paste in one action)
        Button {
            onCopy()
            onPaste()
            HapticFeedback.notification(.success)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        // 9. Delete
        Button(role: .destructive) {
            onDelete()
            HapticFeedback.notification(.warning)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    // MARK: - Lock Toggle Handler

    private func handleLockToggle() {
        if section.isLocked {
            if isAuthenticated {
                // Re-lock (remove from authenticated set and keep locked)
                biometricManager.lockSection(section.id)
                HapticFeedback.notification(.success)
            } else {
                // Need to authenticate first to unlock
                onUnlockRequest()
            }
        } else {
            // Lock the section
            onToggleLock()
            HapticFeedback.notification(.success)
        }
    }

    private func handleRemoveLock() {
        // Require Face ID authentication before removing lock
        Task {
            let success = await biometricManager.authenticate(for: section.id)
            if success {
                // Remove the lock entirely (toggle isLocked from true to false)
                onToggleLock()
                // Also remove from authenticated set since it's no longer locked
                biometricManager.revokeAuthentication(for: section.id)
                HapticFeedback.notification(.success)
            }
        }
    }
}

// MARK: - Conditional Context Menu

/// A modifier that only applies context menu when section is collapsed
/// This prevents the context menu's long-press gesture from interfering with UITextView
struct ConditionalContextMenu<MenuContent: View>: ViewModifier {
    let isCollapsed: Bool
    @ViewBuilder let content: () -> MenuContent

    func body(content view: Content) -> some View {
        if isCollapsed {
            view.contextMenu {
                content()
            }
        } else {
            view
        }
    }
}

// MARK: - Drag Feedback Overlay

/// Visual feedback overlay for drag-to-indent
struct DragIndentFeedback: View {
    let isIndenting: Bool  // true = indent, false = outdent
    let progress: CGFloat  // 0 to 1
    
    var body: some View {
        HStack {
            if !isIndenting {
                feedbackIcon(systemName: "arrow.left.to.line")
                Spacer()
            }
            
            if isIndenting {
                Spacer()
                feedbackIcon(systemName: "arrow.right.to.line")
            }
        }
        .opacity(Double(progress))
    }
    
    private func feedbackIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(isIndenting ? .green : .orange)
            .padding(12)
            .background(
                Circle()
                    .fill(isIndenting ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            )
            .scaleEffect(0.8 + (progress * 0.4))
    }
}

// MARK: - Single Line Text Field (for inline template editing)

#if os(iOS)
struct SingleLineTextField: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.returnKeyType = .done
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
        if isFocused.wrappedValue && !textField.isFirstResponder {
            textField.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SingleLineTextField

        init(_ parent: SingleLineTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused.wrappedValue = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
#endif

// MARK: - Self-Sizing Text View

#if os(iOS)
/// A UITextView subclass that properly calculates its intrinsic content size
/// and uses native UIKit text selection (like iMessage composer)
class SelfSizingTextView: UITextView {
    private var lastWidth: CGFloat = 0

    override var canBecomeFirstResponder: Bool { true }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureLikeMessages()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLikeMessages()
    }

    private func configureLikeMessages() {
        // Core text view settings
        isEditable = true
        isSelectable = true
        isScrollEnabled = false  // Let parent ScrollView handle scrolling

        // Completely disable the UIScrollView pan gesture so it can't
        // intercept touches meant for the parent ScrollView
        panGestureRecognizer.isEnabled = false

        // Disable all automatic text modifications
        smartInsertDeleteType = .no
        smartDashesType = .no
        smartQuotesType = .no
        autocorrectionType = .no

        // Spellcheck only underlines — no text changes
        spellCheckingType = .yes

        // Disable data detectors to prevent link detection interference
        dataDetectorTypes = []

        // IMPORTANT: Don't add custom long-press or double-tap recognizers.
        // UITextView already has the correct gestures for:
        // - single tap = position cursor
        // - double tap = select word + menu
        // - long press = selection handles
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Block any UIPanGestureRecognizer on this view when scrolling is disabled.
        // UITextView (a UIScrollView subclass) has internal pan gestures beyond just
        // panGestureRecognizer that can intercept vertical swipes meant for the
        // parent scroll view. Text selection uses separate gesture types (not pan).
        if !isScrollEnabled && gestureRecognizer is UIPanGestureRecognizer {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    override var intrinsicContentSize: CGSize {
        // Use a reasonable width if bounds isn't set yet
        let width = bounds.width > 0 ? bounds.width : 300
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(32, ceil(size.height)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Only invalidate if width actually changed to prevent layout loops
        if bounds.width > 0 && bounds.width != lastWidth {
            lastWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}
#endif

// MARK: - Keyboard Accessory Toolbar

#if os(iOS)
/// A toolbar that appears above the keyboard with formatting, indent, status, and dismiss buttons
class KeyboardAccessoryToolbar: UIToolbar {
    weak var textView: UITextView?
    var onDismiss: (() -> Void)?
    var onIndent: (() -> Void)?
    var onOutdent: (() -> Void)?
    var onStatusChange: ((IntentType) -> Void)?
    var currentStatus: IntentType = .idea

    private var statusButton: UIBarButtonItem?
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

    init(showIndentButtons: Bool = false, showStatusButton: Bool = false) {
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        setupToolbar(showIndentButtons: showIndentButtons, showStatusButton: showStatusButton)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupToolbar(showIndentButtons: false, showStatusButton: false)
    }

    private func setupToolbar(showIndentButtons: Bool, showStatusButton: Bool) {
        barStyle = .default
        isTranslucent = true
        sizeToFit()

        var items: [UIBarButtonItem] = []

        // Status button (color picker) - far left
        if showStatusButton {
            let button = createStatusButton()
            statusButton = button
            items.append(button)
            items.append(fixedSpace(8))
        }

        // Indent/Outdent buttons
        let outdentButton = UIBarButtonItem(
            image: UIImage(systemName: "decrease.indent"),
            style: .plain,
            target: self,
            action: #selector(outdentTapped)
        )
        items.append(outdentButton)

        let indentButton = UIBarButtonItem(
            image: UIImage(systemName: "increase.indent"),
            style: .plain,
            target: self,
            action: #selector(indentTapped)
        )
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

        items.append(fixedSpace(12))

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

    private func fixedSpace(_ width: CGFloat) -> UIBarButtonItem {
        let space = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        space.width = width
        return space
    }

    private func createStatusButton() -> UIBarButtonItem {
        let menu = UIMenu(title: "Status", children: [
            UIAction(title: "Blue", image: UIImage(systemName: "circle.fill")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)) { [weak self] _ in
                self?.onStatusChange?(.idea)
            },
            UIAction(title: "Yellow", image: UIImage(systemName: "circle.fill")?.withTintColor(.systemYellow, renderingMode: .alwaysOriginal)) { [weak self] _ in
                self?.onStatusChange?(.question)
            },
            UIAction(title: "Green", image: UIImage(systemName: "circle.fill")?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)) { [weak self] _ in
                self?.onStatusChange?(.task)
            },
            UIAction(title: "Purple", image: UIImage(systemName: "circle.fill")?.withTintColor(.systemPurple, renderingMode: .alwaysOriginal)) { [weak self] _ in
                self?.onStatusChange?(.evidence)
            }
        ])

        let button = UIBarButtonItem(
            image: UIImage(systemName: "circle.fill"),
            menu: menu
        )
        button.tintColor = currentStatus.uiColor
        return button
    }

    func updateStatusColor(_ status: IntentType) {
        currentStatus = status
        statusButton?.tintColor = status.uiColor
    }

    private func updateButtonAppearance() {
        // Highlight active formatting buttons with purple
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
        // Bold button only shows active if bold was set independently (not just from title)
        isBoldActive = traits.contains(.traitBold) && !isTitleActive
        isItalicActive = traits.contains(.traitItalic)
        isUnderlineActive = (attrs[.underlineStyle] as? Int) != nil && (attrs[.underlineStyle] as? Int) != 0

        updateButtonAppearance()
    }

    // MARK: - Formatting Actions
    // Rich text formatting is persisted via base64-encoded RTF in the richContent/bodyRichText fields.

    @objc private func titleTapped() {
        guard let textView = textView else { return }
        isTitleActive.toggle()
        let range = textView.selectedRange

        if range.length > 0 {
            // Apply to selected text
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
            // Toggle for future typing
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
            // Apply to selected text
            applyFontTraitToSelection(.traitBold, in: textView)
        } else {
            // Toggle for future typing
            isBoldActive.toggle()
            applyFontTraitToTyping(.traitBold, isActive: isBoldActive, in: textView)
        }
        updateButtonAppearance()
    }

    @objc private func italicTapped() {
        guard let textView = textView else { return }
        let range = textView.selectedRange

        if range.length > 0 {
            // Apply to selected text
            applyFontTraitToSelection(.traitItalic, in: textView)
        } else {
            // Toggle for future typing
            isItalicActive.toggle()
            applyFontTraitToTyping(.traitItalic, isActive: isItalicActive, in: textView)
        }
        updateButtonAppearance()
    }

    @objc private func underlineTapped() {
        guard let textView = textView else { return }
        let range = textView.selectedRange

        if range.length > 0 {
            // Apply to selected text
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
            // Toggle for future typing
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

            // Toggle the trait
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

    // MARK: - Other Actions

    @objc private func dismissTapped() {
        onDismiss?()
    }

    @objc private func indentTapped() {
        onIndent?()
    }

    @objc private func outdentTapped() {
        onOutdent?()
    }
}

// Helper extension to get UIColor from IntentType
extension IntentType {
    var uiColor: UIColor {
        switch self {
        case .idea:     return .systemBlue
        case .question: return .systemYellow
        case .task:     return .systemGreen
        case .evidence: return .systemPurple
        }
    }
}
#endif

// MARK: - Editable Text View (supports iOS edit menu)

#if os(iOS)
/// A UITextView wrapper that properly supports the iOS edit menu (copy/paste/select)
struct EditableTextView: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var richText: String?
    let onContentChange: (String, String?) -> Void
    let onFocusChange: (Bool) -> Void
    var onIndent: (() -> Void)?
    var onOutdent: (() -> Void)?
    var currentStatus: IntentType?
    var onStatusChange: ((IntentType) -> Void)?

    func makeUIView(context: Context) -> SelfSizingTextView {
        let textView = SelfSizingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0

        // Enable proper text wrapping
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.widthTracksTextView = true

        // Content hugging and compression
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        textView.font = bodyFont
        textView.textColor = UIColor.label

        // Load rich text if available, otherwise plain text
        if let richText = richText,
           let attrText = RichTextHelper.deserialize(richText) {
            textView.attributedText = attrText
        } else {
            textView.text = text
        }

        // Highlight any existing hashtags on load
        HashtagHelper.applyHighlighting(to: textView)

        // Add keyboard accessory toolbar with all buttons
        let toolbar = KeyboardAccessoryToolbar(
            showIndentButtons: onIndent != nil,
            showStatusButton: onStatusChange != nil
        )
        toolbar.textView = textView
        toolbar.onDismiss = { [weak textView] in
            textView?.resignFirstResponder()
        }
        toolbar.onIndent = onIndent
        toolbar.onOutdent = onOutdent
        toolbar.onStatusChange = onStatusChange
        if let status = currentStatus {
            toolbar.updateStatusColor(status)
        }
        textView.inputAccessoryView = toolbar

        return textView
    }

    func updateUIView(_ textView: SelfSizingTextView, context: Context) {
        // Never push text back into the text view while the user is actively editing —
        // this prevents cursor jumping and formatting being stripped.
        if !textView.isFirstResponder, textView.text != text {
            if let richText = richText,
               let attrText = RichTextHelper.deserialize(richText) {
                textView.attributedText = attrText
            } else {
                textView.text = text
            }
            textView.invalidateIntrinsicContentSize()
        }

        if isFocused.wrappedValue && !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditableTextView

        init(_ parent: EditableTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = true
            parent.onFocusChange(true)
            // Sync toolbar button states with current typing attributes
            if let toolbar = textView.inputAccessoryView as? KeyboardAccessoryToolbar {
                toolbar.syncWithTypingAttributes()
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = false
            parent.onFocusChange(false)
            // Save rich text formatting when focus leaves
            let richText = RichTextHelper.serialize(textView.attributedText)
            parent.onContentChange(textView.text ?? "", richText)
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

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Sync toolbar button states when cursor moves
            if let toolbar = textView.inputAccessoryView as? KeyboardAccessoryToolbar {
                toolbar.syncWithTypingAttributes()
            }
        }
    }
}
#endif

// MARK: - Template Protected Text View

#if os(iOS)
/// A UITextView that displays template text as bold and prevents editing within the template
struct TemplateProtectedTextView: UIViewRepresentable {
    @Binding var text: String
    let templatePrefix: String
    var isFocused: FocusState<Bool>.Binding
    var richText: String?
    let onContentChange: (String, String?) -> Void
    var onIndent: (() -> Void)?
    var onOutdent: (() -> Void)?
    var currentStatus: IntentType?
    var onStatusChange: ((IntentType) -> Void)?

    func makeUIView(context: Context) -> SelfSizingTextView {
        let textView = SelfSizingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0

        // Enable proper text wrapping
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.widthTracksTextView = true

        // Content hugging and compression
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Set typing attributes to regular font so new text isn't bold, with adaptive color
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        textView.typingAttributes = [.font: bodyFont, .foregroundColor: UIColor.label]

        // Add keyboard accessory toolbar with all buttons
        let toolbar = KeyboardAccessoryToolbar(
            showIndentButtons: onIndent != nil,
            showStatusButton: onStatusChange != nil
        )
        toolbar.textView = textView
        toolbar.onDismiss = { [weak textView] in
            textView?.resignFirstResponder()
        }
        toolbar.onIndent = onIndent
        toolbar.onOutdent = onOutdent
        toolbar.onStatusChange = onStatusChange
        if let status = currentStatus {
            toolbar.updateStatusColor(status)
        }
        textView.inputAccessoryView = toolbar

        let templateSegments = templatePrefix.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Load from saved RTF if available (preserves template bolding + user formatting)
        if let richText = richText,
           let attrText = RichTextHelper.deserialize(richText) {
            textView.attributedText = attrText
        } else {
            // No saved RTF — apply template formatting
            var initialText = text
            let allSegmentsPresent = templateSegments.allSatisfy { initialText.contains($0) }

            if !allSegmentsPresent {
                initialText = templatePrefix + initialText
                DispatchQueue.main.async {
                    self.text = initialText
                    self.onContentChange(initialText, nil)
                }
            }

            updateAttributedText(textView, with: initialText)
        }

        // Position cursor at end of first template segment (or at end if no segments)
        let currentText = textView.text ?? ""
        DispatchQueue.main.async {
            if let firstSegment = templateSegments.first,
               let range = currentText.range(of: firstSegment) {
                let nsRange = NSRange(range, in: currentText)
                let cursorPosition = nsRange.location + nsRange.length
                textView.selectedRange = NSRange(location: cursorPosition, length: 0)
            }
        }

        return textView
    }

    func updateUIView(_ textView: SelfSizingTextView, context: Context) {
        // Never push text back while the user is actively editing —
        // prevents cursor jumping and formatting being stripped.
        if !textView.isFirstResponder {
            let currentPlainText = textView.text ?? ""
            if currentPlainText != text {
                if let richText = richText,
                   let attrText = RichTextHelper.deserialize(richText) {
                    textView.attributedText = attrText
                } else {
                    updateAttributedText(textView, with: text)
                }
                textView.invalidateIntrinsicContentSize()
            }
        }

        // Handle focus
        if isFocused.wrappedValue && !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }
    }

    private func updateAttributedText(_ textView: UITextView, with text: String) {
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let boldFont = UIFont.boldSystemFont(ofSize: bodyFont.pointSize)
        let textColor = UIColor.label  // Adapts to light/dark mode

        // Start with all text as regular
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: [.font: bodyFont, .foregroundColor: textColor]
        )

        // Find and bold each template segment individually
        let templateSegments = templatePrefix.components(separatedBy: "\n").filter { !$0.isEmpty }

        for segment in templateSegments {
            // Find all occurrences of this segment and make them bold
            var searchRange = text.startIndex..<text.endIndex
            while let foundRange = text.range(of: segment, range: searchRange) {
                let nsRange = NSRange(foundRange, in: text)
                attributedString.addAttribute(.font, value: boldFont, range: nsRange)

                // Move search range forward
                searchRange = foundRange.upperBound..<text.endIndex
            }
        }

        textView.attributedText = attributedString
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TemplateProtectedTextView
        weak var textView: UITextView?

        init(_ parent: TemplateProtectedTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = true
            // Sync toolbar button states with current typing attributes
            if let toolbar = textView.inputAccessoryView as? KeyboardAccessoryToolbar {
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
            // Allow cursor to be positioned anywhere
            // Protection happens in shouldChangeTextIn when user tries to delete/modify
            // Sync toolbar button states when cursor moves
            if let toolbar = textView.inputAccessoryView as? KeyboardAccessoryToolbar {
                toolbar.syncWithTypingAttributes()
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let currentText = textView.text ?? ""
            let templatePrefix = parent.templatePrefix

            // Pure insertions (no deletion) are always allowed
            // This lets users add newlines and content anywhere
            if range.length == 0 {
                return true
            }

            // For deletions/replacements, check if any protected template segment is affected
            // Split template into individual segments (by newlines) to protect each separately
            let templateSegments = templatePrefix.components(separatedBy: "\n").filter { !$0.isEmpty }

            let editStart = range.location
            let editEnd = range.location + range.length

            // Check each template segment
            for segment in templateSegments {
                // Find all occurrences of this segment in current text
                var searchRange = currentText.startIndex..<currentText.endIndex
                while let foundRange = currentText.range(of: segment, range: searchRange) {
                    let nsFoundRange = NSRange(foundRange, in: currentText)
                    let segmentStart = nsFoundRange.location
                    let segmentEnd = nsFoundRange.location + nsFoundRange.length

                    // Check if the edit overlaps with this segment
                    let overlapsSegment = !(editEnd <= segmentStart || editStart >= segmentEnd)

                    if overlapsSegment {
                        // Edit would modify a protected template segment - reject it
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.warning)
                        return false
                    }

                    // Move search range forward
                    searchRange = foundRange.upperBound..<currentText.endIndex
                }
            }

            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            let richText = RichTextHelper.serialize(textView.attributedText)

            if parent.text != newText {
                parent.text = newText
            }
            parent.onContentChange(newText, richText)
            textView.invalidateIntrinsicContentSize()
        }
    }
}
#endif

// MARK: - Preview

#Preview("Section States") {
    ScrollView {
        VStack(spacing: 12) {
            // Idea section
            SectionView(
                section: Section(
                    noteId: "1",
                    content: "This is an idea - a creative thought or brainstorm",
                    orderKey: "A",
                    intent: .idea
                ),
                isFocused: false,
                onContentChange: { _, _ in },
                onReturn: {},
                onBackspaceEmpty: {},
                onIndent: {},
                onOutdent: {},
                onToggleCollapse: {}
            )
            
            // Question section (focused)
            SectionView(
                section: Section(
                    noteId: "1",
                    content: "What if we approached this differently?",
                    orderKey: "B",
                    intent: .question
                ),
                isFocused: true,
                onContentChange: { _, _ in },
                onReturn: {},
                onBackspaceEmpty: {},
                onIndent: {},
                onOutdent: {},
                onToggleCollapse: {}
            )
            
            // Task section (indented)
            SectionView(
                section: Section(
                    noteId: "1",
                    content: "Complete the implementation of the new feature",
                    orderKey: "C",
                    indentLevel: 1,
                    intent: .task
                ),
                isFocused: false,
                onContentChange: { _, _ in },
                onReturn: {},
                onBackspaceEmpty: {},
                onIndent: {},
                onOutdent: {},
                onToggleCollapse: {}
            )
            
            // Evidence section with title (indented twice)
            SectionView(
                section: Section(
                    noteId: "1",
                    content: "According to the research paper, this approach yields 40% better results.",
                    title: "Research Citation",
                    orderKey: "D",
                    indentLevel: 2,
                    intent: .evidence
                ),
                isFocused: false,
                onContentChange: { _, _ in },
                onReturn: {},
                onBackspaceEmpty: {},
                onIndent: {},
                onOutdent: {},
                onToggleCollapse: {}
            )
            
            // Collapsed section (Ghost Summary)
            SectionView(
                section: Section(
                    noteId: "1",
                    content: "This is a collapsed section with a lot of content that should be shown as a ghost summary preview",
                    orderKey: "E",
                    isCollapsed: true,
                    intent: .idea
                ),
                isFocused: false,
                hasChildren: true,
                onContentChange: { _, _ in },
                onReturn: {},
                onBackspaceEmpty: {},
                onIndent: {},
                onOutdent: {},
                onToggleCollapse: {}
            )
            
            // Locked section (unauthenticated)
            SectionView(
                section: Section(
                    noteId: "1",
                    content: "This is sensitive content that requires authentication",
                    orderKey: "F",
                    isLocked: true,
                    intent: .evidence
                ),
                isFocused: false,
                isAuthenticated: false,
                onContentChange: { _, _ in },
                onReturn: {},
                onBackspaceEmpty: {},
                onIndent: {},
                onOutdent: {},
                onToggleCollapse: {},
                onUnlockRequest: { print("Unlock requested") }
            )
            
            // Locked section (authenticated)
            SectionView(
                section: Section(
                    noteId: "1",
                    content: "This locked content is now visible after authentication",
                    orderKey: "G",
                    isLocked: true,
                    intent: .task
                ),
                isFocused: false,
                isAuthenticated: true,
                onContentChange: { _, _ in },
                onReturn: {},
                onBackspaceEmpty: {},
                onIndent: {},
                onOutdent: {},
                onToggleCollapse: {}
            )
        }
        .padding()
    }
}

#Preview("Drag Feedback") {
    VStack(spacing: 40) {
        DragIndentFeedback(isIndenting: true, progress: 0.5)
            .frame(height: 60)
            .background(Color.gray.opacity(0.1))
        
        DragIndentFeedback(isIndenting: false, progress: 0.8)
            .frame(height: 60)
            .background(Color.gray.opacity(0.1))
    }
    .padding()
}
