import SwiftUI

struct ActionCardView: View {
    let action: SuggestedAction
    let onAccept: () -> Void
    let onDismiss: () -> Void
    var previewSections: [Section] = []
    var mediaRepository: MediaRepository? = nil

    @State private var isExpanded: Bool = false

    private var isResolved: Bool {
        action.status != .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Type badge + expand toggle for resolved cards
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: action.icon)
                        .font(.caption2)
                    Text(action.toolName.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(action.tintColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(action.tintColor.opacity(0.15))
                .clipShape(Capsule())

                Spacer()

                if isResolved && action.fullContent != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Title
            Text(action.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.lightGray))
                .lineLimit(2)

            // Content area
            if case .rewritePage(let p) = action.actionType {
                if !isResolved || isExpanded {
                    rewritePagePreview(params: p)
                }
            } else if case .updatePageBody(let p) = action.actionType {
                if !isResolved || isExpanded {
                    updatePageBodyPreview(params: p)
                }
            } else if let full = action.fullContent {
                if !isResolved {
                    // Pending: show full content so user can review before accepting
                    Text(full)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if isExpanded {
                    // Resolved + expanded: show full content
                    Text(full)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                // Non-content actions: show description
                Text(action.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isResolved ? 2 : nil)
            }

            // Action row
            statusRow
        }
        .padding(14)
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(action.tintColor.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusRow: some View {
        switch action.status {
        case .pending:
            HStack(spacing: 10) {
                Button {
                    onAccept()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                        Text("Accept")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(action.tintColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(action.tintColor.opacity(0.12))
                    .clipShape(Capsule())
                }

                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                        Text("Dismiss")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }

                Spacer()
            }

        case .accepted:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                Text("Accepted")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.green)

        case .dismissed:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                Text("Dismissed")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)

        case .failed(let reason):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text("Failed: \(reason)")
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
            }
            .foregroundStyle(.red)
        }
    }

    // MARK: - Update Page Body Preview

    @ViewBuilder
    private func updatePageBodyPreview(params p: SuggestedAction.UpdatePageBodyParams) -> some View {
        let activeSections = previewSections.filter { $0.deletedAt == nil }

        VStack(alignment: .leading, spacing: 6) {
            // New body text
            let body = p.newBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // All existing sections unchanged
            ForEach(activeSections) { section in
                #if os(iOS)
                if section.contentType == .image, let mediaRepo = mediaRepository {
                    let hashes = section.content.split(separator: ",").map { entry in
                        String(entry.split(separator: "|").first ?? "")
                    }
                    ImageNodeView(
                        imageHashes: hashes,
                        mediaRepository: mediaRepo,
                        onTap: {}
                    )
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if section.contentType == .audio, let mediaRepo = mediaRepository {
                    let parts = section.content.split(separator: "|")
                    let hash = String(parts.first ?? "")
                    let duration = TimeInterval(parts.count > 1 ? String(parts[1]) : "0") ?? 0
                    AudioNodeView(
                        audioHash: hash,
                        duration: duration,
                        mediaRepository: mediaRepo
                    )
                } else {
                    sectionPreviewRow(section: section, content: section.content)
                }
                #else
                sectionPreviewRow(section: section, content: section.content)
                #endif
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Rewrite Page Preview

    @ViewBuilder
    private func rewritePagePreview(params p: SuggestedAction.RewritePageParams) -> some View {
        let keepIds = Set(p.keepSections.map(\.sectionId))
        // Map of sectionId -> new content from the rewrite
        let contentUpdates = Dictionary(
            p.keepSections.compactMap { ks -> (String, String)? in
                guard let nc = ks.newContent else { return nil }
                return (ks.sectionId, nc)
            },
            uniquingKeysWith: { _, last in last }
        )

        VStack(alignment: .leading, spacing: 6) {
            // Body text
            let body = p.newBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Sections that will remain
            ForEach(previewSections.filter { keepIds.contains($0.id) && $0.deletedAt == nil }) { section in
                let content = contentUpdates[section.id] ?? section.content

                #if os(iOS)
                if section.contentType == .image, let mediaRepo = mediaRepository {
                    let hashes = content.split(separator: ",").map { entry in
                        String(entry.split(separator: "|").first ?? "")
                    }
                    ImageNodeView(
                        imageHashes: hashes,
                        mediaRepository: mediaRepo,
                        onTap: {}
                    )
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if section.contentType == .audio, let mediaRepo = mediaRepository {
                    let parts = content.split(separator: "|")
                    let hash = String(parts.first ?? "")
                    let duration = TimeInterval(parts.count > 1 ? String(parts[1]) : "0") ?? 0
                    AudioNodeView(
                        audioHash: hash,
                        duration: duration,
                        mediaRepository: mediaRepo
                    )
                } else {
                    sectionPreviewRow(section: section, content: content)
                }
                #else
                sectionPreviewRow(section: section, content: content)
                #endif
            }

            // Summary badge
            Text(p.summary)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 4)
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func sectionPreviewRow(section: Section, content: String) -> some View {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if section.sectionType == .fold {
                Text(trimmed)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(section.intent.backgroundTint))
            } else {
                HStack(alignment: .top, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(section.intent.color.opacity(0.5))
                        .frame(width: 2, height: 12)
                        .padding(.top, 1)
                    Text(trimmed)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}
