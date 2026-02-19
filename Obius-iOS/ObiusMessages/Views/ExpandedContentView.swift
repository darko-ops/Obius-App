import SwiftUI

/// Expanded view shown when a recipient taps an Obius message card in iMessage.
/// Includes live content display, handshake signing, and realtime updates.
struct ExpandedContentView: View {
    @ObservedObject var viewModel: ExpandedContentViewModel
    let onDismiss: () -> Void

    init(viewModel: ExpandedContentViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await viewModel.fetchContent() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if let content = viewModel.content {
                    contentView(content)
                }
            }
            .navigationTitle("Shared Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .task {
            await viewModel.fetchContent()
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private func contentView(_ content: SharedContentResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Offline banner
                if content.isOffline {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                        Text("Showing cached content")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Share type badge
                HStack {
                    Text(content.shareType == "commit" ? "Snapshot" : "Live")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(content.shareType == "commit" ? .purple : .blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                content.shareType == "commit"
                                    ? Color.purple.opacity(0.15)
                                    : Color.blue.opacity(0.15)
                            )
                        )

                    Spacer()

                    Text("\(content.viewCount) views")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Live share content
                if let note = content.note {
                    if let title = note.title, !title.isEmpty {
                        Text(title)
                            .font(.title2.bold())
                    }
                    if !note.body.isEmpty {
                        Text(note.body)
                            .font(.body)
                    }
                }

                // Sections
                if let sections = content.sections {
                    ForEach(sections) { section in
                        sectionRow(section)
                    }
                }

                // Commit content
                if let commitContent = content.commitContent {
                    if let commitName = content.commitName {
                        Text(commitName)
                            .font(.headline)
                    }
                    Text(commitContent)
                        .font(.body)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider()

                // Handshake section
                handshakeSection(content)

                Divider()

                // Comments section
                commentsSection(content.comments)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func sectionRow(_ section: SharedSection) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Indent
            if section.indentLevel > 0 {
                Color.clear.frame(width: CGFloat(section.indentLevel) * 16)
            }

            VStack(alignment: .leading, spacing: 4) {
                if section.contentType == "image" {
                    Label("Image", systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if section.contentType == "audio" {
                    Label("Audio", systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(section.content)
                        .font(.body)
                }
            }
        }
    }

    // MARK: - Handshake

    @ViewBuilder
    private func handshakeSection(_ content: SharedContentResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Handshake header
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.purple)
                Text("Handshakes")
                    .font(.headline)
            }

            // Display existing handshakes from interactions
            let handshakes = content.interactions.filter { $0.interactionType == "handshake" }
            if !handshakes.isEmpty {
                ForEach(handshakes) { handshake in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.purple)
                            .font(.system(size: 16))

                        Text(handshake.userDisplayName ?? "Anonymous")
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        Text(formatDate(handshake.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No handshakes yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Handshake action
            if viewModel.isAuthenticated {
                if viewModel.hasSignedHandshake {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.purple)
                        Text("You signed this")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        Task { await viewModel.signHandshake() }
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isSigningHandshake {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "hand.raised.fill")
                            }
                            Text("Sign Handshake")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(viewModel.isSigningHandshake)
                }
            } else {
                // Download CTA for unauthenticated users
                downloadCTA
            }
        }
    }

    // MARK: - Download CTA

    @ViewBuilder
    private var downloadCTA: some View {
        VStack(spacing: 10) {
            Text("Get Obius to collaborate")
                .font(.subheadline.weight(.semibold))

            Text("Sign handshakes, leave comments, and create your own notes")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link(destination: URL(string: "https://apps.apple.com/app/obius/id0000000000")!) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.app.fill")
                    Text("Get Obius")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.blue)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color(UIColor.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Comments

    @ViewBuilder
    private func commentsSection(_ comments: [SharedComment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline)

            if comments.isEmpty {
                Text("No comments yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(comment.userDisplayName ?? "Anonymous")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(formatDate(comment.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(comment.body)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Comment input
            if viewModel.isAuthenticated {
                HStack(spacing: 8) {
                    TextField("Add a comment...", text: $viewModel.commentText)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        Task { await viewModel.postComment() }
                    } label: {
                        if viewModel.isPostingComment {
                            ProgressView()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isPostingComment)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
