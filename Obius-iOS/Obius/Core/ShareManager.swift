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

    /// Initialize with repositories — call once during app startup.
    /// Safe to re-call on account switch.
    func initialize(shareLinkRepository: ShareLinkRepository, commentRepository: CommentRepository) {
        self.shareLinkRepository = shareLinkRepository
        self.commentRepository = commentRepository
        self.isLoaded = true
    }

    /// Drop per-user state. Called on sign-out / account switch before re-initialize.
    func reset() {
        shareLinkRepository = nil
        commentRepository = nil
        isLoaded = false
    }

    // MARK: - Create Live Share

    func createLiveShare(noteId: String, note: Note, sections: [Section]) async throws -> ShareLink {
        guard TierManager.shared.limits.shareLinks else {
            TierManager.shared.paywallFeature = .shareLinks
            TierManager.shared.showPaywall = true
            throw ShareError.notAuthenticated
        }
        guard supabase.isAuthenticated, let userId = supabase.currentUser?.id.uuidString.lowercased() else {
            throw ShareError.notAuthenticated
        }

        // Ensure user_profiles row exists (FK target for notes.user_id)
        try await ensureUserProfile(userId: userId)

        // Push note to Supabase so viewers can read it.
        // interstitial_content / interstitial_rich_content are JSON-encoded
        // [String: String] dicts. Omitting them here lets the share land before
        // the main SyncEngine has pushed them — viewers then see a page with no
        // text between/after nodes until the next sync round-trip.
        let noteRow: [String: String?] = [
            "id": note.id,
            "user_id": userId,
            "title": note.title,
            "body": note.body,
            "body_rich_text": note.bodyRichText,
            "is_pinned": String(note.isPinned),
            "color_intent": note.intent.legacyValue,
            "interstitial_content": encodeJSONDict(note.interstitialContent),
            "interstitial_rich_content": encodeJSONDict(note.interstitialRichContent),
            "created_at": formatTimestamp(note.createdAt),
            "updated_at": formatTimestamp(note.updatedAt)
        ]

        try await supabase.client
            .from("notes")
            .upsert(noteRow)
            .execute()

        // Push sections to Supabase.
        // section_type preserves fold-vs-line; without it line sections render
        // as boxed nodes in the preview until the main SyncEngine catches up.
        if !sections.isEmpty {
            let sectionRows: [[String: String?]] = sections.map { section in
                var row: [String: String?] = [
                    "id": section.id,
                    "note_id": section.noteId,
                    "user_id": userId,
                    "content": section.content,
                    "content_type": section.contentType.rawValue,
                    "section_type": section.sectionType.rawValue,
                    "order_key": section.orderKey,
                    "indent_level": String(section.indentLevel),
                    "is_collapsed": String(section.isCollapsed),
                    "color_intent": section.intent.legacyValue,
                    "handle_id": section.handleId,
                    "created_at": formatTimestamp(section.createdAt),
                    "updated_at": formatTimestamp(section.updatedAt)
                ]
                row["parent_section_id"] = section.parentSectionId
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
        let creatorName = supabase.currentUser?.displayName ?? supabase.currentUser?.email
        let linkRow: [String: String?] = [
            "id": shareLink.id,
            "slug": shareLink.slug,
            "user_id": userId,
            "share_type": "live",
            "note_id": noteId,
            "creator_name": creatorName,
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

    /// Ensures a user_profiles row exists for the current user.
    /// The notes and share_links tables have a FK to user_profiles, so this
    /// must exist before any upsert.  The row is created idempotently via upsert.
    private func ensureUserProfile(userId: String) async throws {
        let displayName = supabase.currentUser?.displayName
            ?? supabase.currentUser?.email
        let row: [String: String?] = [
            "id": userId,
            "display_name": displayName
        ]
        try await supabase.client
            .from("user_profiles")
            .upsert(row, onConflict: "id")
            .execute()
    }

    private func formatTimestamp(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Encodes a [String: String] dict to the JSON-string shape the Supabase
    /// `notes.interstitial_content` / `interstitial_rich_content` columns expect.
    /// Empty dicts become "{}" so the column is never NULL.
    private func encodeJSONDict(_ dict: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Create Commit Share

    func createCommitShare(commitHash: String, commitName: String?, commitShortId: String? = nil, commitContent: String) async throws -> ShareLink {
        guard TierManager.shared.limits.shareLinks else {
            TierManager.shared.paywallFeature = .shareLinks
            TierManager.shared.showPaywall = true
            throw ShareError.notAuthenticated
        }
        guard supabase.isAuthenticated, let userId = supabase.currentUser?.id.uuidString.lowercased() else {
            throw ShareError.notAuthenticated
        }

        try await ensureUserProfile(userId: userId)

        let shareLink = ShareLink(
            userId: userId,
            shareType: .commit,
            commitHash: commitHash,
            commitName: commitName,
            commitShortId: commitShortId
        )

        let creatorName = supabase.currentUser?.displayName ?? supabase.currentUser?.email
        let row: [String: String?] = [
            "id": shareLink.id,
            "slug": shareLink.slug,
            "user_id": userId,
            "share_type": "commit",
            "commit_hash": commitHash,
            "commit_name": commitName,
            "commit_short_id": commitShortId,
            "commit_content": commitContent,
            "creator_name": creatorName,
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

        // Use creator_name stored on the share link (set at creation time)
        // Fall back to user_profiles lookup for old shares, then current user email, then "Anonymous"
        var creatorName: String? = link.creator_name
        if creatorName == nil {
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
        }
        if creatorName == nil, let currentUser = supabase.currentUser,
           currentUser.id.uuidString == link.user_id {
            creatorName = currentUser.email
        }
        if creatorName == nil {
            creatorName = "Anonymous"
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
                createdAt: comment.createdAt
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
            // Fetch note (body may not exist on older schemas)
            struct NoteRow: Decodable {
                let id: String
                let title: String?
                let body: String?
                let interstitial_content: String?
            }
            let notes: [NoteRow] = try await supabase.client
                .from("notes")
                .select("id,title,body,interstitial_content")
                .eq("id", value: noteId)
                .limit(1)
                .execute()
                .value

            let note = notes.first.map { row -> SharedNote in
                // interstitial_content is stored as a JSON string of [String: String]
                // keyed by "after_<sectionId>" or "end". Keys were written using the
                // local UUID string (uppercase), but Postgres returns section IDs in
                // lowercase, so we normalize keys to lowercase for consistent lookup.
                var parsed: [String: String] = [:]
                if let raw = row.interstitial_content,
                   let data = raw.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                    parsed = Dictionary(uniqueKeysWithValues: decoded.map { ($0.key.lowercased(), $0.value) })
                }
                return SharedNote(id: row.id, title: row.title, body: row.body ?? "", interstitialContent: parsed)
            }

            // Fetch sections
            let sections: [SharedSection] = try await supabase.client
                .from("sections")
                .select("id,content,content_type,section_type,order_key,indent_level,color_intent,is_collapsed,parent_section_id")
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
                commitShortId: nil,
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
                commitShortId: link.commit_short_id,
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
            createdAt: ISO8601DateFormatter().string(from: Date())
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

        return MessageSharePayload(
            slug: shareLink.slug,
            shareType: shareLink.shareType.rawValue,
            title: title,
            creatorName: supabase.currentUser?.displayName,
            commitShortId: shareLink.commitShortId,
            sectionPreviews: previews,
            handleNames: handles.map { $0.displayName },
            noteId: shareLink.noteId
        )
    }
}
