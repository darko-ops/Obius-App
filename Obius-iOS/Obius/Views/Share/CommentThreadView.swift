import SwiftUI

struct CommentThreadView: View {
    let comments: [SharedComment]
    let isAuthenticated: Bool
    let onAddComment: (String) async -> Void

    @State private var newCommentBody = ""
    @State private var isSending = false
    @FocusState private var isCommentFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Comments")
                    .font(.headline)

                if !comments.isEmpty {
                    Text("\(comments.count)")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            // Comment list
            if comments.isEmpty {
                Text("No comments yet. Be the first to respond.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(comments) { comment in
                    CommentRow(comment: comment)
                }
            }

            // Input
            if isAuthenticated {
                commentInput
            } else {
                Text("Sign in to leave a comment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var commentInput: some View {
        HStack(spacing: 8) {
            TextField("Add a comment...", text: $newCommentBody, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($isCommentFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            isCommentFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                    }
                }

            Button {
                Task {
                    let body = newCommentBody.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !body.isEmpty else { return }
                    isSending = true
                    isCommentFocused = false
                    newCommentBody = ""
                    await onAddComment(body)
                    isSending = false
                }
            } label: {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .disabled(newCommentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
    }
}
