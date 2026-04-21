import Foundation
import GRDB
import CryptoKit

@MainActor
final class NoteIndexRepository: ObservableObject {
    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - Token Estimation

    /// Rough token count: ~4 bytes per token for English text.
    static func estimateTokens(_ text: String) -> Int {
        max(1, text.utf8.count / 4)
    }

    /// SHA-256 hash of content for change detection.
    private static func contentHash(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Full Reindex

    /// Rebuild the entire note_index from current DB state.
    /// Call on Workspace open or when significant changes occur.
    func reindex(
        notes: [Note],
        sectionsByNote: [String: [Section]],
        handles: [Handle]
    ) async {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        do {
            try await database.write { db in
                // Clear existing index
                try NoteIndex.deleteAll(db)

                // Index note bodies
                for note in notes where !note.isDeleted {
                    let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !body.isEmpty else { continue }
                    let entry = NoteIndex(
                        id: note.id,
                        entityType: .noteBody,
                        noteId: note.id,
                        contentHash: Self.contentHash(body),
                        tokenCount: Self.estimateTokens(body),
                        intent: note.intent.rawValue,
                        handleId: nil,
                        lastIndexedAt: now
                    )
                    try entry.insert(db)
                }

                // Index sections
                for (noteId, sections) in sectionsByNote {
                    for section in sections where section.deletedAt == nil {
                        let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !content.isEmpty else { continue }
                        // Skip binary content (images, audio, base64 RTF)
                        guard section.contentType == .text
                                || section.contentType == .checklist
                                || section.contentType == .quote
                                || section.contentType == .code else { continue }

                        let entry = NoteIndex(
                            id: section.id,
                            entityType: .section,
                            noteId: noteId,
                            contentHash: Self.contentHash(content),
                            tokenCount: Self.estimateTokens(content),
                            intent: section.intent.rawValue,
                            handleId: section.handleId,
                            lastIndexedAt: now
                        )
                        try entry.insert(db)
                    }
                }

                // Index handles
                for handle in handles where handle.deletedAt == nil {
                    let content = handle.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { continue }
                    let entry = NoteIndex(
                        id: handle.id,
                        entityType: .handle,
                        noteId: nil,
                        contentHash: Self.contentHash(content),
                        tokenCount: Self.estimateTokens(content),
                        intent: handle.intent.rawValue,
                        handleId: handle.id,
                        lastIndexedAt: now
                    )
                    try entry.insert(db)
                }
            }
            print("[NoteIndexRepo] Full reindex complete — notes: \(notes.count), handles: \(handles.count)")
        } catch {
            print("[NoteIndexRepo] Reindex failed: \(error)")
        }
    }

    // MARK: - Incremental Reindex

    /// Re-index a single note and its sections if content has changed.
    func reindexIfNeeded(note: Note, sections: [Section]) async {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        do {
            try await database.write { db in
                // Check/update note body
                let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
                let bodyHash = body.isEmpty ? "" : Self.contentHash(body)
                let existing = try NoteIndex.fetchOne(db, key: note.id)

                if !body.isEmpty {
                    if existing?.contentHash != bodyHash {
                        let entry = NoteIndex(
                            id: note.id,
                            entityType: .noteBody,
                            noteId: note.id,
                            contentHash: bodyHash,
                            tokenCount: Self.estimateTokens(body),
                            intent: note.intent.rawValue,
                            handleId: nil,
                            lastIndexedAt: now
                        )
                        try entry.save(db)
                    }
                } else if existing != nil {
                    try NoteIndex.deleteOne(db, key: note.id)
                }

                // Check/update sections
                let existingSectionIds = try NoteIndex
                    .filter(NoteIndex.Columns.noteId == note.id)
                    .filter(NoteIndex.Columns.entityType == NoteIndex.EntityType.section.rawValue)
                    .fetchAll(db)
                    .map(\.id)
                let existingSet = Set(existingSectionIds)

                let activeSections = sections.filter { $0.deletedAt == nil }
                let activeIds = Set(activeSections.map(\.id))

                // Remove deleted sections from index
                for id in existingSet where !activeIds.contains(id) {
                    try NoteIndex.deleteOne(db, key: id)
                }

                // Upsert active sections
                for section in activeSections {
                    let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { continue }
                    guard section.contentType == .text
                            || section.contentType == .checklist
                            || section.contentType == .quote
                            || section.contentType == .code else { continue }

                    let hash = Self.contentHash(content)
                    let existingEntry = try NoteIndex.fetchOne(db, key: section.id)
                    if existingEntry?.contentHash != hash {
                        let entry = NoteIndex(
                            id: section.id,
                            entityType: .section,
                            noteId: note.id,
                            contentHash: hash,
                            tokenCount: Self.estimateTokens(content),
                            intent: section.intent.rawValue,
                            handleId: section.handleId,
                            lastIndexedAt: now
                        )
                        try entry.save(db)
                    }
                }
            }
        } catch {
            print("[NoteIndexRepo] Incremental reindex failed: \(error)")
        }
    }

    // MARK: - Search

    /// Keyword search using FTS5 joined with note_index for token counts.
    /// Returns (sectionId, noteId, tokenCount) tuples ranked by BM25.
    func search(query: String, limit: Int = 15, excludeNoteId: String? = nil) async -> [(id: String, noteId: String?, tokenCount: Int)] {
        do {
            return try await database.read { db in
                let pattern = FTS5Pattern(matchingAllTokensIn: query)
                guard let pattern = pattern else { return [] }

                var sql = """
                    SELECT ni.id, ni.noteId, ni.tokenCount
                    FROM note_index ni
                    JOIN sections s ON s.id = ni.id
                    JOIN sections_fts ON s.rowid = sections_fts.rowid
                    WHERE sections_fts MATCH ?
                    AND ni.entityType = 'section'
                    AND s.deletedAt IS NULL
                """
                var arguments: [DatabaseValueConvertible] = [pattern]

                if let excludeId = excludeNoteId {
                    sql += " AND ni.noteId != ?"
                    arguments.append(excludeId)
                }

                sql += " ORDER BY bm25(sections_fts) LIMIT ?"
                arguments.append(limit)

                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
                return rows.map { row in
                    (
                        id: row["id"] as String,
                        noteId: row["noteId"] as String?,
                        tokenCount: row["tokenCount"] as Int
                    )
                }
            }
        } catch {
            print("[NoteIndexRepo] Search failed: \(error)")
            return []
        }
    }

    /// Get total indexed token count for a note (body + all sections).
    func tokenCount(forNote noteId: String) async -> Int {
        do {
            return try await database.read { db in
                let row = try Row.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(tokenCount), 0) as total
                    FROM note_index WHERE noteId = ?
                """, arguments: [noteId])
                return row?["total"] as? Int ?? 0
            }
        } catch {
            return 0
        }
    }
}
