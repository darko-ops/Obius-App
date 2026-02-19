import Foundation
import Combine
import GRDB
import Supabase

/// ViewModel for the expanded iMessage content view.
/// Fetches shared content, manages handshake signing, and live updates via realtime.
@MainActor
final class ExpandedContentViewModel: ObservableObject {
    let slug: String
    let noteId: String?

    @Published var isLoading = true
    @Published var error: String?
    @Published var content: SharedContentResponse?
    @Published var commentText = ""
    @Published var isPostingComment = false
    @Published var isSigningHandshake = false

    private let supabase = ExtensionSupabaseClient.shared
    private var realtimeSubscriber: ExtensionRealtimeSubscriber?
    private var cancellables = Set<AnyCancellable>()

    var isAuthenticated: Bool { supabase.isAuthenticated }
    var currentUserId: String? { supabase.currentUser?.id.uuidString }
    var currentUserName: String? { supabase.currentUser?.userMetadata["display_name"]?.stringValue }

    /// Whether the current user has already signed a handshake on this share
    var hasSignedHandshake: Bool {
        guard let userId = currentUserId,
              let interactions = content?.interactions else { return false }
        return interactions.contains { $0.userId == userId && $0.interactionType == "handshake" }
    }

    init(slug: String, noteId: String? = nil) {
        self.slug = slug
        self.noteId = noteId
    }

    // MARK: - Fetch Content

    func fetchContent() async {
        isLoading = true
        error = nil

        do {
            let links: [RemoteShareLinkRow] = try await supabase.client
                .from("share_links")
                .select()
                .eq("slug", value: slug)
                .eq("is_active", value: true)
                .limit(1)
                .execute()
                .value

            guard let link = links.first else {
                error = "Shared content not found"
                isLoading = false
                return
            }

            // Increment view count
            _ = try? await supabase.client
                .from("share_links")
                .update(["view_count": String(link.view_count + 1)])
                .eq("id", value: link.id)
                .execute()

            // Fetch comments
            let comments: [SharedComment] = try await supabase.client
                .from("comments")
                .select()
                .eq("share_link_id", value: link.id)
                .is("deleted_at", value: nil)
                .execute()
                .value

            // Fetch interactions (handshakes)
            let interactions: [SharedInteraction] = try await supabase.client
                .from("node_interactions")
                .select()
                .eq("share_link_id", value: link.id)
                .execute()
                .value

            if link.share_type == "live", let noteId = link.note_id {
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

                let sections: [SharedSection] = try await supabase.client
                    .from("sections")
                    .select()
                    .eq("note_id", value: noteId)
                    .is("deleted_at", value: nil)
                    .order("order_key")
                    .execute()
                    .value

                content = SharedContentResponse(
                    shareType: "live",
                    shareLinkId: link.id,
                    note: note,
                    sections: sections,
                    commitContent: nil,
                    commitName: nil,
                    commitHash: nil,
                    creatorName: nil,
                    createdAt: link.created_at,
                    comments: comments,
                    interactions: interactions,
                    viewCount: link.view_count + 1,
                    isOffline: false
                )

                // Start realtime subscription for live shares
                startRealtimeSubscription(noteId: noteId, shareLinkId: link.id)
            } else {
                content = SharedContentResponse(
                    shareType: "commit",
                    shareLinkId: link.id,
                    note: nil,
                    sections: nil,
                    commitContent: link.commit_content,
                    commitName: link.commit_name,
                    commitHash: link.commit_hash,
                    creatorName: nil,
                    createdAt: link.created_at,
                    comments: comments,
                    interactions: interactions,
                    viewCount: link.view_count + 1,
                    isOffline: false
                )
            }
        } catch {
            // Offline fallback: try loading from local database
            if let offlineContent = loadFromLocalDatabase() {
                self.content = offlineContent
            } else {
                self.error = "Failed to load content: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    // MARK: - Offline Fallback

    private func loadFromLocalDatabase() -> SharedContentResponse? {
        guard let noteId = self.noteId else { return nil }

        let reader = ExtensionDatabaseReader.shared
        guard reader.isAvailable else { return nil }

        return reader.read({ db -> SharedContentResponse? in
            // Read note
            guard let noteRow = try Row.fetchOne(db, sql: "SELECT id, title, body FROM notes WHERE id = ?", arguments: [noteId]) else {
                return nil
            }

            let note = SharedNote(
                id: noteRow["id"],
                title: noteRow["title"],
                body: noteRow["body"] ?? ""
            )

            // Read sections
            let sectionRows = try Row.fetchAll(db, sql: """
                SELECT id, content, content_type, order_key, indent_level, handle_id
                FROM sections
                WHERE note_id = ? AND deleted_at IS NULL
                ORDER BY order_key
                """, arguments: [noteId])

            let sections = sectionRows.map { row in
                SharedSection(
                    id: row["id"],
                    content: row["content"] ?? "",
                    contentType: row["content_type"] ?? "text",
                    orderKey: row["order_key"] ?? "",
                    indentLevel: row["indent_level"] ?? 0,
                    handleId: row["handle_id"]
                )
            }

            return SharedContentResponse(
                shareType: "live",
                shareLinkId: "",
                note: note,
                sections: sections,
                commitContent: nil,
                commitName: nil,
                commitHash: nil,
                creatorName: nil,
                createdAt: nil,
                comments: [],
                interactions: [],
                viewCount: 0,
                isOffline: true
            )
        }) ?? nil
    }

    // MARK: - Realtime

    private func startRealtimeSubscription(noteId: String, shareLinkId: String) {
        let subscriber = ExtensionRealtimeSubscriber(noteId: noteId, shareLinkId: shareLinkId)

        // Observe realtime updates and merge into content
        subscriber.$note
            .compactMap { $0 }
            .sink { [weak self] updatedNote in
                guard let self, let existing = self.content else { return }
                self.content = existing.copyWith(note: updatedNote)
            }
            .store(in: &cancellables)

        subscriber.$sections
            .compactMap { $0 }
            .sink { [weak self] updatedSections in
                guard let self, let existing = self.content else { return }
                self.content = existing.copyWith(sections: updatedSections)
            }
            .store(in: &cancellables)

        subscriber.$comments
            .filter { !$0.isEmpty }
            .sink { [weak self] updatedComments in
                guard let self, let existing = self.content else { return }
                self.content = existing.copyWith(comments: updatedComments)
            }
            .store(in: &cancellables)

        subscriber.$interactions
            .filter { !$0.isEmpty }
            .sink { [weak self] updatedInteractions in
                guard let self, let existing = self.content else { return }
                self.content = existing.copyWith(interactions: updatedInteractions)
            }
            .store(in: &cancellables)

        subscriber.subscribe()
        self.realtimeSubscriber = subscriber
    }

    /// Clean up realtime subscriptions. Called by MessagesViewController on view transitions.
    func cleanup() {
        realtimeSubscriber?.unsubscribe()
        realtimeSubscriber = nil
        cancellables.removeAll()
    }

    // MARK: - Handshake Signing

    /// Sign a handshake — inserts into the dedicated node_interactions table
    func signHandshake() async {
        guard let shareLinkId = content?.shareLinkId,
              let user = supabase.currentUser else { return }

        isSigningHandshake = true

        do {
            let interactionId = UUID().uuidString
            let displayName = user.userMetadata["display_name"]?.stringValue ?? user.email

            // For commit shares, include the commit hash as sealed reference
            let sealedHash: String? = content?.shareType == "commit" ? content?.commitName : nil

            let row: [String: String?] = [
                "id": interactionId,
                "share_link_id": shareLinkId,
                "user_id": user.id.uuidString,
                "user_display_name": displayName,
                "interaction_type": "handshake",
                "sealed_commit_hash": sealedHash
            ]

            try await supabase.client
                .from("node_interactions")
                .insert(row)
                .execute()

            let newInteraction = SharedInteraction(
                id: interactionId,
                userId: user.id.uuidString,
                userDisplayName: displayName,
                interactionType: "handshake",
                sealedCommitHash: sealedHash,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )

            // Append to local list
            if let existing = content {
                var interactions = existing.interactions
                interactions.append(newInteraction)
                content = existing.copyWith(interactions: interactions)
            }
        } catch {
            // Unique constraint violation means already signed — not an error
            let errorString = "\(error)"
            if errorString.contains("duplicate") || errorString.contains("unique") || errorString.contains("23505") {
                // Already signed, silently ignore
            } else {
                self.error = "Failed to sign handshake: \(error.localizedDescription)"
            }
        }

        isSigningHandshake = false
    }

    // MARK: - Add Comment

    func postComment() async {
        let body = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty,
              let shareLinkId = content?.shareLinkId,
              let user = supabase.currentUser else { return }

        isPostingComment = true

        do {
            let commentId = UUID().uuidString
            let displayName = user.userMetadata["display_name"]?.stringValue ?? user.email

            let row: [String: String?] = [
                "id": commentId,
                "share_link_id": shareLinkId,
                "user_id": user.id.uuidString,
                "user_display_name": displayName,
                "body": body
            ]

            try await supabase.client
                .from("comments")
                .insert(row)
                .execute()

            let newComment = SharedComment(
                id: commentId,
                userId: user.id.uuidString,
                userDisplayName: displayName,
                body: body,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                sealedCommitHash: nil
            )

            // Append to local list
            if let existing = content {
                var comments = existing.comments
                comments.append(newComment)
                content = existing.copyWith(comments: comments)
            }

            commentText = ""
        } catch {
            self.error = "Failed to post comment: \(error.localizedDescription)"
        }

        isPostingComment = false
    }
}
