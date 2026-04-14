import SwiftUI

#if os(macOS)
/// Full-page AI Workspace for macOS — replaces the popup sheet with a rich,
/// split-pane experience. Left panel for multi-select context (pages + loops),
/// right panel for preview, chat/edit interaction, and editor-style output.
struct MacAIWorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var handleManager = HandleManager.shared

    @AppStorage("selectedModuleId") private var selectedModuleId: String?

    // MARK: - Selection State
    @State private var selectedPageIds: Set<String> = []
    @State private var selectedHandleIds: Set<String> = []
    @State private var searchText = ""
    @State private var previewingItemId: String?  // Page or handle ID being previewed
    @State private var previewingType: PreviewType?

    // MARK: - Interaction State
    @State private var interactionMode: InteractionMode?
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    // MARK: - Editor State (for AI-generated page)
    @State private var activeEditorNoteId: String?
    @State private var editorSections: [Section] = []
    @State private var editableTitle = ""
    @State private var editableBody = ""
    @State private var editableSectionContents: [String: String] = [:]
    @State private var bodySelection: NSRange?

    // MARK: - History
    @State private var isHistoryExpanded = false
    @State private var pageCommits: [Commit] = []
    @State private var expandedCommitId: String?
    @State private var expandedCommitContent: CommitContent?

    // MARK: - Context Panel State
    @State private var contextPanelWidth: CGFloat = 280
    @State private var showPagesSection = true
    @State private var showLoopsSection = true

    private let maxSelections = 30
    private let minContextWidth: CGFloat = 220
    private let maxContextWidth: CGFloat = 400

    enum PreviewType { case page, loop }
    enum InteractionMode: String, CaseIterable {
        case edit = "Edit"
        case chat = "Chat"
    }

    private var totalSelections: Int {
        selectedPageIds.count + selectedHandleIds.count
    }

    private var canSelectMore: Bool {
        totalSelections < maxSelections
    }

    private var selectedModuleName: String {
        appState.moduleRepository.modules.first { $0.id == selectedModuleId }?.name ?? "Artifacts"
    }

    private var pages: [Note] {
        appState.noteRepository.notes.filter { !$0.isDeleted && $0.moduleId == selectedModuleId }
    }

    private var filteredPages: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return pages }
        return pages.filter {
            $0.displayTitle.lowercased().contains(query) ||
            $0.body.lowercased().contains(query)
        }
    }

    private var filteredHandles: [Handle] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allHandles = handleManager.handles
        guard !query.isEmpty else { return allHandles }
        return allHandles.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.content.lowercased().contains(query)
        }
    }

    private var selectedHandles: [Handle] {
        handleManager.handles.filter { selectedHandleIds.contains($0.id) }
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            contextPanel
                .frame(minWidth: minContextWidth, idealWidth: contextPanelWidth, maxWidth: maxContextWidth)

            mainPanel
                .frame(minWidth: 400)
        }
        .background(Color.black)
        .navigationTitle("AI Workspace")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    if totalSelections > 0 {
                        Text("\(totalSelections)/\(maxSelections)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .onAppear {
            Task {
                let notes = appState.noteRepository.notes.filter { !$0.isDeleted }
                var sectionsByNote: [String: [Section]] = [:]
                for note in notes {
                    if let sections = try? await appState.sectionRepository.getSections(noteId: note.id) {
                        sectionsByNote[note.id] = sections
                    }
                }
                let handles = HandleManager.shared.handles
                await appState.noteIndexRepository.reindex(
                    notes: notes,
                    sectionsByNote: sectionsByNote,
                    handles: handles
                )
            }
        }
    }

    // MARK: - Context Panel (Left)

    private var contextPanel: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.06))

            Divider().background(Color(white: 0.15))

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Pages Section
                    contextSectionHeader(
                        title: "PAGES",
                        count: selectedPageIds.count,
                        icon: "doc.text",
                        isExpanded: $showPagesSection
                    )

                    if showPagesSection {
                        ForEach(filteredPages) { note in
                            contextPageRow(note)
                        }

                        if filteredPages.isEmpty {
                            Text("No pages found")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                        }
                    }

                    Divider()
                        .background(Color(white: 0.12))
                        .padding(.vertical, 4)

                    // Loops Section
                    contextSectionHeader(
                        title: "LOOPS",
                        count: selectedHandleIds.count,
                        icon: "link",
                        isExpanded: $showLoopsSection
                    )

                    if showLoopsSection {
                        ForEach(filteredHandles) { handle in
                            contextLoopRow(handle)
                        }

                        if filteredHandles.isEmpty {
                            Text("No loops found")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 16)
            }

            Divider().background(Color(white: 0.15))

            // Bottom bar: selection summary + start button
            contextBottomBar
        }
        .background(Color(red: 0.03, green: 0.03, blue: 0.03))
    }

    private func contextSectionHeader(title: String, count: Int, icon: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .default))
                    .foregroundStyle(.secondary)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func contextPageRow(_ note: Note) -> some View {
        let isSelected = selectedPageIds.contains(note.id)
        let isPreviewing = previewingItemId == note.id && previewingType == .page

        return HStack(spacing: 8) {
            // Selection checkbox
            Button {
                togglePage(note.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.accentColor : Color(white: 0.3))
            }
            .buttonStyle(.plain)

            // Intent color bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(note.intent.color)
                .frame(width: 3, height: 24)

            // Content
            VStack(alignment: .leading, spacing: 1) {
                Text(note.displayTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                let preview = note.body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50)
                if !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Preview button
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isPreviewing {
                        previewingItemId = nil
                        previewingType = nil
                    } else {
                        previewingItemId = note.id
                        previewingType = .page
                    }
                }
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 10))
                    .foregroundStyle(isPreviewing ? .white : Color(white: 0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isPreviewing ? Color.white.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                previewingItemId = note.id
                previewingType = .page
            }
        }
    }

    private func contextLoopRow(_ handle: Handle) -> some View {
        let isSelected = selectedHandleIds.contains(handle.id)
        let isPreviewing = previewingItemId == handle.id && previewingType == .loop

        return HStack(spacing: 8) {
            Button {
                toggleHandle(handle.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? handle.intent.color : Color(white: 0.3))
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(handle.intent.color)
                .frame(width: 3, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("@\(handle.displayName)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(handle.intent.color)
                    .lineLimit(1)
                let preview = handle.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50)
                if !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isPreviewing {
                        previewingItemId = nil
                        previewingType = nil
                    } else {
                        previewingItemId = handle.id
                        previewingType = .loop
                    }
                }
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 10))
                    .foregroundStyle(isPreviewing ? .white : Color(white: 0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isPreviewing ? Color.white.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                previewingItemId = handle.id
                previewingType = .loop
            }
        }
    }

    private var contextBottomBar: some View {
        VStack(spacing: 8) {
            if totalSelections > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("\(totalSelections) item\(totalSelections == 1 ? "" : "s") selected")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedPageIds.removeAll()
                            selectedHandleIds.removeAll()
                            interactionMode = nil
                            messages.removeAll()
                            activeEditorNoteId = nil
                        }
                    } label: {
                        Text("Clear")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Select context or go project-wide")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Toggle Selection

    private func togglePage(_ id: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedPageIds.contains(id) {
                selectedPageIds.remove(id)
            } else if canSelectMore {
                selectedPageIds.insert(id)
            }
        }
    }

    private func toggleHandle(_ id: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedHandleIds.contains(id) {
                selectedHandleIds.remove(id)
            } else if canSelectMore {
                selectedHandleIds.insert(id)
            }
        }
    }

    // MARK: - Main Panel (Right)

    private var mainPanel: some View {
        VStack(spacing: 0) {
            if let editorNoteId = activeEditorNoteId {
                // Editor mode — page has been created/edited by AI
                editorView(noteId: editorNoteId)
            } else if let itemId = previewingItemId, interactionMode == nil {
                // Preview mode — showing content of a selected item
                previewPanel(itemId: itemId)
            } else {
                // Workspace interaction mode
                workspacePanel
            }
        }
        .background(Color.black)
    }

    // MARK: - Preview Panel

    private func previewPanel(itemId: String) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if previewingType == .page,
                       let note = pages.first(where: { $0.id == itemId }) {
                        pagePreviewContent(note)
                    } else if previewingType == .loop,
                              let handle = handleManager.handles.first(where: { $0.id == itemId }) {
                        loopPreviewContent(handle)
                    }
                }
                .padding(20)
            }

            Divider().background(Color(white: 0.15))

            // Action bar at bottom of preview
            HStack(spacing: 12) {
                if interactionMode == nil {
                    modeButton(.edit, icon: "pencil.line", label: "Edit")
                    modeButton(.chat, icon: "bubble.left.and.text.bubble.right", label: "Chat")
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(red: 0.04, green: 0.04, blue: 0.04))
        }
    }

    @ViewBuilder
    private func pagePreviewContent(_ note: Note) -> some View {
        // Title
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(note.intent.color)
                .frame(width: 4, height: 22)
            Text(note.displayTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }

        // Body
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            Text(body)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        // Sections (load async)
        PageSectionsPreview(noteId: note.id, appState: appState)
    }

    @ViewBuilder
    private func loopPreviewContent(_ handle: Handle) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(handle.intent.color)
                .frame(width: 4, height: 22)
            Text("@\(handle.displayName)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(handle.intent.color)
            Spacer()
        }

        let content = handle.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            Text("(empty loop)")
                .font(.body)
                .foregroundStyle(.tertiary)
        } else {
            Text(content)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    // MARK: - Workspace Panel (Chat/Edit)

    private var workspacePanel: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if interactionMode == nil {
                            workspaceWelcome
                        }

                        // Chat messages
                        if interactionMode != nil && !messages.isEmpty {
                            ForEach(Array(messages.enumerated()), id: \.element.id) { messageIndex, message in
                                ChatMessageView(message: message, onOptionSelect: { option in
                                    inputText = option
                                    sendMessage()
                                })
                                .id(message.id)

                                if message.role == .assistant {
                                    ForEach(Array(message.actions.enumerated()), id: \.element.id) { actionIndex, action in
                                        ActionCardView(
                                            action: action,
                                            onAccept: { acceptAction(messageIndex: messageIndex, actionIndex: actionIndex) },
                                            onDismiss: { dismissAction(messageIndex: messageIndex, actionIndex: actionIndex) },
                                            previewSections: editorSections,
                                            mediaRepository: appState.mediaRepository
                                        )
                                    }
                                }
                            }
                        }

                        if interactionMode != nil && isLoading {
                            loadingIndicator
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            // Input bar
            if interactionMode != nil {
                inputBar
            } else {
                // Mode picker at bottom
                HStack(spacing: 12) {
                    modeButton(.edit, icon: "pencil.line", label: "Edit")
                    modeButton(.chat, icon: "bubble.left.and.text.bubble.right", label: "Chat")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(red: 0.04, green: 0.04, blue: 0.04))
            }
        }
    }

    private var workspaceWelcome: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 40)

            Image("MobiusStrip")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(.white.opacity(0.3))

            Text("AI Workspace")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            if totalSelections > 0 {
                Text("\(totalSelections) item\(totalSelections == 1 ? "" : "s") selected as context")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select pages and loops for context, or start project-wide")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Choose a mode to begin")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
                .frame(height: 20)
        }
        .frame(maxWidth: .infinity)
    }

    private func modeButton(_ mode: InteractionMode, icon: String, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                interactionMode = mode
                messages.removeAll()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(interactionMode == mode ? .black : Color(.lightGray))
            .background(interactionMode == mode ? Color.white : Color(white: 0.08))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(interactionMode == mode ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Editor View (AI-generated page seamlessly editable)

    private func editorView(noteId: String) -> some View {
        VStack(spacing: 0) {
            // Editor toolbar
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeEditorNoteId = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                        Text("Back to Workspace")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if let note = pages.first(where: { $0.id == noteId }) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(note.intent.color)
                            .frame(width: 6, height: 6)
                        Text(note.displayTitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHistoryExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                        if !pageCommits.isEmpty {
                            Text("\(pageCommits.count)")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isHistoryExpanded ? Color.white.opacity(0.1) : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(red: 0.04, green: 0.04, blue: 0.04))

            Divider().background(Color(white: 0.15))

            // Editor content + optional chat
            HSplitView {
                // Left: Page editor
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Title
                        TextField("Title", text: $editableTitle)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                            .textFieldStyle(.plain)
                            .padding(.bottom, 12)
                            .onChange(of: editableTitle) { _ in
                                saveEditorTitle(noteId: noteId)
                            }

                        // Body
                        BodyTextEditor(
                            text: $editableBody,
                            selectedRange: $bodySelection,
                            onCreateNode: {},
                            onTextChange: { saveEditorBody(noteId: noteId) }
                        )
                        .frame(minHeight: 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)

                        // Sections
                        let activeSections = editorSections.filter { $0.deletedAt == nil }
                        ForEach(activeSections) { section in
                            editorSectionRow(section)

                            // Interstitial text
                            if let note = pages.first(where: { $0.id == noteId }) {
                                let interstitial = note.textAfterSection(section.id)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !interstitial.isEmpty {
                                    Text(interstitial)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .frame(minWidth: 300)

                // Right: Chat interaction (always visible in editor)
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if messages.isEmpty && interactionMode != nil {
                                    Text("Continue refining this page...")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 20)
                                }

                                ForEach(Array(messages.enumerated()), id: \.element.id) { messageIndex, message in
                                    ChatMessageView(message: message, onOptionSelect: { option in
                                        inputText = option
                                        sendMessage()
                                    })
                                    .id(message.id)

                                    if message.role == .assistant {
                                        ForEach(Array(message.actions.enumerated()), id: \.element.id) { actionIndex, action in
                                            ActionCardView(
                                                action: action,
                                                onAccept: { acceptAction(messageIndex: messageIndex, actionIndex: actionIndex) },
                                                onDismiss: { dismissAction(messageIndex: messageIndex, actionIndex: actionIndex) },
                                                previewSections: editorSections,
                                                mediaRepository: appState.mediaRepository
                                            )
                                        }
                                    }
                                }

                                if isLoading {
                                    loadingIndicator
                                }
                            }
                            .padding(16)
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let lastId = messages.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                    }

                    inputBar
                }
                .frame(minWidth: 280, idealWidth: 320)
                .background(Color(red: 0.03, green: 0.03, blue: 0.03))
            }
        }
    }

    @ViewBuilder
    private func editorSectionRow(_ section: Section) -> some View {
        let handleName = section.handleId
            .flatMap { HandleManager.shared.getHandle(id: $0) }
            .map { "@\($0.displayName)" }

        let binding = Binding<String>(
            get: { editableSectionContents[section.id] ?? section.content },
            set: { editableSectionContents[section.id] = $0 }
        )

        if section.contentType == .image || section.contentType == .audio {
            // Non-text sections: render read-only
            staticSectionRow(section)
        } else if section.sectionType == .fold {
            VStack(alignment: .leading, spacing: 4) {
                if let handleName {
                    Text(handleName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(section.intent.color)
                }
                TextField("Content", text: binding, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: binding.wrappedValue) { _ in
                        saveSectionContent(sectionId: section.id)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(section.intent.backgroundTint))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 2)
        } else {
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(section.intent.color.opacity(0.5))
                    .frame(width: 2, height: 16)
                    .padding(.top, 4)
                TextField("Content", text: binding, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: binding.wrappedValue) { _ in
                        saveSectionContent(sectionId: section.id)
                    }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func staticSectionRow(_ section: Section) -> some View {
        let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if section.contentType == .image {
            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let count = content.split(separator: ",").count
                Text(count > 1 ? "\(count) Photos" : "Photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(section.intent.backgroundTint))
            .padding(.vertical, 2)
        } else if section.contentType == .audio {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Audio Recording")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(section.intent.backgroundTint))
            .padding(.vertical, 2)
        }
    }

    // MARK: - Loading Indicator

    private static let loadingPhrases = [
        "Looping...", "Dooping...", "Hooping...",
        "Mooping...", "Zooping...", "Pooping..."
    ]

    @State private var loadingPhraseIndex = 0

    private var loadingIndicator: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text(Self.loadingPhrases[loadingPhraseIndex % Self.loadingPhrases.count])
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .onAppear { loadingPhraseIndex = 0 }
                .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        loadingPhraseIndex += 1
                    }
                }
            Spacer()
        }
    }

    // MARK: - Input Bar

    private static let editPlaceholders = [
        "Lets build something...",
        "Drop an idea here...",
        "Give this a shape...",
        "Initialize a concept...",
        "Unfold the vision...",
    ]

    private static let chatPlaceholders = [
        "Give this a shape...",
        "Discuss your pages...",
        "Ask about your content...",
        "Explore an idea...",
    ]

    @State private var currentPlaceholder = editPlaceholders.randomElement()!

    private var canSend: Bool {
        !isLoading && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(
                "",
                text: $inputText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if inputText.isEmpty {
                    Text(currentPlaceholder)
                        .foregroundStyle(Color.gray)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }
            }
            .focused($isInputFocused)
            .lineLimit(1...10)
            .onSubmit {
                sendMessage()
            }
            .background {
                WorkspaceInputKeyHandler(inputText: $inputText)
            }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.body)
                    .foregroundStyle(canSend ? .black : .white)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Color.white : Color.gray.opacity(0.3))
                    .clipShape(Circle())
            }
            .disabled(!canSend)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        messages.append(ChatMessage(role: .user, content: text))
        inputText = ""
        isLoading = true

        let currentMode = interactionMode ?? .edit
        let currentSelectedHandles = selectedHandles

        Task {
            do {
                // Auto-create page for edit mode if none exists
                var targetPageId = activeEditorNoteId
                if currentMode == .edit && targetPageId == nil {
                    let newPage = try await appState.noteRepository.createNote(
                        moduleId: selectedModuleId
                    )
                    targetPageId = newPage.id
                    await MainActor.run {
                        activeEditorNoteId = newPage.id
                        loadEditorState(newPage.id)
                        loadCommits(for: newPage.id)
                    }
                }

                let apiMessages = buildAPIMessages()

                // Build context from selected pages + loops
                let context: String
                if selectedPageIds.isEmpty && selectedHandleIds.isEmpty {
                    // Project-wide mode
                    if let moduleId = selectedModuleId {
                        context = await appState.contextAssembler.assembleProjectContext(
                            query: text,
                            moduleId: moduleId,
                            selectedHandles: currentSelectedHandles
                        )
                    } else {
                        context = ""
                    }
                } else {
                    // Multi-page context assembly
                    context = await assembleMultiPageContext(
                        query: text,
                        selectedPageIds: selectedPageIds,
                        selectedHandles: currentSelectedHandles,
                        editorNoteId: targetPageId
                    )
                }

                switch currentMode {
                case .edit:
                    let response = try await ClaudeService.sendWithTools(
                        messages: apiMessages,
                        noteContext: context
                    )

                    let finalActions = coalesceMicroActions(response.actions, pageId: targetPageId)

                    let content: String
                    if !response.text.isEmpty {
                        content = response.text
                    } else if !finalActions.isEmpty {
                        content = "Here's what I suggest:"
                    } else {
                        content = "I wasn't able to generate a response. Try rephrasing your request."
                    }
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: content,
                        actions: finalActions
                    ))

                case .chat:
                    let responseText = try await ClaudeService.sendChat(
                        messages: apiMessages,
                        noteContext: context
                    )
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: responseText
                    ))
                }
            } catch {
                let errorDesc = "\(error)"
                let errorMessage: String
                if errorDesc.contains("404") || error.localizedDescription.contains("404") {
                    errorMessage = "The AI edge function returned 404. Make sure the ai-proxy function is deployed and ANTHROPIC_API_KEY is set."
                } else if !SupabaseManager.shared.isConfigured {
                    errorMessage = "Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to your Info.plist."
                } else if !SupabaseManager.shared.isAuthenticated {
                    errorMessage = "You need to sign in before using AI features."
                } else {
                    errorMessage = "Something went wrong: \(error.localizedDescription)"
                }
                messages.append(ChatMessage(role: .assistant, content: errorMessage))
            }
            isLoading = false
        }
    }

    // MARK: - Multi-Page Context Assembly

    private func assembleMultiPageContext(
        query: String,
        selectedPageIds: Set<String>,
        selectedHandles: [Handle],
        editorNoteId: String?
    ) async -> String {
        var contextParts: [String] = []
        var remainingBudget = 6000  // Generous budget for multi-page

        // 1. Editor page (highest priority — full structured context)
        if let editorId = editorNoteId,
           let note = try? await appState.noteRepository.getNote(id: editorId) {
            let sections = (try? await appState.sectionRepository.getSections(noteId: editorId)) ?? []
            let pageContext = appState.contextAssembler.buildStructuredPageContext(page: note, sections: sections)
            contextParts.append(pageContext)
            remainingBudget -= NoteIndexRepository.estimateTokens(pageContext)
        }

        // 2. Selected pages as context summaries
        let contextPageIds = selectedPageIds.filter { $0 != editorNoteId }
        if !contextPageIds.isEmpty {
            var pageSummaries: [String] = ["SELECTED CONTEXT PAGES (\(contextPageIds.count)):"]
            for pageId in contextPageIds {
                guard remainingBudget > 100 else { break }
                guard let note = try? await appState.noteRepository.getNote(id: pageId) else { continue }
                let sections = (try? await appState.sectionRepository.getSections(noteId: pageId)) ?? []
                let title = note.displayTitle
                let bodyPreview = ContextAssembler.cleanContentForAI(note.body, truncate: true)
                let sectionPreviews = sections
                    .filter { $0.contentType != .image && $0.contentType != .audio && $0.deletedAt == nil }
                    .prefix(5)
                    .compactMap { section -> String? in
                        let content = ContextAssembler.cleanContentForAI(section.content, truncate: true)
                        guard !content.isEmpty else { return nil }
                        let handleTag = section.handleId
                            .flatMap { HandleManager.shared.getHandle(id: $0) }
                            .map { "@\($0.displayName): " } ?? ""
                        return "  - \(handleTag)\(content)"
                    }

                var entry = "---\nPage: \"\(title)\" (id: \(note.id))"
                if !bodyPreview.isEmpty {
                    entry += "\nBody: \(bodyPreview)"
                }
                if !sectionPreviews.isEmpty {
                    entry += "\nNodes:\n" + sectionPreviews.joined(separator: "\n")
                }

                let tokenCost = NoteIndexRepository.estimateTokens(entry)
                guard remainingBudget - tokenCost > 0 else { break }
                pageSummaries.append(entry)
                remainingBudget -= tokenCost
            }
            contextParts.append(pageSummaries.joined(separator: "\n"))
        }

        // 3. Selected loops
        if !selectedHandles.isEmpty {
            let loopContext: String = selectedHandles.map { handle -> String in
                let cleaned = handle.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = cleaned.isEmpty ? "(empty)" : cleaned
                return "Loop: @\(handle.displayName) (id: \(handle.id))\nContent:\n\(preview)"
            }.joined(separator: "\n\n---\n\n")
            contextParts.append("Selected loop content:\n\n\(loopContext)")
        }

        return contextParts.joined(separator: "\n\n")
    }

    // MARK: - API Message Builder

    private func buildAPIMessages() -> [ClaudeService.Message] {
        var apiMessages: [ClaudeService.Message] = []
        for message in messages {
            apiMessages.append(ClaudeService.Message(
                role: message.role == .user ? "user" : "assistant",
                content: message.content
            ))
            if message.role == .assistant && !message.actions.isEmpty {
                let resolvedSummaries = message.actions.compactMap { action -> String? in
                    switch action.status {
                    case .accepted: return "[\(action.toolName) was accepted and executed]"
                    case .dismissed: return "[\(action.toolName) was dismissed by user]"
                    case .failed(let reason): return "[\(action.toolName) failed: \(reason)]"
                    case .pending: return nil
                    }
                }
                if !resolvedSummaries.isEmpty {
                    apiMessages.append(ClaudeService.Message(
                        role: "user",
                        content: resolvedSummaries.joined(separator: "\n")
                    ))
                }
            }
        }
        return apiMessages
    }

    // MARK: - Action Coalescing

    private func coalesceMicroActions(_ actions: [SuggestedAction], pageId: String?) -> [SuggestedAction] {
        guard let pageId else { return actions }

        var deleteIds: Set<String> = []
        var sectionUpdates: [String: String] = [:]
        var otherActions: [SuggestedAction] = []

        for action in actions {
            switch action.actionType {
            case .deleteSection(let p):
                deleteIds.insert(p.sectionId)
            case .updateSectionContent(let p):
                sectionUpdates[p.sectionId] = p.newContent
            default:
                otherActions.append(action)
            }
        }

        let microCount = deleteIds.count + sectionUpdates.count
        guard microCount >= 2 else { return actions }

        let activeSections = editorSections.filter { $0.deletedAt == nil }
        var keepSections: [SuggestedAction.KeepSection] = []
        for section in activeSections {
            if deleteIds.contains(section.id) { continue }
            let newContent = sectionUpdates[section.id]
            keepSections.append(SuggestedAction.KeepSection(
                sectionId: section.id,
                newContent: newContent
            ))
        }

        let page = pages.first(where: { $0.id == pageId })
        let noteTitle = page?.displayTitle ?? ""

        var newBody = page?.body ?? ""
        otherActions = otherActions.filter { action in
            if case .updatePageBody(let p) = action.actionType, p.noteId == pageId {
                newBody = p.newBody
                return false
            }
            return true
        }

        var summaryParts: [String] = []
        if deleteIds.count > 0 {
            summaryParts.append("Removed \(deleteIds.count) section\(deleteIds.count == 1 ? "" : "s")")
        }
        if sectionUpdates.count > 0 {
            summaryParts.append("Updated \(sectionUpdates.count) section\(sectionUpdates.count == 1 ? "" : "s")")
        }

        var previewParts: [String] = []
        let trimmedBody = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty { previewParts.append(trimmedBody) }
        for section in activeSections {
            if deleteIds.contains(section.id) { continue }
            let content = sectionUpdates[section.id] ?? section.content
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let prefix = section.sectionType == .fold ? "▪ " : "│ "
                previewParts.append("\(prefix)\(trimmed)")
            }
        }

        let rewriteAction = SuggestedAction(
            id: UUID().uuidString,
            actionType: .rewritePage(SuggestedAction.RewritePageParams(
                noteId: pageId,
                noteTitle: noteTitle,
                newBody: newBody,
                keepSections: keepSections,
                interstitialContent: [:],
                summary: summaryParts.joined(separator: ", "),
                pagePreview: previewParts.joined(separator: "\n\n")
            ))
        )

        return [rewriteAction] + otherActions
    }

    // MARK: - Action Handlers

    private func acceptAction(messageIndex: Int, actionIndex: Int) {
        guard messageIndex < messages.count,
              actionIndex < messages[messageIndex].actions.count else { return }

        let action = messages[messageIndex].actions[actionIndex]
        guard action.status == .pending else { return }

        Task {
            do {
                try await action.execute(appState: appState)

                // Refresh editor state
                if let editorId = activeEditorNoteId {
                    let freshSections = try? await appState.sectionRepository.getSections(noteId: editorId)
                    let freshNote = try? await appState.noteRepository.getNote(id: editorId)

                    if let sections = freshSections {
                        editorSections = sections
                        var contents: [String: String] = [:]
                        for section in sections where section.deletedAt == nil {
                            contents[section.id] = section.content
                        }
                        editableSectionContents = contents
                    }
                    if let note = freshNote {
                        editableTitle = note.displayTitle(sections: editorSections)
                        editableBody = note.body
                    }

                    // Auto-commit
                    let name = "AI: \(action.title)"
                    _ = try? await appState.commitModule.createCommit(
                        noteId: editorId,
                        name: name,
                        isAutoCommit: false
                    )
                    loadCommits(for: editorId)
                }

                messages[messageIndex].actions[actionIndex] = action.withStatus(.accepted)
                HapticFeedback.notification(.success)
            } catch {
                messages[messageIndex].actions[actionIndex] = action.withStatus(.failed(error.localizedDescription))
                HapticFeedback.notification(.error)
            }
        }
    }

    private func dismissAction(messageIndex: Int, actionIndex: Int) {
        guard messageIndex < messages.count,
              actionIndex < messages[messageIndex].actions.count else { return }
        let action = messages[messageIndex].actions[actionIndex]
        guard action.status == .pending else { return }
        messages[messageIndex].actions[actionIndex] = action.withStatus(.dismissed)
        HapticFeedback.impact(.light)
    }

    // MARK: - Editor Persistence

    private func loadEditorState(_ noteId: String) {
        Task {
            if let sections = try? await appState.sectionRepository.getSections(noteId: noteId) {
                editorSections = sections
                var contents: [String: String] = [:]
                for section in sections where section.deletedAt == nil {
                    contents[section.id] = section.content
                }
                editableSectionContents = contents
            }
            if let note = try? await appState.noteRepository.getNote(id: noteId) {
                editableTitle = note.displayTitle(sections: editorSections)
                editableBody = note.body
            }
        }
    }

    private func loadCommits(for noteId: String) {
        Task {
            if let commits = try? await appState.commitRepository.getCommits(noteId: noteId) {
                pageCommits = commits.filter { !$0.isHidden }
            }
        }
    }

    private func saveEditorTitle(noteId: String) {
        let title = editableTitle
        Task {
            try? await appState.noteRepository.updateNoteTitle(noteId, title: title.isEmpty ? nil : title)
        }
    }

    private func saveEditorBody(noteId: String) {
        let body = editableBody
        Task {
            try? await appState.noteRepository.updateNoteBody(noteId, body: body, clearRichText: true)
        }
    }

    private func saveSectionContent(sectionId: String) {
        guard let content = editableSectionContents[sectionId] else { return }
        Task {
            try? await appState.sectionRepository.updateContent(sectionId, content: content, clearRichText: true)
        }
    }
}

// MARK: - Page Sections Preview (async-loading helper)

private struct PageSectionsPreview: View {
    let noteId: String
    let appState: AppState
    @State private var sections: [Section] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sections.filter { $0.deletedAt == nil }) { section in
                previewSectionRow(section)
            }
        }
        .task {
            if let loaded = try? await appState.sectionRepository.getSections(noteId: noteId) {
                sections = loaded
            }
        }
    }

    @ViewBuilder
    private func previewSectionRow(_ section: Section) -> some View {
        let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let handleName = section.handleId
            .flatMap { HandleManager.shared.getHandle(id: $0) }
            .map { "@\($0.displayName)" }

        if section.contentType == .image {
            HStack(spacing: 4) {
                Image(systemName: "photo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                let count = content.split(separator: ",").count
                Text(count > 1 ? "\(count) Photos" : "Photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } else if section.contentType == .audio {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Audio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } else if !content.isEmpty {
            if section.sectionType == .fold {
                VStack(alignment: .leading, spacing: 2) {
                    if let handleName {
                        Text(handleName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(section.intent.color)
                    }
                    Text(content)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(section.intent.backgroundTint))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.vertical, 2)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(section.intent.color.opacity(0.5))
                        .frame(width: 2, height: 14)
                        .padding(.top, 2)
                    Text(content)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
#endif
