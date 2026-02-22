import SwiftUI

struct IntelligenceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var insightRepository: InsightRepository
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    @State private var isScanning = false
    @State private var hasScannedOnce = false
    @State private var selectedInsight: Insight?
    @State private var showCreateSheet = false
    @State private var insightToDelete: Insight?
    @State private var showDeleteConfirmation = false
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await runScan() }
                } label: {
                    if isScanning {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isScanning)
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
                onDelete: insight.insightType == .nonsenseContent ? {
                    selectedInsight = nil
                    insightToDelete = insight
                    showDeleteConfirmation = true
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
        .alert("Delete Page?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                guard let insight = insightToDelete, let noteId = insight.sourceNoteId else { return }
                Task {
                    try? await appState.noteRepository.deleteNote(noteId)
                    try? await insightRepository.dismissInsight(insight.id)
                    haptic(.success)
                }
                insightToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                insightToDelete = nil
            }
        } message: {
            Text("This will delete the page and all its sections. This action can't be undone easily.")
        }
        .task {
            // Auto-scan on first appearance if no insights exist
            if !hasScannedOnce
                && insightRepository.surfacedInsights.isEmpty
                && insightRepository.trackedInsights.isEmpty {
                await runScan()
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
                    onDelete: insight.insightType == .nonsenseContent ? {
                        insightToDelete = insight
                        showDeleteConfirmation = true
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
            HStack {
                Text("TRACKING")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

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

            Text("Insights about your notes will appear here. Tap refresh to scan for tasks, questions, and patterns.")
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
        hasScannedOnce = true
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        messageText = ""
        isLoading = true

        // TODO: Integrate with actual AI backend
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let response = ChatMessage(
                role: .assistant,
                content: "I'm not connected to an AI backend yet. This is a placeholder response. Once connected, I'll be able to help you explore your notes and answer questions!"
            )
            messages.append(response)
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
