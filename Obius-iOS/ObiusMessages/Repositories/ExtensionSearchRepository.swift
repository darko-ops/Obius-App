import Foundation
import GRDB

/// Read-only search queries for the iMessage extension compact view.
/// All queries use LIMIT clauses to stay within the extension's 120MB memory cap.
enum ExtensionSearchRepository {

    private static var db: ExtensionDatabaseReader { .shared }

    // MARK: - Search

    /// Search handles by name (case-insensitive prefix match)
    static func searchHandles(query: String) -> [Handle] {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        return db.read { db in
            try Handle
                .filter(Handle.Columns.deletedAt == nil)
                .filter(Handle.Columns.name.like("%\(normalized)%"))
                .order(Handle.Columns.updatedAt.desc)
                .limit(10)
                .fetchAll(db)
        } ?? []
    }

    /// Search commits by name or shortId
    static func searchCommits(query: String) -> [Commit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return db.read { db in
            try Commit
                .filter(
                    Commit.Columns.name.like("%\(trimmed)%") ||
                    Commit.Columns.shortId.like("%\(trimmed.uppercased())%")
                )
                .order(Commit.Columns.createdAt.desc)
                .limit(10)
                .fetchAll(db)
        } ?? []
    }

    /// Full-text search on sections via FTS5, returning parent notes
    static func searchNotes(query: String) -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return db.read { db in
            let pattern = FTS5Pattern(matchingAllTokensIn: trimmed)
            guard let pattern else { return [] }

            // Search sections via FTS, get distinct noteIds
            let sql = """
                SELECT DISTINCT sections.noteId
                FROM sections
                JOIN sections_fts ON sections.rowid = sections_fts.rowid
                WHERE sections_fts MATCH ?
                AND sections.deletedAt IS NULL
                ORDER BY bm25(sections_fts)
                LIMIT 10
            """
            let noteIds = try String.fetchAll(db, sql: sql, arguments: [pattern.rawPattern])

            guard !noteIds.isEmpty else {
                // Also try matching note titles directly
                return try Note
                    .filter(Note.Columns.deletedAt == nil)
                    .filter(
                        Note.Columns.title.like("%\(trimmed)%") ||
                        Note.Columns.aiTitle.like("%\(trimmed)%")
                    )
                    .order(Note.Columns.updatedAt.desc)
                    .limit(10)
                    .fetchAll(db)
            }

            return try Note
                .filter(noteIds.contains(Note.Columns.id))
                .filter(Note.Columns.deletedAt == nil)
                .order(Note.Columns.updatedAt.desc)
                .fetchAll(db)
        } ?? []
    }

    // MARK: - Single Lookups

    static func getNote(id: String) -> Note? {
        guard let result = db.read({ db in
            try Note.filter(Note.Columns.id == id).fetchOne(db)
        }) else { return nil }
        return result
    }

    static func getSections(noteId: String) -> [Section] {
        db.read { db in
            try Section
                .filter(Section.Columns.noteId == noteId)
                .filter(Section.Columns.deletedAt == nil)
                .order(Section.Columns.orderKey)
                .fetchAll(db)
        } ?? []
    }

    static func getHandlesForNote(noteId: String) -> [Handle] {
        db.read { db in
            // Get handleIds from sections of this note
            let handleIds = try String.fetchAll(db, sql: """
                SELECT DISTINCT handleId FROM sections
                WHERE noteId = ? AND handleId IS NOT NULL AND deletedAt IS NULL
            """, arguments: [noteId])

            guard !handleIds.isEmpty else { return [] }

            return try Handle
                .filter(handleIds.contains(Handle.Columns.id))
                .filter(Handle.Columns.deletedAt == nil)
                .fetchAll(db)
        } ?? []
    }

    /// Get recent notes for showing when search is empty
    static func getRecentNotes(limit: Int = 5) -> [Note] {
        db.read { db in
            try Note
                .filter(Note.Columns.deletedAt == nil)
                .order(Note.Columns.updatedAt.desc)
                .limit(limit)
                .fetchAll(db)
        } ?? []
    }
}
