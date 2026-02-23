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

                    // New Insights section
                    if !insightRepository.surfacedInsights.isEmpty {
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
        .sheet(item: $selectedInsight) { insight in
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
                onGoToNote: insight.sourceNoteId != nil ? {
                    if let note = appState.noteRepository.notes.first(where: { $0.id == insight.sourceNoteId }) {
                        navigateSectionId = insight.sourceSectionId
                        navigateToNote = note
                    }
                } : nil
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
        .navigationDestination(item: $navigateToNote) { note in
            NoteEditorView(noteId: note.id, targetSectionId: navigateSectionId)
        }
    }

    // MARK: - New Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Insights")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(insightRepository.surfacedInsights) { insight in
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
            ForEach(messages) { message in
                ChatMessageView(message: message)
                    .id(message.id)
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
        .background(.bar)
    }

    // MARK: - Actions

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
                let apiMessages = messages.map {
                    ClaudeService.Message(
                        role: $0.role == .user ? "user" : "assistant",
                        content: $0.content
                    )
                }

                let notes = appState.noteRepository.notes
                let recentTitles = notes.prefix(10).compactMap(\.title).joined(separator: ", ")
                let context = "Total notes: \(notes.count). Recent: \(recentTitles)"

                let reply = try await ClaudeService.send(
                    messages: apiMessages,
                    noteContext: context
                )

                messages.append(ChatMessage(role: .assistant, content: reply))
            } catch {
                messages.append(ChatMessage(
                    role: .assistant,
                    content: "Something went wrong: \(error.localizedDescription)"
                ))
            }
            isLoading = false
        }
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
    let timestamp = Date()

    enum MessageRole {
        case user
        case assistant
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
