import Foundation
import Combine
import Supabase

// Shared types (RemoteShareLinkRow, RemoteCommentRow, SharedNote, SharedSection,
// SharedComment, SharedContentResponse) are defined in Shared/SharedRemoteTypes.swift
// so they can be used by both the main app and the iMessage extension.

// MARK: - Share Errors

enum ShareError: LocalizedError {
    case notAuthenticated
    case noNetwork
    case notFound
    case serverError(String)
    case encodingError
    case tableNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to share content"
        case .noNetwork:
            return "No network connection. Please try again later."
        case .notFound:
            return "Shared content not found"
        case .serverError(let message):
            return message
        case .encodingError:
            return "Failed to prepare content for sharing"
        case .tableNotFound:
            return "Share tables not set up. Please run the database migration in Supabase."
        }
    }
}

// MARK: - ShareManager

@MainActor
final class ShareManager: ObservableObject {
    static let shared = ShareManager()

    @Published private(set) var isLoaded: Bool = false

    private var shareLinkRepository: ShareLinkRepository?
    private var commentRepository: CommentRepository?
    private let supabase = SupabaseManager.shared

    private init() {}

    /// Initialize with repositories — call once during app startup
    func initialize(shareLinkRepository: ShareLinkRepository, commentRepository: CommentRepository) {
        self.shareLinkRepository = shareLinkRepository
        self.commentRepository = commentRepository
        self.isLoaded = true
    }

    // MARK: - Create Live Share

    func createLiveShare(noteId: String, note: Note, sections: [Section]) async throws -> ShareLink {
        guard supabase.isAuthenticated, let userId = supabase.currentUser?.id.uuidString else {
            throw ShareError.notAuthenticated
        }

        // Push note to Supabase so viewers can read it
        let noteRow: [String: String?] = [
            "id": note.id,
            "user_id": userId,
            "title": note.title,
            "body": note.body,
            "is_pinned": String(note.isPinned),
            "color_intent": note.intent.legacyValue,
            "created_at": formatTimestamp(note.createdAt),
            "updated_at": formatTimestamp(note.updatedAt)
        ]

        try await supabase.client
            .from("notes")
            .upsert(noteRow)
            .execute()

        // Push sections to Supabase
        if !sections.isEmpty {
            let sectionRows: [[String: String?]] = sections.map { section in
                var row: [String: String?] = [
                    "id": section.id,
                    "note_id": section.noteId,
                    "user_id": userId,
                    "content": section.content,
                    "content_type": section.contentType.rawValue,
                    "order_key": section.orderKey,
                    "indent_level": String(section.indentLevel),
                    "is_collapsed": String(section.isCollapsed),
                    "color_intent": section.intent.legacyValue,
                    "created_at": formatTimestamp(section.createdAt),
                    "updated_at": formatTimestamp(section.updatedAt)
                ]
                row["parent_section_id"] = section.parentSectionId
                row["handle_id"] = section.handleId
                return row
            }

            try await supabase.client
                .from("sections")
                .upsert(sectionRows)
                .execute()
        }

        let shareLink = ShareLink(
            userId: userId,
            shareType: .live,
            noteId: noteId
        )

        // Insert share link into Supabase
        let linkRow: [String: String?] = [
            "id": shareLink.id,
            "slug": shareLink.slug,
            "user_id": userId,
            "share_type": "live",
            "note_id": noteId,
            "is_active": "true",
            "view_count": "0"
        ]

        try await supabase.client
            .from("share_links")
            .insert(linkRow)
            .execute()

        // Save locally
        try await shareLinkRepository?.saveShareLink(shareLink)
        return shareLink
    }

    private func formatTimestamp(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    // MARK: - Create Commit Share

    func createCommitShare(commitHash: String, commitName: String?, commitContent: String) async throws -> ShareLink {
        guard supabase.isAuthenticated, let userId = supabase.currentUser?.id.uuidString else {
            throw ShareError.notAuthenticated
        }

        let shareLink = ShareLink(
            userId: userId,
            shareType: .commit,
            commitHash: commitHash,
            commitName: commitName
        )

        let row: [String: String?] = [
            "id": shareLink.id,
            "slug": shareLink.slug,
            "user_id": userId,
            "share_type": "commit",
            "commit_hash": commitHash,
            "commit_name": commitName,
            "commit_content": commitContent,
            "is_active": "true",
            "view_count": "0"
        ]

        try await supabase.client
            .from("share_links")
            .insert(row)
            .execute()

        try await shareLinkRepository?.saveShareLink(shareLink)
        return shareLink
    }

    // MARK: - Deactivate Share

    func deactivateShare(id: String) async throws {
        try await shareLinkRepository?.deactivateShareLink(id: id)

        try await supabase.client
            .from("share_links")
            .update(["is_active": "false"])
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Fetch Shared Content

    func fetchSharedContent(slug: String) async throws -> SharedContentResponse {
        // Look up the share link by slug
        let links: [RemoteShareLinkRow] = try await supabase.client
            .from("share_links")
            .select()
            .eq("slug", value: slug)
            .eq("is_active", value: true)
            .limit(1)
            .execute()
            .value

        guard let link = links.first else {
            throw ShareError.notFound
        }

        // Increment view count
        try await supabase.client
            .from("share_links")
            .update(["view_count": String(link.view_count + 1)])
            .eq("id", value: link.id)
            .execute()

        // Fetch creator display name (fall back to current user's email if viewing own share)
        var creatorName: String?
        do {
            struct ProfileRow: Decodable {
                let display_name: String?
            }
            let profiles: [ProfileRow] = try await supabase.client
                .from("user_profiles")
                .select("display_name")
                .eq("id", value: link.user_id)
                .limit(1)
                .execute()
                .value
            creatorName = profiles.first?.display_name
        } catch {
            print("ShareManager: Could not fetch creator profile: \(error.localizedDescription)")
        }
        // Fallback: if display_name is nil and this is the current user's share, use their email
        if creatorName == nil, let currentUser = supabase.currentUser,
           currentUser.id.uuidString == link.user_id {
            creatorName = currentUser.email
        }

        // Fetch comments and enrich with email
        let rawComments: [SharedComment] = try await supabase.client
            .from("comments")
            .select()
            .eq("share_link_id", value: link.id)
            .is("deleted_at", value: nil)
            .execute()
            .value

        let currentUserEmail = supabase.currentUser?.email
        let currentUserId = supabase.currentUser?.id.uuidString
        let comments = rawComments.map { comment in
            SharedComment(
                id: comment.id,
                userId: comment.userId,
                userDisplayName: comment.userDisplayName,
                userEmail: comment.userId == currentUserId ? currentUserEmail : nil,
                body: comment.body,
                createdAt: comment.createdAt,
                sealedCommitHash: comment.sealedCommitHash
            )
        }

        // Fetch interactions (handshakes) — table may not exist yet
        var interactions: [SharedInteraction] = []
        do {
            interactions = try await supabase.client
                .from("node_interactions")
                .select()
                .eq("share_link_id", value: link.id)
                .execute()
                .value
        } catch {
            print("ShareManager: node_interactions not available: \(error.localizedDescription)")
        }

        if link.share_type == "live", let noteId = link.note_id {
            // Fetch note
            struct NoteRow: Decodable {
                let id: String
                let title: String?
                let body: String
            }
            let notes: [NoteRow] = try await supabase.client
                .from("notes")
                .select()
                .eq("id", value: noteId)
                .limit(1)
                .execute()
                .value

            let note = notes.first.map { SharedNote(id: $0.id, title: $0.title, body: $0.body) }

            // Fetch sections
            let sections: [SharedSection] = try await supabase.client
                .from("sections")
                .select()
                .eq("note_id", value: noteId)
                .is("deleted_at", value: nil)
                .order("order_key")
                .execute()
                .value

            return SharedContentResponse(
                shareType: "live",
                shareLinkId: link.id,
                note: note,
                sections: sections,
                commitContent: nil,
                commitName: nil,
                commitHash: nil,
                creatorName: creatorName,
                createdAt: link.created_at,
                comments: comments,
                interactions: interactions,
                viewCount: link.view_count + 1,
                isOffline: false
            )
        } else {
            return SharedContentResponse(
                shareType: "commit",
                shareLinkId: link.id,
                note: nil,
                sections: nil,
                commitContent: link.commit_content,
                commitName: link.commit_name,
                commitHash: link.commit_hash,
                creatorName: creatorName,
                createdAt: link.created_at,
                comments: comments,
                interactions: interactions,
                viewCount: link.view_count + 1,
                isOffline: false
            )
        }
    }

    // MARK: - Comments

    func addComment(shareLinkId: String, body: String, parentCommentId: String? = nil) async throws -> SharedComment {
        guard supabase.isAuthenticated, let user = supabase.currentUser else {
            throw ShareError.notAuthenticated
        }

        let commentId = UUID().uuidString
        let displayName = user.displayName ?? user.email

        let row: [String: String?] = [
            "id": commentId,
            "share_link_id": shareLinkId,
            "user_id": user.id.uuidString,
            "user_display_name": displayName,
            "parent_comment_id": parentCommentId,
            "body": body
        ]

        try await supabase.client
            .from("comments")
            .insert(row)
            .execute()

        // Store locally (may fail if share link isn't in local DB, e.g. viewing someone else's share)
        do {
            let comment = Comment(
                id: commentId,
                shareLinkId: shareLinkId,
                userId: user.id.uuidString,
                userDisplayName: displayName,
                parentCommentId: parentCommentId,
                body: body
            )
            try await commentRepository?.saveComment(comment)
        } catch {
            print("ShareManager: Could not cache comment locally: \(error.localizedDescription)")
        }

        return SharedComment(
            id: commentId,
            userId: user.id.uuidString,
            userDisplayName: displayName,
            userEmail: user.email,
            body: body,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            sealedCommitHash: nil
        )
    }

    // MARK: - Local Queries

    func getShareLinks(noteId: String) async throws -> [ShareLink] {
        try await shareLinkRepository?.getShareLinks(noteId: noteId) ?? []
    }

    func getShareLinks(commitHash: String) async throws -> [ShareLink] {
        try await shareLinkRepository?.getShareLinks(commitHash: commitHash) ?? []
    }

    // MARK: - iMessage Payload Builder

    /// Builds a MessageSharePayload for passing to the iMessage extension via shared UserDefaults.
    func buildMessagePayload(
        shareLink: ShareLink,
        title: String,
        sections: [Section],
        handles: [Handle]
    ) -> MessageSharePayload {
        let previews = sections.prefix(3).map { section in
            MessageSharePayload.SectionPreview(
                content: String(section.content.prefix(100)),
                contentType: section.contentType.rawValue,
                intent: section.intent.rawValue
            )
        }

        let commitShortId: String? = shareLink.commitHash.map { hash in
            let upper = hash.prefix(4).uppercased()
            let lower = hash.suffix(4).uppercased()
            return "OBX-\(upper)-\(lower)"
        }

        return MessageSharePayload(
            slug: shareLink.slug,
            shareType: shareLink.shareType.rawValue,
            title: title,
            creatorName: supabase.currentUser?.displayName,
            commitShortId: commitShortId,
            sectionPreviews: previews,
            handleNames: handles.map { $0.displayName },
            noteId: shareLink.noteId
        )
    }
}
