import Foundation
import Combine
import Messages

/// ViewModel for the compact iMessage extension search view.
/// Searches handles, commits, and notes from the shared local database.
@MainActor
final class CompactSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [SearchResult] = []
    @Published var recentNotes: [Note] = []
    @Published var isCreatingShare = false
    @Published var error: String?

    /// Whether the shared database is available
    var isDatabaseAvailable: Bool { ExtensionDatabaseReader.shared.isAvailable }

    private let supabase = ExtensionSupabaseClient.shared
    private var searchCancellable: AnyCancellable?

    init() {
        // Debounce search input
        searchCancellable = $query
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query)
            }

        // Load recent notes on init
        recentNotes = ExtensionSearchRepository.getRecentNotes(limit: 5)
    }

    // MARK: - Search

    private func performSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        var allResults: [SearchResult] = []

        // Search handles
        let handles = ExtensionSearchRepository.searchHandles(query: trimmed)
        allResults.append(contentsOf: handles.map { .handle($0) })

        // Search commits
        let commits = ExtensionSearchRepository.searchCommits(query: trimmed)
        allResults.append(contentsOf: commits.map { .commit($0) })

        // Search notes via FTS
        let notes = ExtensionSearchRepository.searchNotes(query: trimmed)
        allResults.append(contentsOf: notes.map { .note($0) })

        results = allResults
    }

    // MARK: - Create Share & Build Message

    /// Creates a share link via Supabase and builds an MSMessage from local DB data.
    func createShareAndBuildMessage(for result: SearchResult) async -> MSMessage? {
        // Attempt session restore if not yet authenticated
        if !supabase.isAuthenticated {
            await supabase.restoreSession()
        }

        guard supabase.isAuthenticated,
              let userId = supabase.currentUser?.id.uuidString else {
            error = "Open Obius and sign in first"
            return nil
        }

        isCreatingShare = true
        error = nil

        defer { isCreatingShare = false }

        do {
            switch result {
            case .handle(let handle):
                // Share the handle as a note-like live share
                // Find a note that uses this handle
                let portalSections: [Section] = ExtensionDatabaseReader.shared.read { db in
                    try Section.fetchAll(db, sql: """
                        SELECT * FROM sections
                        WHERE handleId = ? AND deletedAt IS NULL
                        LIMIT 1
                    """, arguments: [handle.id])
                } ?? []

                if let section = portalSections.first,
                   let note = ExtensionSearchRepository.getNote(id: section.noteId) {
                    return try await createLiveShareMessage(
                        noteId: note.id,
                        title: handle.formattedName,
                        userId: userId
                    )
                } else {
                    error = "No notes found for this handle"
                    return nil
                }

            case .commit(let commit):
                return try await createCommitShareMessage(commit: commit, userId: userId)

            case .note(let note):
                let sections = ExtensionSearchRepository.getSections(noteId: note.id)
                let title = note.displayTitle(sections: sections)
                return try await createLiveShareMessage(
                    noteId: note.id,
                    title: title,
                    userId: userId
                )
            }
        } catch {
            self.error = "Failed to create share: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Private Share Creators

    private func createLiveShareMessage(noteId: String, title: String, userId: String) async throws -> MSMessage {
        let slug = generateSlug()

        let creatorName = supabase.currentUser?.userMetadata["display_name"]?.stringValue ?? supabase.currentUser?.email
        let row: [String: String?] = [
            "id": UUID().uuidString,
            "slug": slug,
            "user_id": userId,
            "share_type": "live",
            "note_id": noteId,
            "creator_name": creatorName,
            "is_active": "true",
            "view_count": "0"
        ]

        try await supabase.client
            .from("share_links")
            .insert(row)
            .execute()

        let sections = ExtensionSearchRepository.getSections(noteId: noteId)
        let handles = ExtensionSearchRepository.getHandlesForNote(noteId: noteId)

        let previews = PayloadBuilder.sectionPreviews(from: sections)
        let payload = PayloadBuilder.buildPayload(
            slug: slug,
            shareType: "live",
            title: title,
            sections: previews,
            handleNames: handles.map { $0.displayName },
            creatorName: supabase.currentUser?.userMetadata["display_name"]?.stringValue
        )

        return MessageBuilder.buildMessage(from: payload)
    }

    private func createCommitShareMessage(commit: Commit, userId: String) async throws -> MSMessage {
        let slug = generateSlug()

        let creatorName = supabase.currentUser?.userMetadata["display_name"]?.stringValue ?? supabase.currentUser?.email
        let row: [String: String?] = [
            "id": UUID().uuidString,
            "slug": slug,
            "user_id": userId,
            "share_type": "commit",
            "commit_hash": commit.hash,
            "commit_name": commit.name,
            "commit_short_id": commit.shortId,
            "creator_name": creatorName,
            "is_active": "true",
            "view_count": "0"
        ]

        try await supabase.client
            .from("share_links")
            .insert(row)
            .execute()

        let payload = PayloadBuilder.buildPayload(
            slug: slug,
            shareType: "commit",
            title: commit.name ?? "Snapshot",
            sections: [],
            handleNames: [],
            creatorName: supabase.currentUser?.userMetadata["display_name"]?.stringValue,
            commitHash: commit.hash,
            commitShortId: commit.shortId
        )

        return MessageBuilder.buildMessage(from: payload)
    }

    private func generateSlug() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<8).map { _ in chars.randomElement()! })
    }
}

// MARK: - Search Result

enum SearchResult: Identifiable {
    case handle(Handle)
    case commit(Commit)
    case note(Note)

    var id: String {
        switch self {
        case .handle(let h): return "handle_\(h.id)"
        case .commit(let c): return "commit_\(c.id)"
        case .note(let n): return "note_\(n.id)"
        }
    }
}
