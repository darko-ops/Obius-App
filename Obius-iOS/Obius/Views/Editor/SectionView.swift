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

    /// Convert base64-encoded RTF back to markdown text.
    /// Reconstructs # headings, **bold**, and *italic* from font attributes.
    static func toMarkdown(_ base64String: String) -> String? {
        guard let attrText = deserialize(base64String) else { return nil }
        let baseSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        let fullRange = NSRange(location: 0, length: attrText.length)
        var result = ""
        let plainText = attrText.string

        // Process line by line to detect headings
        let lines = plainText.components(separatedBy: "\n")
        var charIndex = 0

        for (lineIdx, line) in lines.enumerated() {
            let lineRange = NSRange(location: charIndex, length: line.utf16.count)

            if line.isEmpty {
                result += "\n"
                charIndex += line.utf16.count + 1 // +1 for newline
                continue
            }

            // Check the font of the first character to detect heading level
            var isHeading = false
            if lineRange.length > 0 {
                let attrs = attrText.attributes(at: lineRange.location, effectiveRange: nil)
                if let font = attrs[.font] as? UIFont {
                    let ratio = font.pointSize / baseSize
                    if ratio > 1.5 {
                        result += "# "
                        isHeading = true
                    } else if ratio > 1.2 {
                        result += "## "
                        isHeading = true
                    } else if ratio > 1.05 {
                        result += "### "
                        isHeading = true
                    }
                }
            }

            if isHeading {
                // Headings: just append the line text (already has prefix)
                result += line
            } else {
                // Process inline formatting (bold/italic) within the line
                var pos = lineRange.location
                let lineEnd = lineRange.location + lineRange.length
                while pos < lineEnd {
                    var effectiveRange = NSRange()
                    let attrs = attrText.attributes(at: pos, effectiveRange: &effectiveRange)
                    // Clamp effective range to this line
                    let rangeEnd = min(effectiveRange.location + effectiveRange.length, lineEnd)
                    let runRange = NSRange(location: pos, length: rangeEnd - pos)
                    let runText = (plainText as NSString).substring(with: runRange)

                    if let font = attrs[.font] as? UIFont {
                        let isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
                        let isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
                        if isBold && isItalic {
                            result += "***\(runText)***"
                        } else if isBold {
                            result += "**\(runText)**"
                        } else if isItalic {
                            result += "*\(runText)*"
                        } else {
                            result += runText
                        }
                    } else {
                        result += runText
                    }
                    pos = rangeEnd
                }
            }

            charIndex += line.utf16.count + 1 // +1 for newline
            if lineIdx < lines.count - 1 {
                result += "\n"
            }
        }

        return result
    }

    /// Convert markdown-style text to NSAttributedString with rich formatting.
    /// Supports: # headings, ## subheadings, **bold**, *italic*
    static func fromMarkdown(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        let bodyFont = UIFont.systemFont(ofSize: baseSize)
        let bodyColor = UIColor.label

        let lines = text.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if index > 0 {
                // Explicit body font on newlines prevents RTF round-trip from
                // inheriting bold/heading attributes from adjacent runs.
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: bodyFont, .foregroundColor: bodyColor
                ]))
            }

            // Headings — scaled relative to dynamic body size
            if trimmed.hasPrefix("### ") {
                let content = String(trimmed.dropFirst(4))
                let font = UIFont.systemFont(ofSize: baseSize * 1.12, weight: .semibold)
                result.append(NSAttributedString(string: content, attributes: [
                    .font: font, .foregroundColor: bodyColor
                ]))
            } else if trimmed.hasPrefix("## ") {
                let content = String(trimmed.dropFirst(3))
                let font = UIFont.systemFont(ofSize: baseSize * 1.3, weight: .bold)
                result.append(NSAttributedString(string: content, attributes: [
                    .font: font, .foregroundColor: bodyColor
                ]))
            } else if trimmed.hasPrefix("# ") {
                let content = String(trimmed.dropFirst(2))
                let font = UIFont.systemFont(ofSize: baseSize * 1.65, weight: .bold)
                result.append(NSAttributedString(string: content, attributes: [
                    .font: font, .foregroundColor: bodyColor
                ]))
            } else {
                // Inline formatting: **bold** and *italic*
                result.append(parseInlineFormatting(trimmed, bodyFont: bodyFont, bodyColor: bodyColor))
            }
        }

        return result
    }

    /// Parse inline **bold** and *italic* markers within a line.
    private static func parseInlineFormatting(_ text: String, bodyFont: UIFont, bodyColor: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Bold: **text**
            if remaining.hasPrefix("**"),
               let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...].range(of: "**") {
                let boldStart = remaining.index(remaining.startIndex, offsetBy: 2)
                let boldText = String(remaining[boldStart..<endRange.lowerBound])
                let boldFont = UIFont.systemFont(ofSize: bodyFont.pointSize, weight: .bold)
                result.append(NSAttributedString(string: boldText, attributes: [
                    .font: boldFont, .foregroundColor: bodyColor
                ]))
                remaining = remaining[endRange.upperBound...]
            }
            // Italic: *text*
            else if remaining.hasPrefix("*"),
                    let endRange = remaining[remaining.index(after: remaining.startIndex)...].range(of: "*") {
                let italicStart = remaining.index(after: remaining.startIndex)
                let italicText = String(remaining[italicStart..<endRange.lowerBound])
                let italicFont = UIFont.italicSystemFont(ofSize: bodyFont.pointSize)
                result.append(NSAttributedString(string: italicText, attributes: [
                    .font: italicFont, .foregroundColor: bodyColor
                ]))
                remaining = remaining[endRange.upperBound...]
            }
            // Plain character
            else {
                let char = String(remaining[remaining.startIndex])
                result.append(NSAttributedString(string: char, attributes: [
                    .font: bodyFont, .foregroundColor: bodyColor
                ]))
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
            }
        }

        return result
    }
}
#elseif os(macOS)
/// macOS Rich Text Helper using NSFont
enum RichTextHelper {
    static func serialize(_ attributedText: NSAttributedString) -> String? {
        guard attributedText.length > 0 else { return nil }
        guard let data = try? attributedText.data(
            from: NSRange(location: 0, length: attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) else { return nil }
        return data.base64EncodedString()
    }

    static func deserialize(_ base64String: String) -> NSAttributedString? {
        guard let data = Data(base64Encoded: base64String) else { return nil }
        return try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }

    /// Convert base64-encoded RTF back to markdown text.
    static func toMarkdown(_ base64String: String) -> String? {
        guard let attrText = deserialize(base64String) else { return nil }
        let baseSize: CGFloat = 17
        let fullRange = NSRange(location: 0, length: attrText.length)
        var result = ""
        let plainText = attrText.string
        let lines = plainText.components(separatedBy: "\n")
        var charIndex = 0

        for (lineIdx, line) in lines.enumerated() {
            let lineRange = NSRange(location: charIndex, length: line.utf16.count)
            if line.isEmpty {
                result += "\n"
                charIndex += line.utf16.count + 1
                continue
            }
            var isHeading = false
            if lineRange.length > 0 {
                let attrs = attrText.attributes(at: lineRange.location, effectiveRange: nil)
                if let font = attrs[.font] as? NSFont {
                    let ratio = font.pointSize / baseSize
                    if ratio > 1.5 { result += "# "; isHeading = true }
                    else if ratio > 1.2 { result += "## "; isHeading = true }
                    else if ratio > 1.05 { result += "### "; isHeading = true }
                }
            }
            if isHeading {
                result += line
            } else {
                var pos = lineRange.location
                let lineEnd = lineRange.location + lineRange.length
                while pos < lineEnd {
                    var effectiveRange = NSRange()
                    let attrs = attrText.attributes(at: pos, effectiveRange: &effectiveRange)
                    let rangeEnd = min(effectiveRange.location + effectiveRange.length, lineEnd)
                    let runRange = NSRange(location: pos, length: rangeEnd - pos)
                    let runText = (plainText as NSString).substring(with: runRange)
                    if let font = attrs[.font] as? NSFont {
                        let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                        let isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                        if isBold && isItalic { result += "***\(runText)***" }
                        else if isBold { result += "**\(runText)**" }
                        else if isItalic { result += "*\(runText)*" }
                        else { result += runText }
                    } else {
                        result += runText
                    }
                    pos = rangeEnd
                }
            }
            charIndex += line.utf16.count + 1
            if lineIdx < lines.count - 1 { result += "\n" }
        }
        return result
    }

    static func fromMarkdown(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: 17)
        let bodyColor = NSColor.labelColor

        let lines = text.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if index > 0 {
                // Explicit body font on newlines prevents RTF round-trip from
                // inheriting bold/heading attributes from adjacent runs.
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: bodyFont, .foregroundColor: bodyColor
                ]))
            }

            if trimmed.hasPrefix("### ") {
                let content = String(trimmed.dropFirst(4))
                let font = NSFont.systemFont(ofSize: 19, weight: .semibold)
                result.append(NSAttributedString(string: content, attributes: [
                    .font: font, .foregroundColor: bodyColor
                ]))
            } else if trimmed.hasPrefix("## ") {
                let content = String(trimmed.dropFirst(3))
                let font = NSFont.systemFont(ofSize: 22, weight: .bold)
                result.append(NSAttributedString(string: content, attributes: [
                    .font: font, .foregroundColor: bodyColor
                ]))
            } else if trimmed.hasPrefix("# ") {
                let content = String(trimmed.dropFirst(2))
                let font = NSFont.systemFont(ofSize: 28, weight: .bold)
                result.append(NSAttributedString(string: content, attributes: [
                    .font: font, .foregroundColor: bodyColor
                ]))
            } else {
                result.append(parseInlineFormatting(trimmed, bodyFont: bodyFont, bodyColor: bodyColor))
            }
        }

        return result
    }

    private static func parseInlineFormatting(_ text: String, bodyFont: NSFont, bodyColor: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            if remaining.hasPrefix("**"),
               let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...].range(of: "**") {
                let boldStart = remaining.index(remaining.startIndex, offsetBy: 2)
                let boldText = String(remaining[boldStart..<endRange.lowerBound])
                let boldFont = NSFont.systemFont(ofSize: bodyFont.pointSize, weight: .bold)
                result.append(NSAttributedString(string: boldText, attributes: [
                    .font: boldFont, .foregroundColor: bodyColor
                ]))
                remaining = remaining[endRange.upperBound...]
            } else if remaining.hasPrefix("*"),
                      let endRange = remaining[remaining.index(after: remaining.startIndex)...].range(of: "*") {
                let italicStart = remaining.index(after: remaining.startIndex)
                let italicText = String(remaining[italicStart..<endRange.lowerBound])
                let italicFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
                result.append(NSAttributedString(string: italicText, attributes: [
                    .font: italicFont, .foregroundColor: bodyColor
                ]))
                remaining = remaining[endRange.upperBound...]
            } else {
                let char = String(remaining[remaining.startIndex])
                result.append(NSAttributedString(string: char, attributes: [
                    .font: bodyFont, .foregroundColor: bodyColor
                ]))
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
            }
        }

        return result
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

    // AI editing callback
    var onEditWithAI: (() -> Void)? = nil  // Open AI Workspace focused on this section

    // Image node callback
    let onImageTap: () -> Void  // Open image picker for this section
    let mediaRepository: MediaRepository?  // For loading image data

    // Sync conflict resolution
    let onResolveConflict: () -> Void

    @State private var content: String
    @State private var isEditing = false
    @State private var isProcessingLock = false
    @State private var imageDominantColor: Color?
    @State private var imageNodeBackground: PlatformImage?
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
        onEditWithAI: (() -> Void)? = nil,
        onImageTap: @escaping () -> Void = {},
        mediaRepository: MediaRepository? = nil,
        onResolveConflict: @escaping () -> Void = {}
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
        self.onEditWithAI = onEditWithAI
        self.onImageTap = onImageTap
        self.mediaRepository = mediaRepository
        self.onResolveConflict = onResolveConflict

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
            DispatchQueue.main.async {
                // Image/audio sections have no text field — skip focus handling
                guard section.contentType != .image && section.contentType != .audio else { return }

                if newValue && (!section.isLocked || isAuthenticated) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        textFieldFocused = true
                        isEditing = true
                    }
                } else if !newValue && section.isLocked {
                    biometricManager.lockSection(section.id)
                }
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
        .onChange(of: displayContent) { oldValue, newValue in
            // Always sync when content changed externally (e.g. AI workspace action).
            // Only skip if the user is actively typing AND the change is just
            // their own keystroke echoing back (old == what we had before).
            guard content != newValue else { return }
            if textFieldFocused && oldValue == content {
                // User is typing and this is their own edit propagating — skip to avoid cursor jump
                return
            }
            content = newValue
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
                if section.syncStatus == .conflict {
                    syncConflictBadge
                        .padding(6)
                        .padding(.trailing, 20)
                } else if section.isLocked {
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
                                ClipboardHelper.copy(handle.formattedName)
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

    // MARK: - Image Node View (fold-styled container for images)

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
                        platformImage(bgImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .blur(radius: 16)
                            .saturation(1.2)
                            .clipped()
                    } else {
                        (imageDominantColor ?? Color.systemGray5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())  // Constrain interaction area to prevent touch bleed into adjacent views
            .overlay(focusBorder)
            .contextMenu { contextMenuItems }
        }
    }

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
            // macOS: use NSTextView for rich text support
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
                onStatusChange: onIntentChange,
                sectionId: section.id
            )
            .frame(maxWidth: .infinity, minHeight: estimatedHeight, alignment: .topLeading)
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

    private var syncConflictBadge: some View {
        Button {
            // Resolve conflict by re-pushing local state
            onResolveConflict()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.caption)
                Text("Sync conflict")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
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
        // Use content as-is (including trailing newlines) so the minHeight
        // matches the text view's intrinsic size. Trimming trailing \n caused
        // a one-frame height mismatch → visible flicker when pressing Return
        // on the last line of the page.
        let lines = content.components(separatedBy: "\n")
        let lineCount = max(1, lines.count)
        #if os(macOS)
        let avgCharsPerLine: CGFloat = 80
        #else
        let avgCharsPerLine: CGFloat = 35
        #endif
        // Count wrapped lines per paragraph for a more accurate estimate
        var visualLines: CGFloat = 0
        for line in lines {
            let charCount = CGFloat(line.count)
            visualLines += max(1, ceil(charCount / avgCharsPerLine))
        }
        let lineHeight: CGFloat = 22
        let padding: CGFloat = 16
        let result = visualLines * lineHeight + padding
        return result
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
            // macOS: use NSTextView for rich text support
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
                onStatusChange: onIntentChange,
                sectionId: section.id
            )
            .frame(maxWidth: .infinity, minHeight: estimatedHeight, alignment: .topLeading)
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

        // 7. Edit with AI
        if let onEditWithAI {
            Button {
                onEditWithAI()
                HapticFeedback.selection()
            } label: {
                Label("Edit with AI", systemImage: "sparkles")
            }
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
#elseif os(macOS)
/// macOS single-line text field using SwiftUI TextField
struct SingleLineTextField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.body)
            .focused(isFocused)
            .onSubmit {
                isFocused.wrappedValue = false
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

    // Peer pan for driving the enclosing ScrollView's contentOffset while
    // focused. Attached directly to self. Disabled when not first-responder
    // so it never fires during normal scroll-to-here-to-focus flow. See
    // `handleScrollAssistPan(_:)` for details.
    private let scrollAssistDelegate = ScrollAssistAllowingDelegate()
    private var scrollAssistPan: VerticalOnlyPan?
    private var scrollAssistOffsetAtBegin: CGPoint = .zero

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

        // Peer scroll-assist pan, attached to self. Only runs while the text
        // view is first-responder — and only then on a clear vertical drag
        // (VerticalOnlyPan). `cancelsTouchesInView = true` means: when it
        // transitions from .possible → .began (after enough vertical motion),
        // UIKit cancels the in-flight touches on this text view, so
        // UITextView's own selection/loupe recognizers abort and our pan
        // alone drives scroll. Taps don't trigger the transition (no motion),
        // so native tap-to-position fires unperturbed.
        let pan = VerticalOnlyPan(
            target: self,
            action: #selector(handleScrollAssistPan(_:))
        )
        pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.maximumNumberOfTouches = 1
        pan.delegate = scrollAssistDelegate
        pan.isEnabled = false  // Only active while focused
        addGestureRecognizer(pan)
        scrollAssistPan = pan
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Always allow our own scroll-assist pan to begin. Without this
        // exception, the blanket pan-block below would refuse it along with
        // UITextView's own scroll pan.
        if gestureRecognizer === scrollAssistPan {
            return true
        }
        // Block any UIPanGestureRecognizer on this view when scrolling is
        // disabled. UITextView (a UIScrollView subclass) has internal pan
        // gestures beyond just `panGestureRecognizer` that can intercept
        // vertical swipes meant for the parent scroll view. Text selection
        // uses separate (non-pan) gesture types, so this doesn't affect
        // tap-to-position or text selection.
        if !isScrollEnabled && gestureRecognizer is UIPanGestureRecognizer {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { scrollAssistPan?.isEnabled = true }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { scrollAssistPan?.isEnabled = false }
        return result
    }

    @objc private func handleScrollAssistPan(_ recognizer: UIPanGestureRecognizer) {
        guard isFirstResponder,
              let scrollView = enclosingScrollView else { return }
        switch recognizer.state {
        case .began:
            scrollAssistOffsetAtBegin = scrollView.contentOffset
        case .changed:
            let translation = recognizer.translation(in: scrollView)
            let minY = -scrollView.adjustedContentInset.top
            let maxY = max(
                minY,
                scrollView.contentSize.height
                    - scrollView.bounds.height
                    + scrollView.adjustedContentInset.bottom
            )
            let proposedY = scrollAssistOffsetAtBegin.y - translation.y
            let clampedY = min(max(proposedY, minY), maxY)
            scrollView.contentOffset = CGPoint(
                x: scrollAssistOffsetAtBegin.x,
                y: clampedY
            )
        default:
            break
        }
    }

    private var enclosingScrollView: UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scroll = current as? UIScrollView, scroll !== self {
                return scroll
            }
            view = current.superview
        }
        return nil
    }

    override var intrinsicContentSize: CGSize {
        // Use a reasonable width if bounds isn't set yet
        let width = bounds.width > 0 ? bounds.width : 300
        // Use layoutManager's usedRect for accurate height — sizeThatFits can
        // underestimate when word-wrapping produces more visual lines than expected.
        let containerWidth = width - textContainerInset.left - textContainerInset.right
            - textContainer.lineFragmentPadding * 2
        textContainer.size = CGSize(width: containerWidth, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let textHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        let totalHeight = textHeight + textContainerInset.top + textContainerInset.bottom
        return CGSize(width: UIView.noIntrinsicMetric, height: max(32, ceil(totalHeight)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Only invalidate if width actually changed to prevent layout loops
        if bounds.width > 0 && bounds.width != lastWidth {
            lastWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }

    // MARK: - Paste Sanitization

    /// Override paste to strip foreign formatting from copied content (websites,
    /// other apps) so it matches the editor's style. Preserves bold, italic, and
    /// underline but normalizes font family, size, and color.
    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general

        // Try rich text sources — RTF first, then HTML
        if let sanitized = sanitizedAttributedString(from: pasteboard) {
            let location = selectedRange.location
            textStorage.replaceCharacters(in: selectedRange, with: sanitized)
            selectedRange = NSRange(location: location + sanitized.length, length: 0)
            delegate?.textViewDidChange?(self)
            return
        }

        // Plain text — insert with current typing attributes so it matches
        if let plain = pasteboard.string {
            let attrString = NSAttributedString(string: plain, attributes: typingAttributes)
            let location = selectedRange.location
            textStorage.replaceCharacters(in: selectedRange, with: attrString)
            selectedRange = NSRange(location: location + attrString.length, length: 0)
            delegate?.textViewDidChange?(self)
            return
        }

        super.paste(sender)
    }

    private func sanitizedAttributedString(from pasteboard: UIPasteboard) -> NSAttributedString? {
        // Try RTF
        if let data = pasteboard.data(forPasteboardType: "public.rtf"),
           let source = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return sanitize(source)
        }
        // Try HTML
        if let data = pasteboard.data(forPasteboardType: "public.html"),
           let source = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue
               ],
               documentAttributes: nil
           ) {
            return sanitize(source)
        }
        return nil
    }

    private func sanitize(_ source: NSAttributedString) -> NSAttributedString {
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let bodySize = bodyFont.pointSize
        let result = NSMutableAttributedString()

        source.enumerateAttributes(
            in: NSRange(location: 0, length: source.length),
            options: []
        ) { attrs, range, _ in
            let text = (source.string as NSString).substring(with: range)
            var newAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.label
            ]

            // Map bold/italic traits to the editor's font
            if let font = attrs[.font] as? UIFont {
                let traits = font.fontDescriptor.symbolicTraits
                let isBold = traits.contains(.traitBold)
                let isItalic = traits.contains(.traitItalic)

                if isBold && isItalic {
                    let desc = UIFont.systemFont(ofSize: bodySize, weight: .bold).fontDescriptor
                    if let combined = desc.withSymbolicTraits([.traitBold, .traitItalic]) {
                        newAttrs[.font] = UIFont(descriptor: combined, size: bodySize)
                    } else {
                        newAttrs[.font] = UIFont.systemFont(ofSize: bodySize, weight: .bold)
                    }
                } else if isBold {
                    newAttrs[.font] = UIFont.systemFont(ofSize: bodySize, weight: .bold)
                } else if isItalic {
                    newAttrs[.font] = UIFont.italicSystemFont(ofSize: bodySize)
                } else {
                    newAttrs[.font] = bodyFont
                }
            } else {
                newAttrs[.font] = bodyFont
            }

            // Preserve underline
            if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
                newAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            result.append(NSAttributedString(string: text, attributes: newAttrs))
        }

        return result
    }
}

// MARK: - Scroll-Assist Pan Delegate

/// Delegate for `SelfSizingTextView`'s peer scroll-assist pan. Votes `true`
/// for every arbitration question so the pan coexists with UITextView's
/// own recognizers (tap/caret placement, selection drag, loupe) and with
/// the enclosing scroll view's built-in pan. Apple's docs guarantee that
/// one side returning `true` is enough to allow simultaneous recognition,
/// so the internal UIKit delegates voting `false` (default) don't block us.
final class ScrollAssistAllowingDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}

// MARK: - Vertical-Only Pan

/// `UIPanGestureRecognizer` subclass that only enters `.began` on a clear
/// vertical drag. Horizontal swipes and small jitter cause immediate
/// `.failed` so taps, caret placement, and other touch pipelines aren't
/// perturbed by the recognizer's presence in arbitration.
///
/// Rationale: a vanilla pan will eventually fail on a pure tap (no
/// movement), but during the arbitration window UIKit may still wait on
/// it — which on UITextView has been observed to block tap-to-position.
/// This subclass fails fast on every touch that isn't a vertical drag, so
/// the pan is essentially invisible to taps and horizontal gestures.
final class VerticalOnlyPan: UIPanGestureRecognizer {
    private var startLocation: CGPoint?
    private static let activationDistance: CGFloat = 8

    override func reset() {
        super.reset()
        startLocation = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if let window = view?.window {
            startLocation = touches.first?.location(in: window)
        } else {
            startLocation = touches.first?.location(in: view)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        // Once we've entered .began, defer entirely to the default
        // UIPanGestureRecognizer behavior — it tracks translation correctly.
        if state != .possible {
            super.touchesMoved(touches, with: event)
            return
        }

        guard let touch = touches.first, let start = startLocation else {
            super.touchesMoved(touches, with: event)
            return
        }
        let current = (view?.window).map { touch.location(in: $0) } ?? touch.location(in: view)
        let dx = current.x - start.x
        let dy = current.y - start.y
        let absDx = abs(dx)
        let absDy = abs(dy)

        // Clearly horizontal → fail so this recognizer exits the arbitration
        // graph immediately and the next one (e.g. a horizontal swipe) can win.
        if absDx >= Self.activationDistance && absDx > absDy * 1.5 {
            state = .failed
            return
        }

        // Not yet enough vertical movement to count as a drag → stay
        // `.possible` without feeding super, so the recognizer doesn't
        // transition prematurely.
        if absDy < Self.activationDistance {
            return
        }

        // Clear vertical drag → let super begin tracking as usual.
        super.touchesMoved(touches, with: event)
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
        UIFont.preferredFont(forTextStyle: .body).pointSize * 1.65
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

    /// Sync button states with the attributes at the current selection or cursor
    func syncWithTypingAttributes() {
        guard let textView = textView else { return }
        let range = textView.selectedRange
        let attrs: [NSAttributedString.Key: Any]
        if range.location < textView.attributedText.length {
            attrs = textView.attributedText.attributes(at: range.location, effectiveRange: nil)
        } else {
            attrs = textView.typingAttributes
        }
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
            applyFontTraitToSelection(.traitBold, in: textView)
            syncWithTypingAttributes()
        } else {
            isBoldActive.toggle()
            applyFontTraitToTyping(.traitBold, isActive: isBoldActive, in: textView)
            updateButtonAppearance()
        }
    }

    @objc private func italicTapped() {
        guard let textView = textView else { return }
        let range = textView.selectedRange

        if range.length > 0 {
            applyFontTraitToSelection(.traitItalic, in: textView)
            syncWithTypingAttributes()
        } else {
            isItalicActive.toggle()
            applyFontTraitToTyping(.traitItalic, isActive: isItalicActive, in: textView)
            updateButtonAppearance()
        }
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
            syncWithTypingAttributes()
        } else {
            isUnderlineActive.toggle()
            var attrs = textView.typingAttributes
            if isUnderlineActive {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                attrs.removeValue(forKey: .underlineStyle)
            }
            textView.typingAttributes = attrs
            updateButtonAppearance()
        }
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

        // Deferred height recalculation — after SwiftUI assigns proper bounds,
        // recalculate intrinsic content size so multi-line content (e.g. from
        // AI workspace edits) displays at full height immediately.
        DispatchQueue.main.async {
            textView.invalidateIntrinsicContentSize()
        }

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
                // Reset typingAttributes to body defaults before setting .text —
                // otherwise stale Title/Bold from the keyboard toolbar would
                // repaint the whole section text.
                let bodyFont = UIFont.preferredFont(forTextStyle: .body)
                textView.typingAttributes = [
                    .font: bodyFont,
                    .foregroundColor: UIColor.label
                ]
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
            // Invalidate size FIRST so SwiftUI sees the correct height
            // before we update the binding and trigger a re-layout.
            textView.invalidateIntrinsicContentSize()
            let newText = textView.text ?? ""
            // Skip expensive RTF serialization during active typing — pass nil.
            // Rich text is saved on focus loss (textViewDidEndEditing).
            if parent.text != newText {
                parent.text = newText
            }
            parent.onContentChange(newText, nil)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Sync toolbar button states when cursor moves
            if let toolbar = textView.inputAccessoryView as? KeyboardAccessoryToolbar {
                toolbar.syncWithTypingAttributes()
            }
        }
    }
}
#elseif os(macOS)

// MARK: - Paste-Sanitizing NSTextView (macOS)

/// NSTextView subclass that strips foreign formatting on paste, keeping only
/// bold, italic, and underline while normalizing to the editor's font and color.
class PasteSanitizingTextView: NSTextView {

    /// Whether this text view is embedded inside a SwiftUI ScrollView.
    /// When true, scrollRangeToVisible is suppressed so the inner NSScrollView
    /// doesn't fight the outer SwiftUI ScrollView (which causes flicker).
    var suppressScrollToVisible = false

    override func scrollRangeToVisible(_ range: NSRange) {
        guard !suppressScrollToVisible else { return }
        super.scrollRangeToVisible(range)
    }

    /// Creates a scroll view hosting this subclass (replacement for
    /// `NSTextView.scrollableTextView()` which always creates a bare NSTextView).
    static func makeScrollable() -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)

        let textView = PasteSanitizingTextView(frame: .zero, textContainer: textContainer)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        return scrollView
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let bodyFont = NSFont.systemFont(ofSize: 17)
        let bodySize = bodyFont.pointSize

        // Try to read rich text from pasteboard (RTF or HTML)
        var source: NSAttributedString?
        if let rtfData = pasteboard.data(forType: .rtf) {
            source = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        } else if let htmlData = pasteboard.data(forType: .html) {
            source = try? NSAttributedString(
                data: htmlData,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
        }

        if let source = source {
            let sanitized = NSMutableAttributedString()
            source.enumerateAttributes(
                in: NSRange(location: 0, length: source.length),
                options: []
            ) { attrs, range, _ in
                let text = (source.string as NSString).substring(with: range)
                var newAttrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.labelColor
                ]

                if let font = attrs[.font] as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    let isBold = traits.contains(.boldFontMask)
                    let isItalic = traits.contains(.italicFontMask)

                    if isBold && isItalic {
                        var f = NSFont.systemFont(ofSize: bodySize, weight: .bold)
                        f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask)
                        newAttrs[.font] = f
                    } else if isBold {
                        newAttrs[.font] = NSFont.systemFont(ofSize: bodySize, weight: .bold)
                    } else if isItalic {
                        newAttrs[.font] = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
                    } else {
                        newAttrs[.font] = bodyFont
                    }
                } else {
                    newAttrs[.font] = bodyFont
                }

                if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
                    newAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }

                sanitized.append(NSAttributedString(string: text, attributes: newAttrs))
            }

            let insertionRange = selectedRange()
            if shouldChangeText(in: insertionRange, replacementString: sanitized.string) {
                textStorage?.replaceCharacters(in: insertionRange, with: sanitized)
                setSelectedRange(NSRange(location: insertionRange.location + sanitized.length, length: 0))
                didChangeText()
            }
            return
        }

        // Plain text — insert with current typing attributes
        if let plain = pasteboard.string(forType: .string) {
            let attrString = NSAttributedString(string: plain, attributes: typingAttributes)
            let insertionRange = selectedRange()
            if shouldChangeText(in: insertionRange, replacementString: plain) {
                textStorage?.replaceCharacters(in: insertionRange, with: attrString)
                setSelectedRange(NSRange(location: insertionRange.location + attrString.length, length: 0))
                didChangeText()
            }
            return
        }

        super.paste(sender)
    }
}

/// macOS editable text view using NSViewRepresentable wrapping NSTextView
struct EditableTextView: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var richText: String?
    let onContentChange: (String, String?) -> Void
    let onFocusChange: (Bool) -> Void
    var onIndent: (() -> Void)?
    var onOutdent: (() -> Void)?
    var currentStatus: IntentType?
    var onStatusChange: ((IntentType) -> Void)?
    /// Section ID this editor belongs to, or nil for the body editor.
    var sectionId: String? = nil
    /// Optional binding for dynamic height — when provided, the view reports its content height.
    var dynamicHeight: Binding<CGFloat>? = nil
    /// Insight radar highlight ranges — (NSRange, PlatformColor) pairs for inline highlighting.
    var insightHighlightRanges: [(NSRange, PlatformColor)] = []

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PasteSanitizingTextView.makeScrollable()
        let textView = scrollView.documentView as! PasteSanitizingTextView
        textView.delegate = context.coordinator
        textView.suppressScrollToVisible = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.font = NSFont.systemFont(ofSize: 17)
        textView.textColor = NSColor.labelColor

        // Disable scroll view scrolling — parent ScrollView handles it.
        // Pin content to top so the inner NSScrollView never auto-scrolls
        // to reveal the cursor (which fights the outer SwiftUI ScrollView
        // and causes a visible flicker when pressing Return at the bottom).
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.verticalScrollElasticity = .none

        // Load rich text if available, otherwise plain text
        // Suppress textDidChange during initial load and hashtag highlighting —
        // otherwise HashtagHelper's textStorage edits fire a non-suppressed
        // textDidChange that schedules a spurious writeback of the AI body.
        context.coordinator.isProgrammaticUpdate = true
        if let richText = richText,
           let attrText = RichTextHelper.deserialize(richText) {
            textView.textStorage?.setAttributedString(attrText)
        } else {
            textView.string = text
        }
        HashtagHelper.applyHighlighting(to: textView)
        context.coordinator.isProgrammaticUpdate = false
        context.coordinator.textView = textView
        // Report initial content height after layout
        DispatchQueue.main.async {
            context.coordinator.updateDynamicHeight()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let isFirstResponder = textView.window?.firstResponder == textView
        // Only update when not focused, OR when focused and the text has changed
        // significantly (e.g. external sync). Skip small diffs while focused to
        // avoid scroll freezes and visual glitches during normal typing.
        let textDiffers = textView.string != text
        let shouldUpdate = textDiffers && (!isFirstResponder || abs(textView.string.count - text.count) > 1)
        if shouldUpdate {
            // Suppress textDidChange callback during programmatic updates
            // to prevent observation → setText → textDidChange → DB write → observation loop.
            context.coordinator.isProgrammaticUpdate = true
            let selectedRanges = textView.selectedRanges
            // Always prefer the rich-text path when available — assigning
            // textView.string strips all attributes and inherits typingAttributes,
            // which can collapse a mixed-format document (headings/bold/body) into
            // whatever style the caret happens to sit in.
            if let richText = richText,
               let attrText = RichTextHelper.deserialize(richText) {
                textView.textStorage?.setAttributedString(attrText)
            } else {
                // Reset typingAttributes to body defaults BEFORE setting .string —
                // otherwise NSTextView paints the whole text with whatever style
                // was last armed (e.g. a 28pt Title toggle still live from the
                // formatting bar), making the body appear as "all big text".
                let bodyFont = NSFont.systemFont(ofSize: 17)
                textView.typingAttributes = [
                    .font: bodyFont,
                    .foregroundColor: NSColor.labelColor
                ]
                textView.string = text
            }
            if isFirstResponder {
                // Restore selection, clamping to new text length
                let maxLen = textView.string.count
                let restored = selectedRanges.compactMap { rangeValue -> NSValue? in
                    let r = rangeValue.rangeValue
                    let loc = min(r.location, maxLen)
                    let len = min(r.length, maxLen - loc)
                    return NSValue(range: NSRange(location: loc, length: len))
                }
                if !restored.isEmpty {
                    textView.setSelectedRanges(restored, affinity: .downstream, stillSelecting: false)
                }
            }
            // Apply hashtag highlighting before releasing the programmatic guard —
            // otherwise HashtagHelper's textStorage edits fire a non-suppressed
            // textDidChange, scheduling a debounced writeback that round-trips the
            // body through the DB and cascades onContentChange firings.
            HashtagHelper.applyHighlighting(to: textView)
            context.coordinator.isProgrammaticUpdate = false
            // Recalculate height after external text change
            DispatchQueue.main.async {
                context.coordinator.updateDynamicHeight()
            }
        }

        // Apply insight radar highlights — subtle background tint
        if let textStorage = textView.textStorage {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.beginEditing()
            // Clear previous insight highlights
            textStorage.enumerateAttribute(.insightHighlight, in: fullRange, options: []) { value, range, _ in
                guard value != nil else { return }
                textStorage.removeAttribute(.backgroundColor, range: range)
                textStorage.removeAttribute(.insightHighlight, range: range)
            }
            // Apply subtle background tint
            for (range, color) in insightHighlightRanges {
                guard range.location + range.length <= textStorage.length else { continue }
                textStorage.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.06), range: range)
                textStorage.addAttribute(.insightHighlight, value: true, range: range)
            }
            textStorage.endEditing()
        }

        if isFocused.wrappedValue && textView.window?.firstResponder != textView {
            let coordinator = context.coordinator
            Coordinator.activeCoordinator = coordinator
            DispatchQueue.main.async {
                // Defer @Published mutations out of the view update cycle,
                // and guard with equality so idempotent writes don't republish.
                let state = MacFormattingState.shared
                state.activeTextView = textView
                if !state.hasActiveEditor {
                    state.hasActiveEditor = true
                }
                if state.activeSectionId != self.sectionId {
                    state.activeSectionId = self.sectionId
                }
                textView.window?.makeFirstResponder(textView)
                coordinator.syncFormattingState()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditableTextView
        weak var textView: NSTextView?
        /// Saved selection range — preserved when the text view loses focus
        /// so formatting buttons can still apply to the original selection.
        var savedSelectedRange: NSRange = NSRange(location: 0, length: 0)
        /// Debounce timer for expensive per-keystroke work (rich text
        /// serialization, hashtag highlighting, database persistence).
        private var contentDebounceTimer: Timer?
        /// True when updateNSView is setting text programmatically — suppresses
        /// textDidChange to prevent observation → write → observation loops.
        var isProgrammaticUpdate = false

        /// Tracks the most recently focused text view coordinator so formatting
        /// buttons can call applyBold/Italic/etc directly on the active editor.
        static weak var activeCoordinator: Coordinator?

        init(_ parent: EditableTextView) {
            self.parent = parent
            super.init()
        }

        deinit {
            contentDebounceTimer?.invalidate()
            if Coordinator.activeCoordinator === self {
                Coordinator.activeCoordinator = nil
            }
        }

        // MARK: - Persistence

        private func notifyChange() {
            guard let textView = textView else { return }
            let richText = RichTextHelper.serialize(textView.attributedString())
            parent.onContentChange(textView.string, richText)
        }

        /// Flush any pending debounced content change immediately.
        /// Called on focus loss so edits are never silently dropped.
        func flushPendingContentChange() {
            guard contentDebounceTimer != nil else { return }
            contentDebounceTimer?.invalidate()
            contentDebounceTimer = nil
            guard let textView = textView else { return }
            HashtagHelper.applyHighlighting(to: textView)
            notifyChange()
        }

        // MARK: - NSTextViewDelegate

        func textDidBeginEditing(_ notification: Notification) {
            Coordinator.activeCoordinator = self
            parent.isFocused.wrappedValue = true
            parent.onFocusChange(true)
            // Set activeTextView synchronously so it is available
            // immediately if a formatting button fires right after focus.
            let state = MacFormattingState.shared
            state.activeTextView = self.textView
            // @Published writes publish on every set, even when the value is unchanged,
            // which re-renders any view observing MacFormattingState and can loop
            // during AppKit layout passes. Guard with equality.
            if state.activeSectionId != self.parent.sectionId {
                state.activeSectionId = self.parent.sectionId
            }
            DispatchQueue.main.async {
                if !state.hasActiveEditor {
                    state.hasActiveEditor = true
                }
                self.syncFormattingState()
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            flushPendingContentChange()
            parent.isFocused.wrappedValue = false
            parent.onFocusChange(false)
            if Coordinator.activeCoordinator === self {
                DispatchQueue.main.async {
                    let state = MacFormattingState.shared
                    if state.hasActiveEditor {
                        state.hasActiveEditor = false
                    }
                    if state.activeSectionId != nil {
                        state.activeSectionId = nil
                    }
                }
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView else { return }
            let range = textView.selectedRange()
            savedSelectedRange = range
            // Update savedSelectedRange synchronously so it is always
            // current when a formatting button reads it.
            let state = MacFormattingState.shared
            state.savedSelectedRange = range
            state.activeTextView = textView
            // Only publish @Published mutations when the value actually changes.
            // Programmatic text loads fire repeated selection changes during AppKit
            // layout, and each unconditional publish re-renders observing views —
            // previously cascading into a "Publishing changes from within view
            // updates" storm that froze the editor.
            if state.activeSectionId != self.parent.sectionId {
                state.activeSectionId = self.parent.sectionId
            }
            // Defer only @Published mutations to avoid re-rendering during view updates
            DispatchQueue.main.async {
                self.syncFormattingState()
            }
        }

        func syncFormattingState() {
            guard let textView = textView else { return }
            // Read formatting state from the text view
            let bodySize = NSFont.systemFont(ofSize: 17).pointSize
            let attrs: [NSAttributedString.Key: Any]
            let range = textView.selectedRange()
            // With a selection: read storage attrs. With a collapsed cursor:
            // prefer typingAttributes so the toolbar reflects the armed style.
            if range.length > 0, range.location < (textView.textStorage?.length ?? 0) {
                attrs = textView.textStorage?.attributes(at: range.location, effectiveRange: nil) ?? textView.typingAttributes
            } else {
                attrs = textView.typingAttributes
            }
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: bodySize)
            let traits = NSFontManager.shared.traits(of: font)
            let state = MacFormattingState.shared
            let isBold = traits.contains(.boldFontMask)
            let isItalic = traits.contains(.italicFontMask)
            let isUnderline = (attrs[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
            let isTitle = font.pointSize > bodySize + 2
            // Only publish when values actually change — otherwise every selection
            // change re-renders every view observing MacFormattingState.
            if state.isBold != isBold { state.isBold = isBold }
            if state.isItalic != isItalic { state.isItalic = isItalic }
            if state.isUnderline != isUnderline { state.isUnderline = isUnderline }
            if state.isTitle != isTitle { state.isTitle = isTitle }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            // Skip when updateNSView is setting text programmatically
            guard !isProgrammaticUpdate else { return }
            // Update the binding immediately so SwiftUI stays in sync
            let newText = textView.string
            if parent.text != newText {
                parent.text = newText
            }
            updateDynamicHeight()

            // Debounce expensive work: rich text serialization, hashtag
            // highlighting, and the persistence callback
            contentDebounceTimer?.invalidate()
            contentDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                guard let self, let textView = self.textView else { return }
                HashtagHelper.applyHighlighting(to: textView)
                self.notifyChange()
            }
        }

        func updateDynamicHeight() {
            guard let textView = textView,
                  let container = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }
            layoutManager.ensureLayout(for: container)
            let usedRect = layoutManager.usedRect(for: container)
            let inset = textView.textContainerInset
            let newHeight = ceil(usedRect.height + inset.height * 2)
            let finalHeight = max(newHeight, 22)
            // Set height synchronously so it updates in the same render pass
            // as the text binding — async dispatch caused a one-frame desync
            // where the text grew but the frame height lagged, producing a flicker.
            parent.dynamicHeight?.wrappedValue = finalHeight
        }
    }
}

#endif

// MARK: - Formatting Notification Names (macOS)

#if os(macOS)
/// Tracks the active formatting state at the cursor so the inline bar can show indicators.
/// Also provides formatting methods that operate directly on the active NSTextView.
final class MacFormattingState: ObservableObject {
    static let shared = MacFormattingState()
    @Published var isBold = false
    @Published var isItalic = false
    @Published var isUnderline = false
    @Published var isTitle = false
    /// True when any NSTextView (section or body) is the active editor.
    @Published var hasActiveEditor = false
    /// The section ID of the currently focused section editor, or nil if body/title is focused.
    @Published var activeSectionId: String? = nil
    /// Direct reference to the active text view for formatting commands.
    weak var activeTextView: NSTextView?
    /// Saved selection range — preserved so formatting works even if button click collapses selection.
    var savedSelectedRange: NSRange = NSRange(location: 0, length: 0)

    /// Save the selection range (called from textViewDidChangeSelection).
    func saveSelection(_ range: NSRange) {
        savedSelectedRange = range
    }

    private var effectiveRange: NSRange {
        guard let tv = activeTextView else { return NSRange(location: 0, length: 0) }
        let live = tv.selectedRange()
        let textLength = tv.textStorage?.length ?? 0
        // Validate the live range is within bounds
        if live.location + live.length <= textLength {
            return live
        }
        // Fall back to saved range if it's valid
        if savedSelectedRange.location + savedSelectedRange.length <= textLength {
            return savedSelectedRange
        }
        // Last resort: cursor at end of text
        return NSRange(location: textLength, length: 0)
    }

    /// If the cursor is collapsed, expand to the word containing it.
    /// This lets a user click inside a word and toggle bold/italic without
    /// having to manually select — matches WYSIWYG editor expectations.
    private func rangeOrCurrentWord(_ range: NSRange, in storage: NSTextStorage) -> NSRange {
        guard range.length == 0 else { return range }
        let text = storage.string as NSString
        let length = text.length
        guard length > 0 else { return range }
        var start = min(range.location, length)
        var end = start
        let wordChars = CharacterSet.whitespacesAndNewlines.inverted
        while start > 0, let scalar = Unicode.Scalar(text.character(at: start - 1)),
              wordChars.contains(scalar) {
            start -= 1
        }
        while end < length, let scalar = Unicode.Scalar(text.character(at: end)),
              wordChars.contains(scalar) {
            end += 1
        }
        if end > start {
            return NSRange(location: start, length: end - start)
        }
        return range
    }

    /// Expand a collapsed cursor to the paragraph (line) containing it.
    /// Title/heading is a paragraph-level style, so this matches Word/Pages.
    private func rangeOrCurrentParagraph(_ range: NSRange, in storage: NSTextStorage) -> NSRange {
        guard range.length == 0 else { return range }
        let text = storage.string as NSString
        let length = text.length
        guard length > 0 else { return range }
        let loc = min(range.location, length)
        let paragraphRange = text.paragraphRange(for: NSRange(location: loc, length: 0))
        // Trim a trailing newline so the newline's font doesn't get promoted,
        // which would bleed heading size into the next paragraph's empty line.
        var trimmed = paragraphRange
        while trimmed.length > 0,
              let scalar = Unicode.Scalar(text.character(at: trimmed.location + trimmed.length - 1)),
              CharacterSet.newlines.contains(scalar) {
            trimmed.length -= 1
        }
        return trimmed.length > 0 ? trimmed : paragraphRange
    }

    // MARK: - Formatting Commands

    func applyBold() { toggleFontTrait(.boldFontMask) }
    func applyItalic() { toggleFontTrait(.italicFontMask) }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        // With a selection: toggle the trait on the selected range.
        // With a collapsed cursor: only flip typingAttributes so the NEXT typed
        // character carries the style — don't auto-expand into the word.
        let range = effectiveRange
        let textLength = storage.length

        if range.length > 0 && range.location + range.length <= textLength {
            var allHaveTrait = true
            storage.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
                guard let font = value as? NSFont else { allHaveTrait = false; return }
                if !NSFontManager.shared.traits(of: font).contains(trait) { allHaveTrait = false }
            }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                guard let font = value as? NSFont else { return }
                let newFont = allHaveTrait
                    ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                    : NSFontManager.shared.convert(font, toHaveTrait: trait)
                storage.addAttribute(.font, value: newFont, range: subRange)
            }
            storage.endEditing()
        }

        var attrs = tv.typingAttributes
        let currentFont = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 17)
        let hasTrait = NSFontManager.shared.traits(of: currentFont).contains(trait)
        attrs[.font] = hasTrait
            ? NSFontManager.shared.convert(currentFont, toNotHaveTrait: trait)
            : NSFontManager.shared.convert(currentFont, toHaveTrait: trait)
        tv.typingAttributes = attrs

        finishFormatting(tv, range)
    }

    func applyUnderline() {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        // Cursor-only: flip typingAttributes for the next-typed char.
        let range = effectiveRange
        let textLength = storage.length

        if range.length > 0 && range.location + range.length <= textLength {
            var allUnderlined = true
            storage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
                if (value as? Int) != NSUnderlineStyle.single.rawValue { allUnderlined = false }
            }
            storage.beginEditing()
            if allUnderlined {
                storage.removeAttribute(.underlineStyle, range: range)
            } else {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            storage.endEditing()
        }

        var attrs = tv.typingAttributes
        let isUnderlined = (attrs[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
        attrs[.underlineStyle] = isUnderlined ? 0 : NSUnderlineStyle.single.rawValue
        tv.typingAttributes = attrs

        finishFormatting(tv, range)
    }

    func applyTitle() {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        let bodySize = NSFont.systemFont(ofSize: 17).pointSize
        let titleSize = bodySize * 1.65
        let range = effectiveRange
        let textLength = storage.length

        if range.length > 0 && range.location + range.length <= textLength {
            var allTitle = true
            storage.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
                guard let font = value as? NSFont else { allTitle = false; return }
                if font.pointSize < bodySize + 2 { allTitle = false }
            }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let existing = (value as? NSFont) ?? NSFont.systemFont(ofSize: bodySize)
                let traits = NSFontManager.shared.traits(of: existing)
                let targetSize = allTitle ? bodySize : titleSize
                // Promote path seeds with bold (heading convention); demote
                // path keeps whatever traits the run already had. Either way
                // we re-apply italic at the end so it survives both paths.
                var base = allTitle
                    ? NSFont.systemFont(ofSize: targetSize)
                    : NSFont.systemFont(ofSize: targetSize, weight: .bold)
                if traits.contains(.boldFontMask) { base = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) }
                if traits.contains(.italicFontMask) { base = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask) }
                storage.addAttribute(.font, value: base, range: subRange)
            }
            storage.endEditing()
        }

        var attrs = tv.typingAttributes
        let currentFont = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: bodySize)
        let isTitle = currentFont.pointSize > bodySize + 2
        let traits = NSFontManager.shared.traits(of: currentFont)
        let targetSize = isTitle ? bodySize : titleSize
        var base = isTitle
            ? NSFont.systemFont(ofSize: targetSize)
            : NSFont.systemFont(ofSize: targetSize, weight: .bold)
        if traits.contains(.boldFontMask) { base = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) }
        if traits.contains(.italicFontMask) { base = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask) }
        attrs[.font] = base
        tv.typingAttributes = attrs

        finishFormatting(tv, range)
    }

    private func finishFormatting(_ tv: NSTextView, _ range: NSRange) {
        tv.window?.makeFirstResponder(tv)
        // Snapshot typingAttributes BEFORE setSelectedRange — AppKit rewrites
        // typingAttributes to match the cursor's surrounding run on selection
        // change, which would wipe the style we just armed for the next char.
        let pendingTypingAttrs = tv.typingAttributes
        let textLength = tv.textStorage?.length ?? 0
        if range.location + range.length <= textLength {
            tv.setSelectedRange(range)
        }
        // Re-arm typingAttributes so the next-typed char inherits the toggled
        // style even when the cursor is collapsed (no selection was edited).
        tv.typingAttributes = pendingTypingAttrs
        syncState(from: tv)
        if let delegate = tv.delegate as? EditableTextView.Coordinator {
            let richText = RichTextHelper.serialize(tv.attributedString())
            delegate.parent.onContentChange(tv.string, richText)
        }
    }

    /// Read attributes from the text view and update published properties.
    func syncState(from tv: NSTextView) {
        let bodySize = NSFont.systemFont(ofSize: 17).pointSize
        let attrs: [NSAttributedString.Key: Any]
        let range = tv.selectedRange()
        // With a selection: read the first character's attributes (what the
        // user is looking at). With a collapsed cursor: prefer typingAttributes
        // so the toolbar reflects the "armed" style that the next-typed char
        // will carry — otherwise pressing Bold at a body cursor leaves the
        // button dark even though bold is now armed.
        if range.length > 0, range.location < (tv.textStorage?.length ?? 0) {
            attrs = tv.textStorage?.attributes(at: range.location, effectiveRange: nil) ?? tv.typingAttributes
        } else {
            attrs = tv.typingAttributes
        }
        let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: bodySize)
        let traits = NSFontManager.shared.traits(of: font)
        isBold = traits.contains(.boldFontMask)
        isItalic = traits.contains(.italicFontMask)
        isUnderline = (attrs[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
        isTitle = font.pointSize > bodySize + 2
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
            // Recalculate height after layout so multi-line content displays fully
            textView.invalidateIntrinsicContentSize()
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
            // Invalidate size FIRST so SwiftUI sees the correct height
            // before we update the binding and trigger a re-layout.
            textView.invalidateIntrinsicContentSize()
            let newText = textView.text ?? ""
            // Skip expensive RTF serialization during active typing — pass nil.
            // Rich text is saved on focus loss (textViewDidEndEditing).
            if parent.text != newText {
                parent.text = newText
            }
            parent.onContentChange(newText, nil)
        }
    }
}
#elseif os(macOS)
/// macOS template protected text view — uses basic TextEditor with template prefix enforcement
struct TemplateProtectedTextView: View {
    @Binding var text: String
    let templatePrefix: String
    var isFocused: FocusState<Bool>.Binding
    var richText: String?
    let onContentChange: (String, String?) -> Void
    var onIndent: (() -> Void)?
    var onOutdent: (() -> Void)?
    var currentStatus: IntentType?
    var onStatusChange: ((IntentType) -> Void)?

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .focused(isFocused)
            .onAppear {
                // Ensure template prefix is present
                let templateSegments = templatePrefix.components(separatedBy: "\n").filter { !$0.isEmpty }
                let allPresent = templateSegments.allSatisfy { text.contains($0) }
                if !allPresent {
                    text = templatePrefix + text
                    onContentChange(text, nil)
                }
            }
            .onChange(of: text) { _, newValue in
                DispatchQueue.main.async { onContentChange(newValue, nil) }
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
