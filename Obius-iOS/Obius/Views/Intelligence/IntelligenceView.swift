import SwiftUI

struct IntelligenceView: View {
    @EnvironmentObject var appState: AppState
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            inputBar
        }
        .navigationTitle("Obius")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "brain")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Intelligence : Architecture")
                .font(.title2.weight(.semibold))

            Text("I can help you explore your notes, generate ideas, and answer questions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        ChatMessageView(message: message)
                            .id(message.id)
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
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
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
        .background(.bar)
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        messageText = ""
        isLoading = true

        // TODO: Integrate with actual AI backend
        // For now, show a placeholder response
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

#Preview {
    NavigationStack {
        IntelligenceView()
    }
    .environmentObject(AppState())
}
