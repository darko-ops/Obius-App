import SwiftUI

enum WorkspaceAction: String, CaseIterable, Identifiable {
    case summarize = "Summarize"
    case refine = "Refine"
    case compare = "Compare"
    case freeform = "Free-form"

    var id: Self { self }

    var icon: String {
        switch self {
        case .summarize: return "doc.text"
        case .refine: return "pencil.and.outline"
        case .compare: return "arrow.left.arrow.right"
        case .freeform: return "text.bubble"
        }
    }
}

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
    @State private var activeCategorySheet: InsightType?

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

                    if !upcomingEchoInsights.isEmpty {
                        upcomingEchoesSection
                    }

                    if !categoryGroups.isEmpty {
                        categoriesSection
                    }

                    if upcomingEchoInsights.isEmpty
                        && categoryGroups.isEmpty
                        && insightsInModule(insightRepository.trackedInsights).isEmpty
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

    // MARK: - Upcoming Echoes

    private var upcomingEchoInsights: [Insight] {
        insightsInModule(insightRepository.surfacedInsights).filter { $0.insightType == .upcomingEcho }
    }

    private var upcomingEchoesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UPCOMING ECHOES")
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

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INSIGHTS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(categoryGroups, id: \.type) { group in
                CategoryCardView(
                    insightType: group.type,
                    insights: group.insights,
                    onTap: {
                        activeCategorySheet = group.type
                    }
                )
            }
        }
    }

    // MARK: - Tracked

    private var trackedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRACKING")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(insightsInModule(insightRepository.trackedInsights)) { insight in
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

                    // + button at the end of the row
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
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
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
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
        await insightEngine.scan()
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
                    .background(message.role == .user ? Color.accentColor : Color.gray.opacity(0.15))
                    .foregroundStyle(message.role == .user ? .white : .primary)
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

    @State private var selectedHandleIds: Set<String> = []
    @State private var selectedAction: WorkspaceAction = .summarize
    @State private var editableContent = ""
    @State private var editingHandleId: String?
    @State private var contentHasUnsavedChanges = false
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    private var selectedHandles: [Handle] {
        handles.filter { selectedHandleIds.contains($0.id) }
    }

    private var primaryHandle: Handle? {
        guard let firstId = selectedHandleIds.sorted().first else { return nil }
        return handles.first { $0.id == firstId }
    }

    private var isCompareDisabled: Bool {
        selectedHandleIds.count < 2
    }

    private var canSend: Bool {
        guard !selectedHandleIds.isEmpty else { return false }
        guard !isLoading else { return false }
        if selectedAction == .freeform {
            return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Loop content editor
                        if let handle = primaryHandle {
                            loopContentEditor(for: handle)
                        }

                        // Loop chip selector
                        loopSelector

                        // Action picker
                        actionPicker

                        // Chat messages
                        if !messages.isEmpty {
                            chatSection
                        }

                        if isLoading {
                            loadingIndicator
                        }
                    }
                    .padding()
                }

                // Input bar pinned at bottom
                inputBar
            }
            .navigationTitle("Workspace")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onChange(of: editableContent) {
                    if editingHandleId == handle.id {
                        contentHasUnsavedChanges = true
                    }
                }
        }
    }

    // MARK: - Loop Selector

    private var loopSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOOPS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if handles.isEmpty {
                Text("No loops available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(handles) { handle in
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
    }

    private func toggleHandle(_ handle: Handle) {
        let isSelected = selectedHandleIds.contains(handle.id)

        if isSelected {
            selectedHandleIds.remove(handle.id)
        } else {
            // Save pending edits before switching
            savePendingEdits()
            selectedHandleIds.insert(handle.id)
        }

        if selectedAction == .compare && selectedHandleIds.count < 2 {
            selectedAction = .summarize
        }

        // Load the new primary handle's content
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

    // MARK: - Action Picker

    private var actionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTION")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(WorkspaceAction.allCases), id: \.rawValue) { (action: WorkspaceAction) in
                        actionPill(for: action)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionPill(for action: WorkspaceAction) -> some View {
        let isSelected = selectedAction == action
        let isDisabled = action == .compare && isCompareDisabled

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedAction = action
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: action.icon)
                    .font(.caption)
                Text(action.rawValue)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundColor(isDisabled ? Color.gray : isSelected ? Color.white : Color.primary)
            .background(isSelected && !isDisabled ? Color.accentColor : Color.gray.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
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
                selectedAction == .freeform ? "Ask about your loops..." : "Additional instructions...",
                text: $inputText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
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
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        // Save any pending content edits so AI sees latest
        savePendingEdits()

        // Build loop content — use editableContent for the primary handle since
        // the handles array is a snapshot and won't reflect edits.
        // Include handle IDs so the AI can reference them in tool calls.
        let currentHandles = selectedHandles
        let loopContent = currentHandles.map { handle in
            let content: String
            if handle.id == editingHandleId {
                content = editableContent
            } else {
                content = handle.content
            }
            let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Loop: @\(handle.displayName) (id: \(handle.id))\nContent:\n\(cleaned.isEmpty ? "(empty)" : cleaned)"
        }.joined(separator: "\n\n---\n\n")

        // Build user-facing message
        let userText: String
        let handleNames = currentHandles.map { "@\($0.displayName)" }.joined(separator: ", ")
        switch selectedAction {
        case .summarize:
            userText = text.isEmpty ? "Summarize: \(handleNames)" : "Summarize: \(handleNames)\n\n\(text)"
        case .refine:
            userText = text.isEmpty ? "Refine: \(handleNames)" : "Refine: \(handleNames)\n\n\(text)"
        case .compare:
            userText = text.isEmpty ? "Compare: \(handleNames)" : "Compare: \(handleNames)\n\n\(text)"
        case .freeform:
            userText = text
        }

        messages.append(ChatMessage(role: .user, content: userText))
        inputText = ""
        isLoading = true

        // Build prompt for Claude
        let prompt: String
        switch selectedAction {
        case .summarize:
            let extra = text.isEmpty ? "" : "\n\nAdditional instructions: \(text)"
            prompt = "Summarize the following loops:\n\n\(loopContent)\(extra)"
        case .refine:
            let extra = text.isEmpty ? "" : "\n\nAdditional instructions: \(text)"
            prompt = "Refine and improve the content of these loops:\n\n\(loopContent)\(extra)"
        case .compare:
            let extra = text.isEmpty ? "" : "\n\nAdditional instructions: \(text)"
            prompt = "Compare these loops — highlight similarities, differences, and connections:\n\n\(loopContent)\(extra)"
        case .freeform:
            prompt = text
        }

        Task {
            do {
                let apiMessages = buildAPIMessages()
                // Always include loop content so the AI can see it
                let richContext = await buildRichContext(for: selectedAction == .freeform ? text : prompt)
                let context = "Loop content:\n\n\(loopContent)\n\n\(richContext)"

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

        let notes = appState.noteRepository.notes
        var matchedSections: [Section] = []
        if let results = try? await appState.sectionRepository.searchSections(query: query) {
            matchedSections = Array(results.prefix(8))
        }

        if !matchedSections.isEmpty {
            var snippets: [String] = []
            for section in matchedSections {
                let noteTitle = notes.first(where: { $0.id == section.noteId })?.displayTitle ?? "Untitled"
                let cleaned = Self.cleanContentForAI(section.content)
                guard !cleaned.isEmpty else { continue }
                snippets.append("  \"\(noteTitle)\": \(cleaned)")
            }
            if !snippets.isEmpty {
                parts.append("Related notes:\n\(snippets.joined(separator: "\n"))")
            }
        } else {
            let keywords = query.lowercased()
                .split(separator: " ")
                .filter { $0.count > 2 }
                .map(String.init)

            if !keywords.isEmpty {
                var snippets: [String] = []
                for note in notes.prefix(20) {
                    let body = note.body.lowercased()
                    if keywords.contains(where: { body.contains($0) }) {
                        let title = note.displayTitle
                        let cleaned = Self.cleanContentForAI(note.body)
                        guard !cleaned.isEmpty else { continue }
                        snippets.append("  \"\(title)\": \(cleaned)")
                    }
                    if snippets.count >= 8 { break }
                }
                if !snippets.isEmpty {
                    parts.append("Related notes:\n\(snippets.joined(separator: "\n"))")
                }
            }
        }

        // Workspace overview — human-readable, no raw IDs
        let noteNames = notes.prefix(15).map { "  - \($0.displayTitle) (\($0.intent.rawValue))" }
        parts.append("Your notes (\(notes.count) total):\n\(noteNames.joined(separator: "\n"))")

        let allHandles = HandleManager.shared.handles
        if !allHandles.isEmpty {
            let loopNames = allHandles.prefix(20).map { handle in
                let preview = Self.cleanContentForAI(handle.content)
                let suffix = preview.isEmpty ? "" : " — \(String(preview.prefix(60)))"
                return "  - @\(handle.displayName) (\(handle.intent.rawValue))\(suffix)"
            }
            parts.append("Your loops (\(allHandles.count) total):\n\(loopNames.joined(separator: "\n"))")
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
