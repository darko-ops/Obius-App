import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
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

    let onContentChange: (String) -> Void
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

    @State private var content: String
    @State private var isEditing = false
    @State private var isProcessingLock = false
    @FocusState private var textFieldFocused: Bool

    @StateObject private var biometricManager = BiometricManager.shared
    
    init(
        section: Section,
        isFocused: Bool,
        isAuthenticated: Bool = false,
        hasChildren: Bool = false,
        handle: Handle? = nil,
        displayContent: String? = nil,
        onContentChange: @escaping (String) -> Void,
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
        onUnlinkHandle: @escaping () -> Void = {}
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
        _content = State(initialValue: displayContent ?? handle?.content ?? section.content)
    }
    
    var body: some View {
        Group {
            if section.sectionType == .line {
                // Line item - simple text without fold styling
                lineView
            } else {
                // Fold - full styling with background
                foldView
            }
        }
        .padding(.leading, CGFloat(section.indentLevel) * 24)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .onChange(of: isFocused) { _, newValue in
            if newValue && (!section.isLocked || isAuthenticated) {
                textFieldFocused = true
                isEditing = true
            }
        }
        .onChange(of: displayContent) { _, newValue in
            if content != newValue {
                content = newValue
            }
        }
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - Line View (simple text without fold styling)

    private var lineView: some View {
        HStack(alignment: .top, spacing: 8) {
            contentArea
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Fold View (full styling with background)

    private var foldView: some View {
        HStack(alignment: .top, spacing: 8) {
            // Collapse indicator (only for sections with children)
            collapseButton
                .opacity(hasChildren ? 1 : 0.3)

            // Content area with shimmer lock support
            contentArea

            // Badges
            VStack(alignment: .trailing, spacing: 4) {
                // Handle badge (when linked to a handle)
                if let handle = handle {
                    HandleBadge(
                        handle: handle,
                        showUnlinkAction: true,
                        onUnlink: onUnlinkHandle
                    )
                }

                // Lock badge (when locked)
                if section.isLocked {
                    lockBadge
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(focusBorder)
    }
    
    // MARK: - Tap Handler
    
    private func handleTap() {
        if section.isLocked && !isAuthenticated {
            // Request authentication for locked section
            HapticFeedback.impact(.light)
            onUnlockRequest()
        } else if section.isCollapsed {
            // Expand collapsed section
            withAnimation(.easeInOut(duration: 0.2)) {
                onToggleCollapse()
            }
            HapticFeedback.selection()
        } else {
            // Focus for editing
            print("👆 Section tapped, calling onFocus for: \(section.id.prefix(8))")
            textFieldFocused = true
            isEditing = true
            onFocus()  // Notify parent that this section gained focus
        }
    }
    
    // MARK: - Subviews
    
    private var collapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                onToggleCollapse()
            }
            HapticFeedback.selection()
        } label: {
            Image(systemName: section.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var lockBadge: some View {
        Button {
            if isAuthenticated {
                // Already authenticated, offer to re-lock
                onToggleLock()
            } else {
                // Need authentication
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
        VStack(alignment: .leading, spacing: 4) {
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
            onUnlock: onUnlockRequest
        )
    }
    
    private var ghostSummary: some View {
        HStack(spacing: 8) {
            // Intent icon
            Image(systemName: section.intent.icon)
                .font(.caption)
                .foregroundStyle(section.intent.color)

            // Handle badge (compact) if linked
            if let handle = handle {
                HandleBadgeCompact(handle: handle)
            }

            // Preview text (use displayContent for portals)
            let previewText = displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? ""
            let preview = previewText.count > 80 ? String(previewText.prefix(80)) + "..." : previewText
            Text(preview.isEmpty ? "Empty section" : preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            // Expand indicator
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Child count indicator
            if hasChildren {
                Text("...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private var contentEditor: some View {
        ZStack(alignment: .topLeading) {
            // Hidden text to calculate proper height
            Text(content.isEmpty ? " " : content)
                .font(.body)
                .opacity(0)
                .padding(.vertical, 8)
                .padding(.horizontal, 5)

            // Actual editor
            TextEditor(text: $content)
                .font(.body)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($textFieldFocused)
                .onTapGesture {
                    // Allow TextEditor to handle its own focus
                    textFieldFocused = true
                    isEditing = true
                }
                .onChange(of: content) { _, newValue in
                    // Allow all content including newlines
                    onContentChange(newValue)
                }
        }
        .frame(minHeight: 28)
    }
    
    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(section.intent.backgroundTint)
    }
    
    @ViewBuilder
    private var focusBorder: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: 8)
                .stroke(section.intent.color.opacity(0.6), lineWidth: 1.5)
        }
    }
    
    @ViewBuilder
    private var contextMenuItems: some View {
        // Intent picker section
        SwiftUI.Section {
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
                Label("Change Intent", systemImage: section.intent.icon)
            }
        }
        
        // Structure section
        SwiftUI.Section {
            Button {
                onIndent()
                HapticFeedback.selection()
            } label: {
                Label("Indent", systemImage: "arrow.right.to.line")
            }
            .disabled(section.indentLevel >= 5)
            
            Button {
                onOutdent()
                HapticFeedback.selection()
            } label: {
                Label("Outdent", systemImage: "arrow.left.to.line")
            }
            .disabled(section.indentLevel == 0)
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggleCollapse()
                }
                HapticFeedback.selection()
            } label: {
                Label(
                    section.isCollapsed ? "Expand" : "Collapse",
                    systemImage: section.isCollapsed ? "chevron.down.circle" : "chevron.up.circle"
                )
            }
        }
        
        // Security section
        SwiftUI.Section {
            Button {
                handleLockToggle()
            } label: {
                if section.isLocked {
                    Label(
                        isAuthenticated ? "Re-lock" : "Unlock with \(biometricManager.biometricTypeName)",
                        systemImage: isAuthenticated ? "lock.fill" : biometricManager.biometricIcon
                    )
                } else {
                    Label(
                        "Lock with \(biometricManager.biometricTypeName)",
                        systemImage: "lock.fill"
                    )
                }
            }
        }

        // Handle Loop section
        SwiftUI.Section {
            if handle != nil {
                // Already linked to a handle
                Button(role: .destructive) {
                    onUnlinkHandle()
                    HapticFeedback.selection()
                } label: {
                    Label("Unlink from Loop", systemImage: "link.badge.minus")
                }
            } else {
                // Not linked - offer to create echo
                Button {
                    onCreateLoop()
                    HapticFeedback.selection()
                } label: {
                    Label("Create Loop", systemImage: "link.badge.plus")
                }
            }
        }

        // Copy & Delete section
        SwiftUI.Section {
            Button {
                onApplyTemplate()
            } label: {
                Label("Apply Template", systemImage: "doc.on.doc.fill")
            }

            Button {
                #if os(iOS)
                UIPasteboard.general.string = displayContent
                #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(displayContent, forType: .string)
                #endif
                HapticFeedback.notification(.success)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                onDelete()
                HapticFeedback.notification(.warning)
            } label: {
                Label("Delete", systemImage: "trash")
            }
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
                onContentChange: { _ in },
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
                onContentChange: { _ in },
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
                onContentChange: { _ in },
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
                onContentChange: { _ in },
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
                onContentChange: { _ in },
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
                onContentChange: { _ in },
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
                onContentChange: { _ in },
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
