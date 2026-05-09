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
            .background(Color.systemBackground)
            .navigationTitle("")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("ObiusLogo")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
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
                // Title (centered)
                if let title = viewModel.title, !title.isEmpty {
                    Button {
                        ClipboardHelper.copy(title)
                        copiedField = "badge_title"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedField == "badge_title" { copiedField = nil }
                        }
                    } label: {
                        Text(copiedField == "badge_title" ? "Copied" : title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(copiedField == "badge_title" ? .green : .primary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                // Share type badge (left) + centered ID + action button (right)
                ZStack {
                    HStack {
                        shareTypeBadge
                        Spacer()
                    }

                    if viewModel.shareType == .commit, let shortId = viewModel.commitShortId ?? viewModel.commitHash.map({ commitShortId(from: $0) }) {
                        Button {
                            ClipboardHelper.copy(shortId)
                            copiedField = "nav_title"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedField == "nav_title" { copiedField = nil }
                            }
                        } label: {
                            Text(copiedField == "nav_title" ? "Copied" : "#\(shortId)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(copiedField == "nav_title" ? .white : .green)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.2), in: Capsule())
                        }
                    }

                    if SupabaseManager.shared.isAuthenticated {
                        HStack {
                            Spacer()
                            if viewModel.shareType == .commit {
                                archiveButton
                            } else if viewModel.shareType == .live {
                                addToArtifactsButton
                            }
                        }
                    }
                }

                // Metadata card (for commits)
                if viewModel.shareType == .commit {
                    commitMetadataCard
                }

                // Content
                if viewModel.shareType == .live {
                    liveContentView
                } else {
                    commitContentView
                }

                // Copy all button
                HStack {
                    Spacer()
                    Button {
                        let allText = buildFullContentText()
                        ClipboardHelper.copy(allText)
                        copiedField = "copy_all"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedField == "copy_all" { copiedField = nil }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedField == "copy_all" ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                            Text(copiedField == "copy_all" ? "" : "")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(copiedField == "copy_all" ? .green : .secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

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

            Text(viewModel.shareType == .live ? "Live" : "Version")
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            (viewModel.shareType == .live ? Color.green : Color.purple).opacity(0.15),
            in: Capsule()
        )
        .foregroundStyle(viewModel.shareType == .live ? .green : .purple)
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

    private var commitMetadataCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // .obx filename
            copyableRow(
                label: "File",
                value: "\(viewModel.commitName ?? "Untitled").obx",
                field: "file",
                valueFont: .subheadline.weight(.medium),
                valueColor: .primary
            )

            // Creator
            copyableRow(
                label: "By",
                value: viewModel.creatorName ?? "Anonymous",
                field: "creator",
                valueFont: .subheadline,
                valueColor: .secondary
            )

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
        .background(Color.secondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var commitContentView: some View {
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
                    commitRepository: appState.commitRepository,
                    noteRepository: appState.noteRepository,
                    sectionRepository: appState.sectionRepository
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
                Text(viewModel.isArchived ? "Saved" : "Add")
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
            ClipboardHelper.copy(value)
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

    private func buildFullContentText() -> String {
        var parts: [String] = []
        if viewModel.shareType == .live {
            if let note = viewModel.note, !note.body.isEmpty {
                parts.append(note.body)
            }
            if let sections = viewModel.sections {
                for section in sections where section.contentType != "image" && section.contentType != "audio" {
                    parts.append(section.content)
                }
            }
        } else {
            if let body = viewModel.commitNoteBody, !body.isEmpty {
                parts.append(body)
            }
            for section in viewModel.commitSections where section.contentType != "image" && section.contentType != "audio" {
                parts.append(section.content)
            }
            if parts.isEmpty, let raw = viewModel.commitContent {
                parts.append(raw)
            }
        }
        return parts.joined(separator: "\n")
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
            let intent = section.intent

            HStack(alignment: .top, spacing: 0) {
                if section.indentLevel > 0 {
                    Spacer()
                        .frame(width: CGFloat(section.indentLevel) * 20)
                }

                HStack(spacing: 0) {
                    // Intent rail
                    RoundedRectangle(cornerRadius: 2)
                        .fill(intent.color)
                        .frame(width: 3)
                        .padding(.vertical, 4)

                    Text(section.content)
                        .font(section.contentType == "code" ? .system(.body, design: .monospaced) : .body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(intent.backgroundTint)
                )
            }
        }
    }
}
