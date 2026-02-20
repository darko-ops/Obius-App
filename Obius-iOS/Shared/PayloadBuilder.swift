import Foundation

/// Shared payload builder usable by both the main app and the iMessage extension.
/// Extracts logic from ShareManager.buildMessagePayload() so the extension can
/// build payloads from local DB data without needing the full ShareManager.
enum PayloadBuilder {

    /// Build a MessageSharePayload from local data.
    /// - Parameters:
    ///   - slug: The share link slug
    ///   - shareType: "live" or "commit"
    ///   - title: Display title for the shared content
    ///   - sections: Sections to preview (up to 3 will be used)
    ///   - handles: Handles referenced by the note
    ///   - creatorName: Optional creator display name
    ///   - commitHash: Optional commit hash (unused, kept for compatibility)
    ///   - commitShortId: Optional human-readable short ID (e.g. OBX-A1B2-C3D4)
    static func buildPayload(
        slug: String,
        shareType: String,
        title: String,
        sections: [MessageSharePayload.SectionPreview],
        handleNames: [String],
        creatorName: String? = nil,
        commitHash: String? = nil,
        commitShortId: String? = nil,
        noteId: String? = nil
    ) -> MessageSharePayload {
        return MessageSharePayload(
            slug: slug,
            shareType: shareType,
            title: title,
            creatorName: creatorName,
            commitShortId: commitShortId,
            sectionPreviews: sections,
            handleNames: handleNames,
            noteId: noteId
        )
    }

    /// Build section previews from Section models (for extension use)
    static func sectionPreviews(from sections: [SectionPreviewSource], limit: Int = 3) -> [MessageSharePayload.SectionPreview] {
        sections.prefix(limit).map { section in
            MessageSharePayload.SectionPreview(
                content: String(section.previewContent.prefix(100)),
                contentType: section.previewContentType,
                intent: section.previewIntent
            )
        }
    }
}

/// Protocol for types that can provide section preview data.
/// Both the main app's Section model and extension can conform.
protocol SectionPreviewSource {
    var previewContent: String { get }
    var previewContentType: String { get }
    var previewIntent: String? { get }
}
