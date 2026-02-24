import SwiftUI

struct IntelligenceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var insightRepository: InsightRepository
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    @State private var isScanning = false
    @State private var selectedInsight: Insight?
    @State private var showCreateSheet = false
    @State private var navigateToNote: Note?
    @State private var navigateSectionId: String?
    @State private var pendingGoToNoteId: String?
    @State private var pendingGoToSectionId: String?
    @State private var insightFilter: String = "All"
    @FocusState private var isInputFocused: Bool

    private var insightEngine: InsightEngine {
        InsightEngine(
            noteRepository: appState.noteRepository,
            sectionRepository: appState.sectionRepository,
            handleRepository: appState.handleRepository,
            insightRepository: insightRepository,
            database: appState.database
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Tracked section (always visible for + button)
                    trackedSection

                    // Upcoming Echoes section
                    if !upcomingEchoInsights.isEmpty {
                        upcomingEchoesSection
                    }

                    // New Insights section (excludes upcoming echoes)
                    if !nonEchoSurfacedInsights.isEmpty {
                        insightsSection
                    }

                    // Empty state (when no insights and no chat)
                    if insightRepository.surfacedInsights.isEmpty
                        && insightRepository.trackedInsights.isEmpty
                        && messages.isEmpty
                        && !isScanning {
                        emptyState
                    }

                    // Chat messages
                    if !messages.isEmpty {
                        chatSection
                    }

                    if isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Thinking...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }

            inputBar
        }
        .navigationTitle("Intelligence")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Image("ObiusLogo")
                    .renderingMode(.original)
            }
        }
        .sheet(item: $selectedInsight, onDismiss: {
            if let noteId = pendingGoToNoteId,
               let note = appState.noteRepository.notes.first(where: { $0.id == noteId }) {
                navigateSectionId = pendingGoToSectionId
                navigateToNote = note
            }
            pendingGoToNoteId = nil
            pendingGoToSectionId = nil
        }) { insight in
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
                onDeleteNote: insight.insightType == .nonsenseContent ? {
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
        .sheet(isPresented: $showCreateSheet) {
            CreateInsightSheet { title, body in
                Task {
                    try? await insightRepository.createInsight(
                        type: .suggestedTask,
                        title: title,
                        body: body,
                        status: .tracked
                    )
                    haptic(.success)
                }
            }
        }
        .task {
            await runScan()
        }
        .onChange(of: insightRepository.surfacedInsights) {
            if insightFilter != "All" && filteredInsights.isEmpty {
                withAnimation { insightFilter = "All" }
            }
        }
        .navigationDestination(item: $navigateToNote) { note in
            NoteEditorView(noteId: note.id, targetSectionId: navigateSectionId)
        }
    }

    // MARK: - Upcoming Echoes

    private var upcomingEchoInsights: [Insight] {
        insightRepository.surfacedInsights.filter { $0.insightType == .upcomingEcho }
    }

    private var nonEchoSurfacedInsights: [Insight] {
        insightRepository.surfacedInsights.filter { $0.insightType != .upcomingEcho }
    }

    private var availableFilters: [(label: String, color: Color)] {
        var seen = Set<String>()
        var filters: [(label: String, color: Color)] = []
        for insight in nonEchoSurfacedInsights {
            let label = insight.displayLabel
            if seen.insert(label).inserted {
                filters.append((label: label, color: insight.displayTint.color))
            }
        }
        filters.sort { $0.label < $1.label }
        return filters
    }

    private var filteredInsights: [Insight] {
        if insightFilter == "All" { return nonEchoSurfacedInsights }
        return nonEchoSurfacedInsights.filter { $0.displayLabel == insightFilter }
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

    // MARK: - New Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Insights")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // "All" filter
                    let allSelected = insightFilter == "All"
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            insightFilter = "All"
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(allSelected ? Color.primary : .clear)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary, lineWidth: 1.5)
                                )
                                .frame(width: 10, height: 10)
                            Text("All")
                                .font(.caption.weight(allSelected ? .semibold : .regular))
                                .foregroundStyle(allSelected ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    // Dynamic filters from actual insight types
                    ForEach(availableFilters, id: \.label) { filter in
                        let isSelected = insightFilter == filter.label
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                insightFilter = filter.label
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(isSelected ? filter.color : .clear)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(filter.color, lineWidth: 1.5)
                                    )
                                    .frame(width: 10, height: 10)
                                Text(filter.label)
                                    .font(.caption.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? filter.color : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ForEach(filteredInsights) { insight in
                InsightCardView(
                    insight: insight,
                    onTrack: {
                        Task {
                            try? await insightRepository.trackInsight(insight.id)
                            haptic(.success)
                        }
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            Task {
                                try? await insightRepository.dismissInsight(insight.id)
                            }
                        }
                        haptic(.light)
                    },
                    onTap: {
                        selectedInsight = insight
                    },
                    onDeleteNote: insight.insightType == .nonsenseContent ? {
                        Task {
                            if let noteId = insight.sourceNoteId {
                                try? await appState.noteRepository.deleteNote(noteId)
                                try? await insightRepository.dismissInsight(insight.id)
                                haptic(.success)
                            }
                        }
                    } : nil
                )
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
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
                    ForEach(insightRepository.trackedInsights) { insight in
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

    // MARK: - Chat

    private var chatSection: some View {
        VStack(spacing: 12) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { messageIndex, message in
                ChatMessageView(message: message)
                    .id(message.id)

                // Render action cards after assistant messages
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

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask a question...", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isInputFocused)
                .lineLimit(1...5)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .accentColor)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Actions

    private func navigateToInsightSource(_ insight: Insight) {
        if let noteId = insight.sourceNoteId,
           let note = appState.noteRepository.notes.first(where: { $0.id == noteId }) {
            navigateSectionId = insight.sourceSectionId
            navigateToNote = note
        } else {
            selectedInsight = insight
        }
    }

    private func resolveReferences(for insight: Insight) -> [InsightReference] {
        var refs: [InsightReference] = []

        // Concept clusters store the tag in sourceSectionId — resolve all notes sharing that tag
        if insight.insightType == .conceptCluster, let tag = insight.sourceSectionId {
            let tagLower = tag.lowercased()
            for note in appState.noteRepository.notes where !note.isDeleted {
                if note.tags.contains(where: { $0.lowercased() == tagLower }) {
                    refs.append(InsightReference(noteId: note.id, title: note.displayTitle, sectionId: nil))
                }
            }
            return refs
        }

        if let noteId = insight.sourceNoteId,
           let note = appState.noteRepository.notes.first(where: { $0.id == noteId }) {
            // For AI insights, sourceSectionId is the subtype string — not a real section.
            // For loop insights, sourceSectionId stores handle IDs — also not a real section.
            let nonSectionTypes: Set<InsightType> = [.aiSuggestion, .activeLoop, .dormantLoop, .emergingLoop, .loopConnection, .lonelyHandle, .conceptCluster, .suggestedEcho]
            let sectionId = nonSectionTypes.contains(insight.insightType) ? nil : insight.sourceSectionId
            refs.append(InsightReference(noteId: noteId, title: note.displayTitle, sectionId: sectionId))
        }
        // relatedNoteId may contain comma-separated IDs for multi-reference insights
        // (but not for suggestedEcho, where it stores JSON config)
        if insight.insightType != .suggestedEcho, let relatedField = insight.relatedNoteId {
            let relatedIds = relatedField.split(separator: ",").map(String.init)
            for relatedId in relatedIds {
                if let note = appState.noteRepository.notes.first(where: { $0.id == relatedId }) {
                    refs.append(InsightReference(noteId: relatedId, title: note.displayTitle, sectionId: nil))
                }
            }
        }

        // For AI suggestions, scan title/body for note titles that weren't captured
        // in sourceNoteId or relatedNoteId (handles older insights and multi-reference gaps)
        if insight.insightType == .aiSuggestion {
            let searchText = insight.title + " " + insight.body
            let existingIds = Set(refs.map(\.noteId))
            for note in appState.noteRepository.notes where !note.isDeleted {
                guard !existingIds.contains(note.id) else { continue }
                let noteTitle = note.displayTitle
                guard noteTitle.count >= 4 else { continue }
                guard noteTitle.lowercased() != "untitled" else { continue }
                if searchText.localizedCaseInsensitiveContains(noteTitle) {
                    refs.append(InsightReference(noteId: note.id, title: noteTitle, sectionId: nil))
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

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        messageText = ""
        isLoading = true

        Task {
            do {
                let apiMessages = buildAPIMessages()
                let context = await buildRichContext(for: text)

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
                messages.append(ChatMessage(
                    role: .assistant,
                    content: "Something went wrong: \(error.localizedDescription)"
                ))
            }
            isLoading = false
        }
    }

    // MARK: - Context Builder

    private func buildRichContext(for query: String) async -> String {
        var parts: [String] = []

        // Part A — Relevant content via FTS5 search
        let notes = appState.noteRepository.notes
        var matchedSections: [Section] = []
        if let results = try? await appState.sectionRepository.searchSections(query: query) {
            matchedSections = Array(results.prefix(8))
        }

        if !matchedSections.isEmpty {
            let snippetLines = matchedSections.map { section -> String in
                let noteTitle = notes.first(where: { $0.id == section.noteId })?.title
                    ?? notes.first(where: { $0.id == section.noteId })?.aiTitle
                    ?? "Untitled"
                let content = String(section.content.prefix(300))
                return "  From \"\(noteTitle)\": \(content)"
            }
            parts.append("Relevant content:\n\(snippetLines.joined(separator: "\n"))")
        } else {
            // Fallback: scan note bodies for any keyword overlap
            let keywords = query.lowercased()
                .split(separator: " ")
                .filter { $0.count > 2 }
                .map(String.init)

            if !keywords.isEmpty {
                var fallbackLines: [String] = []
                for note in notes.prefix(20) {
                    let body = note.body.lowercased()
                    if keywords.contains(where: { body.contains($0) }) {
                        let title = note.title ?? note.aiTitle ?? "Untitled"
                        let snippet = String(note.body.prefix(300))
                        fallbackLines.append("  From \"\(title)\": \(snippet)")
                    }
                    if fallbackLines.count >= 8 { break }
                }
                if !fallbackLines.isEmpty {
                    parts.append("Relevant content:\n\(fallbackLines.joined(separator: "\n"))")
                }
            }
        }

        // Part B — Workspace overview
        let noteLines = notes.prefix(15).map { note in
            let title = note.title ?? note.aiTitle ?? "Untitled"
            return "  - id: \(note.id), title: \(title), intent: \(note.intent.rawValue)"
        }
        parts.append("Notes (\(notes.count) total):\n\(noteLines.joined(separator: "\n"))")

        let handles = HandleManager.shared.handles
        if !handles.isEmpty {
            let handleLines = handles.prefix(20).map { handle in
                return "  - id: \(handle.id), @\(handle.displayName), intent: \(handle.intent.rawValue)"
            }
            parts.append("Handles (\(handles.count) total):\n\(handleLines.joined(separator: "\n"))")
        }


        return parts.joined(separator: "\n\n")
    }

    // MARK: - API Message Builder

    private func buildAPIMessages() -> [ClaudeService.Message] {
        var apiMessages: [ClaudeService.Message] = []

        for message in messages {
            // Send text content for both roles
            apiMessages.append(ClaudeService.Message(
                role: message.role == .user ? "user" : "assistant",
                content: message.content
            ))

            // For assistant messages with resolved actions, append status as a user message
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


#Preview {
    let appState = AppState()
    NavigationStack {
        IntelligenceView()
            .environmentObject(appState.insightRepository)
    }
    .environmentObject(appState)
}
