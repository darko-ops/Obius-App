import SwiftUI

struct IntelligenceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var insightRepository: InsightRepository
    @State private var isScanning = false
    @State private var selectedInsight: Insight?
    @State private var showCreateSheet = false
    @State private var navigateToNote: Note?
    @State private var navigateSectionId: String?
    @State private var pendingGoToNoteId: String?
    @State private var pendingGoToSectionId: String?
    @State private var showingLoops = false
    @State private var showWorkspaceSheet = false
    @State private var showingSettings = false
    @AppStorage("selectedModuleId") private var selectedModuleId: String?
    @State private var showingModulePicker = false
    @StateObject private var handleManager = HandleManager.shared
    @StateObject private var echoManager = EchoManager.shared
    @State private var activeCategorySheet: InsightType?
    @State private var selectedEcho: Echo?
    @State private var showingManageEchoes = false

    private var insightEngine: InsightEngine {
        InsightEngine(
            noteRepository: appState.noteRepository,
            sectionRepository: appState.sectionRepository,
            handleRepository: appState.handleRepository,
            insightRepository: insightRepository,
            database: appState.database
        )
    }

    private var selectedModuleName: String {
        appState.moduleRepository.modules.first { $0.id == selectedModuleId }?.name ?? "Artifacts"
    }

    /// Note IDs in the selected module. nil = show all (no filter).
    private var moduleNoteIds: Set<String>? {
        guard let moduleId = selectedModuleId else { return nil }
        return Set(appState.noteRepository.notes.filter { $0.moduleId == moduleId }.map(\.id))
    }

    /// Filter any insight array to the selected module.
    /// Insights with nil sourceNoteId pass through (shown in all modules).
    private func insightsInModule(_ insights: [Insight]) -> [Insight] {
        guard let noteIds = moduleNoteIds else { return insights }
        return insights.filter { insight in
            guard let sourceNoteId = insight.sourceNoteId else { return true }
            return noteIds.contains(sourceNoteId)
        }
    }

    // MARK: - Category Grouping

    /// Display order for categories on the main view.
    private static let categoryOrder: [InsightType] = [.safety, .reminder, .cleanup]

    /// Groups surfaced (non-echo) insights by type.
    private var categoryGroups: [(type: InsightType, insights: [Insight])] {
        let nonEcho = insightsInModule(insightRepository.surfacedInsights)
            .filter { $0.insightType != .upcomingEcho }

        var grouped: [InsightType: [Insight]] = [:]
        for insight in nonEcho {
            grouped[insight.insightType, default: []].append(insight)
        }

        return Self.categoryOrder.compactMap { type in
            guard let insights = grouped[type], !insights.isEmpty else { return nil }
            return (type: type, insights: insights)
        }
    }

    var body: some View {
        mainContent
        .navigationTitle("Intelligence")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(.lightGray))
                        .offset(y: 2)
                }
            }
            ToolbarItem(placement: .principal) {
                Button {
                    showingModulePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(selectedModuleName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLoops = true
                } label: {
                    Text("@")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(.lightGray))
                }
            }
        }
        .sheet(item: $selectedInsight, onDismiss: {
            handleInsightSheetDismiss()
        }) { insight in
            insightDetailSheet(for: insight)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateInsightSheet { title, body in
                Task {
                    try? await insightRepository.createInsight(
                        type: .reminder,
                        title: title,
                        body: body,
                        status: .tracked,
                        sourceSectionId: "task"
                    )
                    haptic(.success)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
            .environmentObject(AppearanceManager.shared)
        }
        .sheet(isPresented: $showingLoops) {
            LoopsSheetView(handles: handleManager.handles)
        }
        .sheet(isPresented: $showingModulePicker) {
            ModulePickerSheet(
                moduleRepository: appState.moduleRepository,
                selectedModuleId: $selectedModuleId
            )
        }
        .sheet(isPresented: $showWorkspaceSheet) {
            WorkspaceSheet(handles: handleManager.handles)
                .environmentObject(appState)
        }
        .sheet(item: $selectedEcho) { echo in
            EchoDetailSheet(echo: echo)
        }
        .sheet(isPresented: $showingManageEchoes) {
            ManageEchoesSheet(echoManager: echoManager, onSelect: { echo in
                showingManageEchoes = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    selectedEcho = echo
                }
            })
        }
        .sheet(item: $activeCategorySheet) { type in
            let insights = categoryGroups.first(where: { $0.type == type })?.insights ?? []
            CategoryDetailSheet(
                insightType: type,
                insights: insights,
                onTrack: { insight in
                    Task {
                        try? await insightRepository.trackInsight(insight.id)
                        haptic(.success)
                    }
                },
                onDismiss: { insight in
                    Task {
                        try? await insightRepository.dismissInsight(insight.id)
                    }
                    haptic(.light)
                },
                onSelectInsight: { insight in
                    activeCategorySheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        selectedInsight = insight
                    }
                }
            )
        }
        .task {
            if selectedModuleId == nil,
               let local = appState.moduleRepository.getLocalModule() {
                selectedModuleId = local.id
            }
            await runScan()
        }
        .onChange(of: selectedModuleId) { _, _ in
            Task { await runScan() }
        }
        .navigationDestination(item: $navigateToNote) { note in
            NoteEditorView(noteId: note.id, targetSectionId: navigateSectionId)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    trackedSection

                    activeEchoesSection

                    if !upcomingEchoInsights.isEmpty {
                        upcomingEchoesSection
                    }

                    if !allSurfacedInsights.isEmpty {
                        categoriesSection
                    }

                    if upcomingEchoInsights.isEmpty
                        && allSurfacedInsights.isEmpty
                        && insightsInModule(insightRepository.trackedInsights).isEmpty
                        && firingEchoes.isEmpty
                        && !isScanning {
                        emptyState
                    }
                }
                .padding()
            }
            .overlay(alignment: .bottomTrailing) {
                workspaceFAB
            }
        }
    }

    // MARK: - Active Echoes

    private var firingEchoes: [Echo] {
        echoManager.activeEchoes.filter { $0.isAlerted }
    }

    private var activeEchoesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ECHOES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ForEach(firingEchoes) { echo in
                EchoRowView(echo: echo)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEcho = echo
                    }

                Divider()
            }

            Button {
                showingManageEchoes = true
            } label: {
                HStack {
                    Text("Manage Echoes")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(echoManager.activeEchoes.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                    .background(Color(red: 0.06, green: 0.06, blue: 0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Upcoming Echoes

    private var upcomingEchoInsights: [Insight] {
        insightsInModule(insightRepository.surfacedInsights).filter { $0.insightType == .upcomingEcho }
    }

    private var upcomingEchoesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ECHOES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(upcomingEchoInsights) { insight in
                        UpcomingEchoCard(
                            insight: insight,
                            onTap: {
                                selectedInsight = insight
                            },
                            onLongPress: {
                                selectedInsight = insight
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Category Cards

    private var allSurfacedInsights: [Insight] {
        insightsInModule(insightRepository.surfacedInsights)
            .filter { $0.insightType != .upcomingEcho }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("INSIGHTS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ForEach(allSurfacedInsights) { insight in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: insight.displayIcon)
                                .font(.caption2)
                            Text(insight.displayLabel)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(insight.displayTint.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(insight.displayTint.color.opacity(0.15))
                        .clipShape(Capsule())

                        Spacer()

                        HStack(spacing: 16) {
                            Button {
                                Task {
                                    try? await insightRepository.trackInsight(insight.id)
                                    haptic(.success)
                                }
                            } label: {
                                Image(systemName: "star")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task {
                                    try? await insightRepository.dismissInsight(insight.id)
                                }
                                haptic(.light)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(insight.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if !insight.body.isEmpty {
                        Text(insight.body)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedInsight = insight
                }

                if insight.id != allSurfacedInsights.last?.id {
                    Divider()
                        .padding(.leading, 36)
                }
            }
        }
    }

    // MARK: - Tracked

    private var trackedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRACKING")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline)
                        .foregroundStyle(Color(.lightGray))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(insightsInModule(insightRepository.trackedInsights).sorted { lhs, rhs in
                        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                        return lhs.createdAt > rhs.createdAt
                    }) { insight in
                        TrackedInsightChip(
                            insight: insight,
                            onTap: {
                                selectedInsight = insight
                            },
                            onUntrack: {
                                Task {
                                    try? await insightRepository.untrackInsight(insight.id)
                                    haptic(.light)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 60)

            Image(systemName: "brain")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Intelligence")
                .font(.title2.weight(.semibold))

            Text("Insights about your notes will appear here automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
                .frame(height: 60)
        }
    }

    // MARK: - Workspace FAB

    private var workspaceFAB: some View {
        Button {
            showWorkspaceSheet = true
        } label: {
            Image("MobiusStrip")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 85, height: 85)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1)
                )
                .shadow(color: .white.opacity(0.2), radius: 10)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Actions

    private func handleInsightSheetDismiss() {
        if let noteId = pendingGoToNoteId,
           let note = appState.noteRepository.notes.first(where: { $0.id == noteId }) {
            navigateSectionId = pendingGoToSectionId
            navigateToNote = note
        }
        pendingGoToNoteId = nil
        pendingGoToSectionId = nil
    }

    @ViewBuilder
    private func insightDetailSheet(for insight: Insight) -> some View {
        let refs = resolveReferences(for: insight)
        InsightDetailSheet(
            insight: insight,
            onTrack: {
                Task {
                    try? await insightRepository.trackInsight(insight.id)
                    haptic(.success)
                }
            },
            onDismiss: {
                Task {
                    try? await insightRepository.dismissInsight(insight.id)
                }
                haptic(.light)
            },
            onUntrack: {
                Task {
                    try? await insightRepository.untrackInsight(insight.id)
                    haptic(.light)
                }
            },
            onDeleteNote: (insight.insightType == .cleanup && insight.sourceSectionId == "nonsense") ? {
                Task {
                    if let noteId = insight.sourceNoteId {
                        try? await appState.noteRepository.deleteNote(noteId)
                        try? await insightRepository.dismissInsight(insight.id)
                        haptic(.success)
                    }
                }
            } : nil,
            onCreateBlock: (insight.insightType == .cleanup && insight.sourceSectionId == "dormant_loop") ? { blockName in
                Task {
                    if let noteId = insight.sourceNoteId {
                        try? await appState.noteRepository.setGroupName(noteId: noteId, groupName: blockName)
                        try? await insightRepository.dismissInsight(insight.id)
                        haptic(.success)
                    }
                }
            } : nil,
            references: refs,
            onNavigate: { ref in
                pendingGoToNoteId = ref.noteId
                pendingGoToSectionId = ref.sectionId
            }
        )
    }

    private func resolveReferences(for insight: Insight) -> [InsightReference] {
        var refs: [InsightReference] = []

        if let noteId = insight.sourceNoteId,
           let note = appState.noteRepository.notes.first(where: { $0.id == noteId }) {
            // For new consolidated types, sourceSectionId stores the subtype string — not a real section.
            // Only pass sourceSectionId as a real section for reminder subtypes that kept it from old code.
            let sectionId: String? = nil  // subtypes are never real section IDs
            refs.append(InsightReference(noteId: noteId, title: note.displayTitle, sectionId: sectionId))
        }

        // relatedNoteId may contain comma-separated IDs for multi-reference insights
        // (but not for suggested_echo, where it stores JSON config)
        let isSuggestedEcho = insight.insightType == .reminder && insight.sourceSectionId == "suggested_echo"
        if !isSuggestedEcho, let relatedField = insight.relatedNoteId {
            let relatedIds = relatedField.split(separator: ",").map(String.init)
            for relatedId in relatedIds {
                if let note = appState.noteRepository.notes.first(where: { $0.id == relatedId }) {
                    refs.append(InsightReference(noteId: relatedId, title: note.displayTitle, sectionId: nil))
                }
            }
        }

        return refs
    }

    private func runScan() async {
        isScanning = true
        await insightEngine.scan(moduleId: selectedModuleId)
        isScanning = false
    }

    // MARK: - Haptics

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    var actions: [SuggestedAction]
    let timestamp = Date()

    enum MessageRole {
        case user
        case assistant
    }

    init(role: MessageRole, content: String, actions: [SuggestedAction] = []) {
        self.role = role
        self.content = content
        self.actions = actions
    }
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? Color.accentColor : Color(red: 0.12, green: 0.12, blue: 0.12))
                    .foregroundStyle(message.role == .user ? .white : Color(.lightGray))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            if message.role == .assistant {
                Spacer()
            }
        }
    }
}


// MARK: - Loops Sheet View

/// Sheet that lists all loops, reusing the same row style as the Library page.
struct LoopsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let handles: [Handle]

    @State private var selectedHandle: Handle?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if handles.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "link")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Loops")
                            .font(.headline)
                        Text("Loops sync content across sections")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(handles) { handle in
                                LoopRowView(handle: handle)
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedHandle = handle
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Loops")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedHandle) { handle in
                LoopDetailSheet(handle: handle)
            }
        }
    }
}

// MARK: - Workspace Sheet

struct WorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    let handles: [Handle]
    var preselectedPageId: String? = nil

    enum FocusMode: String, CaseIterable {
        case pages = "Pages"
        case loops = "Loops"
    }

    enum InteractionMode: String, CaseIterable {
        case edit = "Edit"
        case chat = "Chat"
    }

    @State private var selectedHandleIds: Set<String> = []
    @State private var focusMode: FocusMode = .pages
    @State private var selectedPageId: String?
    @State private var cachedPageSections: [Section] = []
    @State private var editableContent = ""
    @State private var editingHandleId: String?
    @State private var contentHasUnsavedChanges = false
    @State private var interactionMode: InteractionMode?
    @State private var searchText = ""
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    // Editable page content state
    @State private var editableTitle = ""
    @State private var editableBody = ""
    @State private var editableSectionContents: [String: String] = [:]

    // History
    @State private var isHistoryExpanded = false

    private var selectedHandles: [Handle] {
        handles.filter { selectedHandleIds.contains($0.id) }
    }

    private var primaryHandle: Handle? {
        guard let firstId = selectedHandleIds.sorted().first else { return nil }
        return handles.first { $0.id == firstId }
    }

    @AppStorage("selectedModuleId") private var selectedModuleId: String?

    private var pages: [Note] {
        appState.noteRepository.notes.filter { !$0.isDeleted && $0.moduleId == selectedModuleId }
    }

    private var pageHandles: [Handle] {
        let handleIds = Set(cachedPageSections.compactMap(\.handleId))
        return handles.filter { handleIds.contains($0.id) }
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
        guard !query.isEmpty else { return handles }
        return handles.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.content.lowercased().contains(query)
        }
    }

    private var hasSelection: Bool {
        selectedPageId != nil || !selectedHandleIds.isEmpty
    }

    private var canSend: Bool {
        guard !isLoading else { return false }
        return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Search bar (hidden when something is selected)
                        if !hasSelection {
                            searchBar
                        }

                        // Focus mode selector (hidden when opened from editor with a specific page)
                        if preselectedPageId == nil {
                            focusSelector
                        }

                        // Pages list or Loop list based on mode
                        if focusMode == .pages && preselectedPageId == nil {
                            pagesList
                        } else if focusMode == .loops && preselectedPageId == nil {
                            loopSelector
                        }

                        // Full page content when a page is selected
                        if let pageId = selectedPageId,
                           let page = pages.first(where: { $0.id == pageId }) {
                            pageFullContent(for: page)
                        }

                        // Change history (below page content)
                        if selectedPageId != nil {
                            changeHistory
                        }

                        // Loop content editor (only in loops mode)
                        if focusMode == .loops, let handle = primaryHandle {
                            loopContentEditor(for: handle)
                        }

                        // Mode picker after selection
                        if hasSelection && interactionMode == nil {
                            modePicker
                        }

                        // Chat messages (only after mode chosen)
                        if interactionMode != nil && !messages.isEmpty {
                            chatSection
                        }

                        if interactionMode != nil && isLoading {
                            loadingIndicator
                        }
                    }
                    .padding()
                }

                // Input bar pinned at bottom (only after mode chosen)
                if interactionMode != nil {
                    inputBar
                }
            }
            .background(Color.black)
            .navigationTitle("Workspace")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        savePendingEdits()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if let preselectedPageId, selectedPageId == nil {
                selectedPageId = preselectedPageId
                focusMode = .pages
                loadSectionsForPage(preselectedPageId)
            }
        }
    }

    // MARK: - Loop Content Editor

    @ViewBuilder
    private func loopContentEditor(for handle: Handle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("@\(handle.displayName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(handle.intent.color)

                if contentHasUnsavedChanges {
                    Text("Edited")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(handle.intent.color.opacity(0.7))
                        .clipShape(Capsule())
                }

                Spacer()
            }

            TextEditor(text: $editableContent)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 100, maxHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: editableContent) {
                    if editingHandleId == handle.id {
                        contentHasUnsavedChanges = true
                    }
                }
        }
    }

    // MARK: - Full Page Content

    @ViewBuilder
    private func pageFullContent(for note: Note) -> some View {
        let isEditable = preselectedPageId != nil
        return VStack(alignment: .leading, spacing: 0) {
            // Page title
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(note.intent.color)
                    .frame(width: 4, height: 18)
                if isEditable {
                    TextField("Title", text: $editableTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textFieldStyle(.plain)
                        .onChange(of: editableTitle) { _ in
                            savePageTitle(noteId: note.id)
                        }
                } else {
                    Text(note.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding(.bottom, 8)

            // Page body + sections + interstitials
            VStack(alignment: .leading, spacing: 0) {
                if isEditable {
                    if !editableBody.isEmpty || true {
                        TextField("Body", text: $editableBody, axis: .vertical)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textFieldStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 6)
                            .onChange(of: editableBody) { _ in
                                savePageBody(noteId: note.id)
                            }
                    }
                } else {
                    let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty {
                        Text(body)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 6)
                    }
                }

                let sections = cachedPageSections.filter { $0.deletedAt == nil }
                ForEach(sections) { section in
                    if isEditable {
                        editableSectionRow(for: section)
                    } else {
                        sectionRow(for: section)
                    }

                    // Interstitial text after this section
                    let interstitial = note.textAfterSection(section.id)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !interstitial.isEmpty {
                        Text(interstitial)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }

                // End interstitial
                let endText = note.endText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !endText.isEmpty {
                    Text(endText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            .padding(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func sectionRow(for section: Section) -> some View {
        let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let handleName = section.handleId
            .flatMap { HandleManager.shared.getHandle(id: $0) }
            .map { "@\($0.displayName)" }

        if section.sectionType == .fold {
            // Node / bubble style
            VStack(alignment: .leading, spacing: 4) {
                if let handleName {
                    Text(handleName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(section.intent.color)
                }

                if section.contentType == .checklist {
                    HStack(spacing: 4) {
                        Image(systemName: content.isEmpty ? "square" : "checkmark.square")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if !content.isEmpty {
                            Text(content)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                } else if !content.isEmpty {
                    Text(content)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(section.intent.backgroundTint))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 2)
        } else {
            // Line style — simple inline text
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(section.intent.color.opacity(0.5))
                    .frame(width: 2, height: 14)
                    .padding(.top, 2)

                if !content.isEmpty {
                    Text(content)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func editableSectionRow(for section: Section) -> some View {
        let handleName = section.handleId
            .flatMap { HandleManager.shared.getHandle(id: $0) }
            .map { "@\($0.displayName)" }

        let binding = Binding<String>(
            get: { editableSectionContents[section.id] ?? section.content },
            set: { editableSectionContents[section.id] = $0 }
        )

        if section.sectionType == .fold {
            // Node / bubble style — editable
            VStack(alignment: .leading, spacing: 4) {
                if let handleName {
                    Text(handleName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(section.intent.color)
                }

                TextField("Content", text: binding, axis: .vertical)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: binding.wrappedValue) { _ in
                        saveSectionContent(sectionId: section.id)
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(section.intent.backgroundTint))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 2)
        } else {
            // Line style — editable
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(section.intent.color.opacity(0.5))
                    .frame(width: 2, height: 14)
                    .padding(.top, 2)

                TextField("Content", text: binding, axis: .vertical)
                    .font(.caption)
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

    private func savePageTitle(noteId: String) {
        let title = editableTitle
        Task {
            try? await appState.noteRepository.updateNoteTitle(noteId, title: title.isEmpty ? nil : title)
        }
    }

    private func savePageBody(noteId: String) {
        let body = editableBody
        Task {
            try? await appState.noteRepository.updateNoteBody(noteId, body: body)
        }
    }

    private func saveSectionContent(sectionId: String) {
        guard let content = editableSectionContents[sectionId] else { return }
        Task {
            try? await appState.sectionRepository.updateContent(sectionId, content: content)
        }
    }

    // MARK: - Change History

    private var resolvedActions: [(action: SuggestedAction, timestamp: Date)] {
        messages.flatMap { message in
            message.actions
                .filter { action in
                    switch action.status {
                    case .accepted, .dismissed, .failed: return true
                    case .pending: return false
                    }
                }
                .map { (action: $0, timestamp: message.timestamp) }
        }
    }

    private var changeHistory: some View {
        let actions = resolvedActions
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHistoryExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text("HISTORY")
                        .font(.caption.weight(.semibold))
                    if !actions.isEmpty {
                        Text("\(actions.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                    }
                    Spacer()
                    Image(systemName: isHistoryExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isHistoryExpanded {
                if actions.isEmpty {
                    Text("No changes yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(actions.enumerated()), id: \.element.action.id) { index, item in
                            historyRow(action: item.action, timestamp: item.timestamp, isLast: index == actions.count - 1)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func historyRow(action: SuggestedAction, timestamp: Date, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Timeline
            VStack(spacing: 0) {
                Circle()
                    .fill(statusColor(for: action.status))
                    .frame(width: 8, height: 8)
                if !isLast {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: action.icon)
                        .font(.caption2)
                        .foregroundStyle(action.tintColor)
                    Text(action.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(statusLabel(for: action.status))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(statusColor(for: action.status))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, isLast ? 0 : 10)
        }
    }

    private func statusColor(for status: ActionStatus) -> Color {
        switch status {
        case .accepted: return .green
        case .dismissed: return .gray
        case .failed: return .red
        case .pending: return .yellow
        }
    }

    private func statusLabel(for status: ActionStatus) -> String {
        switch status {
        case .accepted: return "Applied"
        case .dismissed: return "Dismissed"
        case .failed(let reason): return "Failed: \(reason)"
        case .pending: return "Pending"
        }
    }

    // MARK: - Loop Selector

    private var loopSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            if handles.isEmpty {
                Text("No loops available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if let selectedHandle = selectedHandleIds.sorted().first.flatMap({ id in handles.first { $0.id == id } }) {
                loopRow(for: selectedHandle)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedHandleIds.removeAll()
                        editableContent = ""
                        editingHandleId = nil
                        contentHasUnsavedChanges = false
                        interactionMode = nil
                        messages.removeAll()
                    }
                } label: {
                    Label("Change loop", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(filteredHandles) { handle in
                    loopRow(for: handle)
                }
            }
        }
    }

    @ViewBuilder
    private func loopRow(for handle: Handle) -> some View {
        let isSelected = selectedHandleIds.contains(handle.id)
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                toggleHandle(handle)
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(handle.intent.color)
                    .frame(width: 4, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(handle.displayName)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    let preview = handle.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func toggleHandle(_ handle: Handle) {
        if selectedHandleIds.contains(handle.id) {
            selectedHandleIds.remove(handle.id)
        } else {
            savePendingEdits()
            selectedHandleIds.insert(handle.id)
        }

        // Reset mode when selection changes
        interactionMode = nil
        messages.removeAll()
        searchText = ""

        if let primary = primaryHandle {
            editableContent = primary.content
            editingHandleId = primary.id
            contentHasUnsavedChanges = false
        } else {
            editableContent = ""
            editingHandleId = nil
            contentHasUnsavedChanges = false
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Search pages and loops...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Focus Selector

    private var focusSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOCUS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(FocusMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            focusMode = mode
                            selectedHandleIds.removeAll()
                            selectedPageId = nil
                            cachedPageSections = []
                            editableContent = ""
                            editingHandleId = nil
                            contentHasUnsavedChanges = false
                            interactionMode = nil
                            messages.removeAll()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode == .pages ? "doc.text" : "link")
                                .font(.caption)
                            Text(mode.rawValue)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundColor(focusMode == mode ? .white : Color(.lightGray))
                        .background(focusMode == mode ? Color.accentColor : Color(red: 0.06, green: 0.06, blue: 0.06))
                        .overlay(
                            Capsule()
                                .strokeBorder(focusMode == mode ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Pages List

    private var pagesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedPage = pages.first(where: { $0.id == selectedPageId }) {
                pageRow(for: selectedPage)

                if preselectedPageId == nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedPageId = nil
                            cachedPageSections = []
                            selectedHandleIds.removeAll()
                            editableContent = ""
                            editingHandleId = nil
                            contentHasUnsavedChanges = false
                            interactionMode = nil
                            messages.removeAll()
                        }
                    } label: {
                        Label("Change page", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(filteredPages) { note in
                    pageRow(for: note)
                }
            }
        }
    }

    @ViewBuilder
    private func pageRow(for note: Note) -> some View {
        let isSelected = selectedPageId == note.id
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected && preselectedPageId == nil {
                    selectedPageId = nil
                    cachedPageSections = []
                    selectedHandleIds.removeAll()
                    editableContent = ""
                    editingHandleId = nil
                    contentHasUnsavedChanges = false
                    interactionMode = nil
                    messages.removeAll()
                } else if !isSelected {
                    selectedPageId = note.id
                    selectedHandleIds.removeAll()
                    editableContent = ""
                    editingHandleId = nil
                    contentHasUnsavedChanges = false
                    interactionMode = nil
                    messages.removeAll()
                    searchText = ""
                    loadSectionsForPage(note.id)
                }
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(note.intent.color)
                    .frame(width: 4, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    let preview = note.body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var loopsInPageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOOPS IN PAGE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pageHandles) { handle in
                        let isSelected = selectedHandleIds.contains(handle.id)
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                toggleHandle(handle)
                            }
                        } label: {
                            Text("@\(handle.displayName)")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(isSelected ? .white : handle.intent.color)
                                .background(isSelected ? handle.intent.color : .clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(handle.intent.color, lineWidth: 1.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 12) {
            modeButton(.edit, icon: "pencil.line", description: "Apply changes")
            modeButton(.chat, icon: "bubble.left.and.text.bubble.right", description: "Discuss content")
        }
        .padding(.top, 4)
    }

    private func modeButton(_ mode: InteractionMode, icon: String, description: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                interactionMode = mode
                messages.removeAll()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color(.lightGray))
                Text(mode.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.lightGray))
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(red: 0.06, green: 0.06, blue: 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func loadSectionsForPage(_ noteId: String) {
        Task {
            if let sections = try? await appState.sectionRepository.getSections(noteId: noteId) {
                await MainActor.run {
                    cachedPageSections = sections
                    // Populate editable section contents
                    var contents: [String: String] = [:]
                    for section in sections where section.deletedAt == nil {
                        contents[section.id] = section.content
                    }
                    editableSectionContents = contents
                }
            }
            // Populate editable title/body from the note
            if let note = appState.noteRepository.notes.first(where: { $0.id == noteId }) {
                let sections = cachedPageSections
                await MainActor.run {
                    editableTitle = note.displayTitle(sections: sections)
                    editableBody = note.body
                }
            }
        }
    }

    // MARK: - Chat Section

    private var chatSection: some View {
        VStack(spacing: 12) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { messageIndex, message in
                ChatMessageView(message: message)
                    .id(message.id)

                if message.role == .assistant {
                    ForEach(Array(message.actions.enumerated()), id: \.element.id) { actionIndex, action in
                        ActionCardView(
                            action: action,
                            onAccept: { acceptAction(messageIndex: messageIndex, actionIndex: actionIndex) },
                            onDismiss: { dismissAction(messageIndex: messageIndex, actionIndex: actionIndex) }
                        )
                    }
                }
            }
        }
    }

    private var loadingIndicator: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Thinking...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(
                interactionMode == .edit ? "Describe your changes..." : "Ask about this content...",
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
            .focused($isInputFocused)
            .lineLimit(1...4)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Color.accentColor : Color.gray.opacity(0.3))
                    .clipShape(Circle())
            }
            .disabled(!canSend)
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        savePendingEdits()

        // Build loop content if loops are selected
        let currentHandles = selectedHandles
        let loopContent: String
        if currentHandles.isEmpty {
            loopContent = ""
        } else {
            loopContent = currentHandles.map { handle in
                let content = handle.id == editingHandleId ? editableContent : handle.content
                let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                return "Loop: @\(handle.displayName) (id: \(handle.id))\nContent:\n\(cleaned.isEmpty ? "(empty)" : cleaned)"
            }.joined(separator: "\n\n---\n\n")
        }

        // Build page context if a page is selected
        let pageContext: String
        if let pageId = selectedPageId,
           let page = pages.first(where: { $0.id == pageId }) {
            let body = page.body.trimmingCharacters(in: .whitespacesAndNewlines)
            var parts: [String] = []
            parts.append("Focused page (id: \(page.id)): \"\(page.displayTitle)\"")
            parts.append("Body: \(body.isEmpty ? "(empty — user wants you to generate content here)" : String(body.prefix(500)))")

            // Include section content for the focused page with IDs and types
            let activeSections = cachedPageSections.filter { $0.deletedAt == nil }
            let sectionTexts = activeSections
                .prefix(20)
                .compactMap { section -> String? in
                    let cleaned = Self.cleanContentForAI(section.content)
                    guard !cleaned.isEmpty else { return nil }
                    let type = section.sectionType == .fold ? "node" : "line"
                    let handleInfo: String
                    if let hId = section.handleId,
                       let h = HandleManager.shared.getHandle(id: hId) {
                        handleInfo = ", loop: @\(h.displayName)"
                    } else {
                        handleInfo = ""
                    }
                    return "  Section (id: \(section.id), type: \(type)\(handleInfo)): \(cleaned)"
                }
            if !sectionTexts.isEmpty {
                parts.append("Sections:\n\(sectionTexts.joined(separator: "\n"))")
            } else if body.isEmpty {
                parts.append("This page is completely blank. When the user asks you to write or create content, use the update_page_body tool with note_id \"\(page.id)\" and note_title \"\(page.displayTitle)\" to generate the content they request.")
            }

            pageContext = parts.joined(separator: "\n")
        } else {
            pageContext = ""
        }

        messages.append(ChatMessage(role: .user, content: text))
        inputText = ""
        isLoading = true

        let currentMode = interactionMode ?? .edit

        Task {
            do {
                let apiMessages = buildAPIMessages()
                let richContext = await buildRichContext(for: text)

                var contextParts: [String] = []
                contextParts.append(richContext)
                if !pageContext.isEmpty { contextParts.append(pageContext) }
                if !loopContent.isEmpty { contextParts.append("Selected loop content:\n\n\(loopContent)") }
                let context = contextParts.joined(separator: "\n\n")

                switch currentMode {
                case .edit:
                    let response = try await ClaudeService.sendWithTools(
                        messages: apiMessages,
                        noteContext: context
                    )

                    let content = response.text.isEmpty && !response.actions.isEmpty
                        ? "Here's what I suggest:"
                        : response.text
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: content,
                        actions: response.actions
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
                    errorMessage = "The AI edge function returned 404. Make sure the ai-proxy function is deployed:\n\n`supabase functions deploy ai-proxy`\n\nand that ANTHROPIC_API_KEY is set in your Supabase project secrets."
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

    // MARK: - Content Persistence

    private func savePendingEdits() {
        guard contentHasUnsavedChanges, let handleId = editingHandleId else { return }
        let content = editableContent
        contentHasUnsavedChanges = false
        Task {
            try? await HandleManager.shared.updateContent(handleId: handleId, content: content)
        }
    }

    // MARK: - Context Builder

    /// Strip non-readable content (base64 RTF, encoded data) from text
    private static func cleanContentForAI(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Skip base64-encoded RTF blobs
        if trimmed.hasPrefix("e]") || trimmed.hasPrefix("ew0") || trimmed.hasPrefix("eyJ") ||
           trimmed.contains("{\\rtf") || trimmed.contains("\\fonttbl") {
            return ""
        }
        return String(trimmed.prefix(300))
    }

    private func buildRichContext(for query: String) async -> String {
        var parts: [String] = []

        let notes = appState.noteRepository.notes.filter { !$0.isDeleted }

        // Full project content — include note bodies and section content
        // so the AI can see the entire project, not just loops.
        var noteDetails: [String] = []
        for note in notes.prefix(25) {
            let title = note.displayTitle
            let intent = note.intent.rawValue
            let body = Self.cleanContentForAI(note.body)

            var noteEntry = "Page: \"\(title)\" (intent: \(intent))"
            if !body.isEmpty {
                noteEntry += "\n  Body: \(body)"
            }

            // Include section content
            if let sections = try? await appState.sectionRepository.getSections(noteId: note.id) {
                let textSections = sections
                    .filter { $0.contentType == .text || $0.contentType == .checklist || $0.contentType == .quote }
                    .prefix(8)
                var sectionPreviews: [String] = []
                for section in textSections {
                    let cleaned = Self.cleanContentForAI(section.content)
                    guard !cleaned.isEmpty else { continue }
                    let handleTag = section.handleId
                        .flatMap { HandleManager.shared.getHandle(id: $0) }
                        .map { "@\($0.displayName): " } ?? ""
                    sectionPreviews.append("    \(handleTag)\(cleaned)")
                }
                if !sectionPreviews.isEmpty {
                    noteEntry += "\n  Sections:\n\(sectionPreviews.joined(separator: "\n"))"
                }
            }

            // Include interstitial content
            let interstitials = note.interstitialContent.values
                .map { Self.cleanContentForAI($0) }
                .filter { !$0.isEmpty }
                .prefix(3)
            if !interstitials.isEmpty {
                noteEntry += "\n  Between sections: \(interstitials.joined(separator: " | "))"
            }

            noteDetails.append(noteEntry)
        }

        if !noteDetails.isEmpty {
            let header = "Project pages (\(notes.count) total):"
            parts.append("\(header)\n\n\(noteDetails.joined(separator: "\n\n"))")
        }

        // All loops with their content
        let allHandles = HandleManager.shared.handles
        if !allHandles.isEmpty {
            let loopDetails = allHandles.prefix(20).map { handle in
                let preview = Self.cleanContentForAI(handle.content)
                let suffix = preview.isEmpty ? " (empty)" : "\n  Content: \(preview)"
                return "  @\(handle.displayName) (\(handle.intent.rawValue))\(suffix)"
            }
            parts.append("Project loops (\(allHandles.count) total):\n\(loopDetails.joined(separator: "\n"))")
        }

        return parts.joined(separator: "\n\n")
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
                    case .accepted:
                        return "[\(action.toolName) was accepted and executed]"
                    case .dismissed:
                        return "[\(action.toolName) was dismissed by user]"
                    case .failed(let reason):
                        return "[\(action.toolName) failed: \(reason)]"
                    case .pending:
                        return nil
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

    // MARK: - Action Handlers

    private func acceptAction(messageIndex: Int, actionIndex: Int) {
        guard messageIndex < messages.count,
              actionIndex < messages[messageIndex].actions.count else { return }

        let action = messages[messageIndex].actions[actionIndex]
        guard action.status == .pending else { return }

        Task {
            do {
                try await action.execute(appState: appState)

                // If this was a loop content update, refresh the editor
                if case .updateLoopContent(let p) = action.actionType,
                   p.handleId == editingHandleId {
                    editableContent = p.newContent
                    contentHasUnsavedChanges = false
                }

                // If a section was deleted, refresh the cached sections
                if case .deleteSection = action.actionType,
                   let pageId = selectedPageId {
                    loadSectionsForPage(pageId)
                }

                messages[messageIndex].actions[actionIndex] = action.withStatus(.accepted)
                haptic(.success)
            } catch {
                messages[messageIndex].actions[actionIndex] = action.withStatus(.failed(error.localizedDescription))
                haptic(.error)
            }
        }
    }

    private func dismissAction(messageIndex: Int, actionIndex: Int) {
        guard messageIndex < messages.count,
              actionIndex < messages[messageIndex].actions.count else { return }

        let action = messages[messageIndex].actions[actionIndex]
        guard action.status == .pending else { return }

        messages[messageIndex].actions[actionIndex] = action.withStatus(.dismissed)
        haptic(.light)
    }

    // MARK: - Haptics

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

#Preview {
    let appState = AppState()
    NavigationStack {
        IntelligenceView()
            .environmentObject(appState.insightRepository)
    }
    .environmentObject(appState)
}
