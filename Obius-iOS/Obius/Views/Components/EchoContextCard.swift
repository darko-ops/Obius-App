import SwiftUI

/// Shows context when an Echo fires: the last 3 portal sections referencing
/// the handle, with their parent note titles and last-edited dates.
struct EchoContextCard: View {
    let echo: Echo
    let handleName: String
    let portalContexts: [PortalContext]
    let onNavigate: ((String) -> Void)? // noteId

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Echo Fired")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("@\(handleName)")
                        .font(.subheadline.weight(.semibold))
                }

                Spacer()

                Text(echo.cadenceDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if portalContexts.isEmpty {
                Text("No pages reference this loop yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                // Portal sections with context
                ForEach(portalContexts) { context in
                    Button {
                        onNavigate?(context.noteId)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.purple.opacity(0.5))
                                .frame(width: 3)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(context.noteTitle)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(context.contentPreview)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                Text(context.editedAgo)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Portal Context

struct PortalContext: Identifiable {
    var id: String { sectionId }
    let sectionId: String
    let noteId: String
    let noteTitle: String
    let contentPreview: String
    let editedAgo: String
}

// MARK: - Factory

extension EchoContextCard {
    /// Build portal contexts from sections with a given handle.
    /// Requires access to the note repository to resolve note titles.
    @MainActor
    static func buildContexts(
        handleId: String,
        handleRepository: HandleRepository,
        noteRepository: NoteRepository
    ) async -> [PortalContext] {
        guard let sections = try? await handleRepository.getSectionsWithHandle(handleId: handleId) else {
            return []
        }

        let now = Date()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        var contexts: [PortalContext] = []
        var seenNotes = Set<String>()

        for section in sections.prefix(3) {
            guard seenNotes.insert(section.noteId).inserted else { continue }

            let noteTitle: String
            if let note = noteRepository.notes.first(where: { $0.id == section.noteId }) {
                noteTitle = note.displayTitle
            } else {
                noteTitle = "Untitled"
            }

            let updatedDate = Date(timeIntervalSince1970: Double(section.updatedAt) / 1000)
            let editedAgo = "Edited " + formatter.localizedString(for: updatedDate, relativeTo: now)

            contexts.append(PortalContext(
                sectionId: section.id,
                noteId: section.noteId,
                noteTitle: noteTitle,
                contentPreview: String(section.content.prefix(120)),
                editedAgo: editedAgo
            ))
        }

        return contexts
    }
}
