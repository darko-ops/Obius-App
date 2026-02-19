import SwiftUI

struct SharedContentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = SharedContentViewModel()

    let slug: String
    @State private var copiedField: String?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading shared content...")
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView(
                        "Unable to Load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    contentView
                }
            }
            .background(Color.black)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.shareType == .commit, let hash = viewModel.commitHash {
                        Text("#\(commitShortId(from: hash))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Text(viewModel.title ?? "Shared")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                        DeepLinkRouter.shared.clearPending()
                    }
                }
            }
            .task {
                await viewModel.loadContent(slug: slug)
                await viewModel.checkIfArchived(commitRepository: appState.commitRepository)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Share type badge + action button
                HStack {
                    shareTypeBadge
                    Spacer()
                    if SupabaseManager.shared.isAuthenticated {
                        if viewModel.shareType == .commit {
                            archiveButton
                        } else if viewModel.shareType == .live {
                            addToArtifactsButton
                        }
                    }
                }

                // Content
                if viewModel.shareType == .live {
                    liveContentView
                } else {
                    commitContentView
                }

                Divider()
                    .padding(.vertical, 8)

                // Comments
                CommentThreadView(
                    comments: viewModel.comments,
                    isAuthenticated: SupabaseManager.shared.isAuthenticated,
                    isCommitShare: viewModel.shareType == .commit,
                    onAddComment: { body in
                        await viewModel.addComment(body: body)
                    }
                )
            }
            .padding()
        }
    }

    private var shareTypeBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.shareType == .live
                  ? "antenna.radiowaves.left.and.right"
                  : "doc.zipper")
                .font(.caption2)

            Text(viewModel.shareType == .live ? "Live" : "Commit")
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            (viewModel.shareType == .live ? Color.blue : Color.purple).opacity(0.15),
            in: Capsule()
        )
        .foregroundStyle(viewModel.shareType == .live ? .blue : .purple)
    }

    @ViewBuilder
    private var liveContentView: some View {
        if let note = viewModel.note {
            if !note.body.isEmpty {
                Text(note.body)
                    .font(.body)
            }
        }

        if let sections = viewModel.sections {
            ForEach(sections) { section in
                sharedSectionView(section)
            }
        }
    }

    @ViewBuilder
    private var commitContentView: some View {
        // Commit metadata header
        VStack(alignment: .leading, spacing: 6) {
            // Page title
            if let title = viewModel.title, !title.isEmpty {
                copyableRow(
                    label: "Title",
                    value: title,
                    field: "title",
                    valueFont: .subheadline.weight(.semibold),
                    valueColor: .primary
                )
            }

            // .obx filename
            copyableRow(
                label: "File",
                value: "\(viewModel.commitName ?? "Untitled").obx",
                field: "file",
                valueFont: .subheadline.weight(.medium),
                valueColor: .primary
            )

            // Commit ID
            if let hash = viewModel.commitHash {
                copyableRow(
                    label: "ID",
                    value: "#\(commitShortId(from: hash))",
                    field: "id",
                    valueFont: .subheadline.weight(.medium),
                    valueColor: .primary
                )
            }

            // Creator
            if let creator = viewModel.creatorName {
                copyableRow(
                    label: "By",
                    value: creator,
                    field: "creator",
                    valueFont: .subheadline,
                    valueColor: .secondary
                )
            }

            // Created date
            if let date = viewModel.createdAt {
                let formatter = {
                    let f = DateFormatter()
                    f.dateStyle = .medium
                    f.timeStyle = .short
                    return f
                }()
                copyableRow(
                    label: "Date",
                    value: formatter.string(from: date),
                    field: "date",
                    valueFont: .subheadline,
                    valueColor: .secondary
                )
            }

            // Hash
            if let hash = viewModel.commitHash {
                let bareHash = hash.replacingOccurrences(of: "sha256:", with: "")
                copyableRow(
                    label: "Hash",
                    value: bareHash,
                    field: "hash",
                    valueFont: .system(.caption2, design: .monospaced),
                    valueColor: .tertiary
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))

        // Dot divider
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)

        // Section content
        if !viewModel.commitSections.isEmpty {
            if let body = viewModel.commitNoteBody, !body.isEmpty {
                Text(body)
                    .font(.body)
            }

            ForEach(viewModel.commitSections) { section in
                sharedSectionView(section)
            }
        } else if let raw = viewModel.commitContent {
            // Fallback for unparseable content
            Text(raw)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var addToArtifactsButton: some View {
        Button {
            Task {
                await viewModel.addToArtifacts(
                    coldStore: appState.coldStore,
                    commitRepository: appState.commitRepository
                )
            }
        } label: {
            HStack(spacing: 4) {
                if viewModel.isArchiving {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: viewModel.isArchived ? "checkmark.circle.fill" : "arrow.down.doc.fill")
                        .font(.caption)
                }
                Text(viewModel.isArchived ? "Saved" : "Add to Artifacts")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(viewModel.isArchived ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
            .foregroundStyle(viewModel.isArchived ? .green : .blue)
            .clipShape(Capsule())
        }
        .disabled(viewModel.isArchived || viewModel.isArchiving)
    }

    private var archiveButton: some View {
        Button {
            Task {
                await viewModel.archiveCommit(
                    coldStore: appState.coldStore,
                    commitRepository: appState.commitRepository
                )
            }
        } label: {
            HStack(spacing: 4) {
                if viewModel.isArchiving {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: viewModel.isArchived ? "checkmark.circle.fill" : "arrow.down.doc.fill")
                        .font(.caption)
                }
                Text(viewModel.isArchived ? "Archived" : "Archive")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(viewModel.isArchived ? Color.green.opacity(0.15) : Color.purple.opacity(0.15))
            .foregroundStyle(viewModel.isArchived ? .green : .purple)
            .clipShape(Capsule())
        }
        .disabled(viewModel.isArchived || viewModel.isArchiving)
    }

    private func copyableRow<S: ShapeStyle>(label: String, value: String, field: String, valueFont: Font, valueColor: S) -> some View {
        Button {
            UIPasteboard.general.string = value
            copiedField = field
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedField == field { copiedField = nil }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if copiedField == field {
                    Text("Copied")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Text(value)
                        .font(valueFont)
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Derives a short commit ID from a hash like "sha256:abc123..." → "OBX-ABC1-...XYZ"
    private func commitShortId(from hash: String) -> String {
        let hex = hash.hasPrefix("sha256:") ? String(hash.dropFirst(7)) : hash
        let upper = hex.prefix(4).uppercased()
        let lower = hex.suffix(4).uppercased()
        return "OBX-\(upper)-\(lower)"
    }

    @ViewBuilder
    private func sharedSectionView(_ section: SharedSection) -> some View {
        if section.contentType == "image" || section.contentType == "audio" {
            CommitNodePreview(
                content: section.content,
                contentType: section.contentType,
                indentLevel: section.indentLevel,
                sectionType: "node",
                mediaRepository: appState.mediaRepository
            )
        } else {
            HStack(alignment: .top, spacing: 0) {
                if section.indentLevel > 0 {
                    Spacer()
                        .frame(width: CGFloat(section.indentLevel) * 20)
                }

                Text(section.content)
                    .font(section.contentType == "code" ? .system(.body, design: .monospaced) : .body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
