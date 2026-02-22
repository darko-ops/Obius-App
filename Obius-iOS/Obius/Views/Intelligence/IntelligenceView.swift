import SwiftUI

struct IntelligenceView: View {
    @EnvironmentObject var appState: AppState
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    @State private var isScanning = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Surfaced insight cards
                    if !appState.insightRepository.surfacedInsights.isEmpty {
                        surfacedSection
                    }

                    // Tracked insights (pinned)
                    if !appState.insightRepository.trackedInsights.isEmpty {
                        trackedSection
                    }

                    // Empty state when nothing exists
                    if appState.insightRepository.surfacedInsights.isEmpty
                        && appState.insightRepository.trackedInsights.isEmpty
                        && messages.isEmpty {
                        emptyState
                    }

                    // Chat messages
                    if !messages.isEmpty {
                        chatSection
                    }
                }
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
                    Task { await scanForInsights() }
                } label: {
                    if isScanning {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                    }
                }
                .disabled(isScanning)
            }
        }
        .task {
            // Auto-scan on first appearance if no insights exist
            if appState.insightRepository.surfacedInsights.isEmpty
                && appState.insightRepository.trackedInsights.isEmpty {
                await scanForInsights()
            }
        }
    }

    // MARK: - Surfaced Insights

    private var surfacedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("New Insights")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(appState.insightRepository.surfacedInsights.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)

            ForEach(appState.insightRepository.surfacedInsights) { insight in
                InsightCardView(
                    insight: insight,
                    onTrack: {
                        Task { try? await appState.insightRepository.trackInsight(insight.id) }
                        HapticFeedback.selection()
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            Task { try? await appState.insightRepository.dismissInsight(insight.id) }
                        }
                        HapticFeedback.light()
                    },
                    onTap: {
                        navigateToSource(insight)
                    }
                )
                .padding(.horizontal)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Tracked Insights

    private var trackedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Tracked")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            ForEach(appState.insightRepository.trackedInsights) { insight in
                TrackedInsightRow(
                    insight: insight,
                    onTap: {
                        navigateToSource(insight)
                    },
                    onUntrack: {
                        Task { try? await appState.insightRepository.untrackInsight(insight.id) }
                    }
                )
                .padding(.horizontal)
            }

            Divider()
                .padding(.horizontal)
                .padding(.top, 4)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 80)

            Image(systemName: "brain")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Intelligence")
                .font(.title2.weight(.semibold))

            Text("Insights about your notes will appear here. I detect tasks, questions, connections, and patterns in your content.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Scanning your notes...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 8)
            }

            Spacer()
                .frame(height: 80)
        }
    }

    // MARK: - Chat Section

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !appState.insightRepository.surfacedInsights.isEmpty
                || !appState.insightRepository.trackedInsights.isEmpty {
                HStack {
                    Text("Chat")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }

            ForEach(messages) { message in
                ChatMessageView(message: message)
                    .padding(.horizontal)
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
        .padding(.bottom, 16)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask about your notes...", text: $messageText, axis: .vertical)
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

    private func scanForInsights() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let engine = InsightEngine(
            noteRepository: appState.noteRepository,
            sectionRepository: appState.sectionRepository,
            handleRepository: appState.handleRepository,
            insightRepository: appState.insightRepository,
            database: appState.database
        )
        await engine.scan()
    }

    private func navigateToSource(_ insight: Insight) {
        // TODO: Navigate to the source note/section when tapped
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

// MARK: - Haptic Helpers

private enum HapticFeedback {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

#Preview {
    NavigationStack {
        IntelligenceView()
    }
    .environmentObject(AppState())
}
