import Foundation
import GRDB
import Combine

/// Repository for managing Commit records in the Hot Store.
/// Commits are indexed here for quick lookups; actual content lives in Cold Store .obx files.
@MainActor
final class CommitRepository: ObservableObject {
    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - Create

    /// Saves a new commit record to the Hot Store.
    /// - Parameter commit: The commit to save
    func saveCommit(_ commit: Commit) async throws {
        try await database.write { db in
            try commit.insert(db, onConflict: .replace)
        }
    }

    // MARK: - Read

    /// Gets a commit by its ID.
    /// - Parameter id: The commit ID
    /// - Returns: The commit if found
    func getCommit(id: String) async throws -> Commit? {
        try await database.read { db in
            try Commit.fetchOne(db, key: id)
        }
    }

    /// Gets a commit by its hash.
    /// - Parameter hash: The commit hash (with or without "sha256:" prefix)
    /// - Returns: The commit if found
    func getCommit(hash: String) async throws -> Commit? {
        try await database.read { db in
            try Commit
                .filter(Commit.Columns.hash == hash)
                .fetchOne(db)
        }
    }

    /// Gets the latest (most recent) commit for a note.
    /// - Parameter noteId: The note ID
    /// - Returns: The most recent commit if any
    func getLatestCommit(noteId: String) async throws -> Commit? {
        try await database.read { db in
            try Commit
                .filter(Commit.Columns.noteId == noteId)
                .order(Commit.Columns.createdAt.desc)
                .fetchOne(db)
        }
    }

    /// Gets all commits for a note, ordered by creation time (newest first).
    /// - Parameter noteId: The note ID
    /// - Returns: Array of commits
    func getCommits(noteId: String) async throws -> [Commit] {
        try await database.read { db in
            try Commit
                .filter(Commit.Columns.noteId == noteId)
                .order(Commit.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Gets the commit count for a note.
    /// - Parameter noteId: The note ID
    /// - Returns: Number of commits
    func getCommitCount(noteId: String) async throws -> Int {
        try await database.read { db in
            try Commit
                .filter(Commit.Columns.noteId == noteId)
                .fetchCount(db)
        }
    }

    /// Gets all commits in the database.
    /// - Returns: Array of all commits
    func getAllCommits() async throws -> [Commit] {
        try await database.read { db in
            try Commit
                .order(Commit.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Delete

    /// Deletes a commit by ID.
    /// Note: This only removes the index; the .obx file in Cold Store remains.
    /// - Parameter id: The commit ID to delete
    func deleteCommit(id: String) async throws {
        try await database.write { db in
            _ = try Commit.deleteOne(db, key: id)
        }
    }

    /// Deletes a commit by hash.
    /// - Parameter hash: The commit hash to delete
    func deleteCommit(hash: String) async throws {
        try await database.write { db in
            _ = try Commit
                .filter(Commit.Columns.hash == hash)
                .deleteAll(db)
        }
    }

    /// Deletes all commits for a note.
    /// - Parameter noteId: The note ID whose commits to delete
    func deleteCommits(noteId: String) async throws {
        try await database.write { db in
            _ = try Commit
                .filter(Commit.Columns.noteId == noteId)
                .deleteAll(db)
        }
    }

    /// Deletes all commits from the database.
    func deleteAllCommits() async throws {
        try await database.write { db in
            _ = try Commit.deleteAll(db)
        }
    }

    // MARK: - Visibility

    /// Toggles the hidden state of a commit.
    func setHidden(_ isHidden: Bool, id: String) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE commits SET isHidden = ? WHERE id = ?",
                arguments: [isHidden, id]
            )
        }
    }

    /// Gets all visible (non-hidden) commits, ordered by creation time (newest first).
    func getVisibleCommits() async throws -> [Commit] {
        try await database.read { db in
            try Commit
                .filter(Commit.Columns.isHidden == false)
                .order(Commit.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Observation

    /// Observes commits for a specific note.
    /// - Parameter noteId: The note ID to observe
    /// - Returns: Publisher emitting commit arrays
    func observeCommits(noteId: String) -> AnyPublisher<[Commit], Error> {
        let observation = ValueObservation.tracking { db in
            try Commit
                .filter(Commit.Columns.noteId == noteId)
                .order(Commit.Columns.createdAt.desc)
                .fetchAll(db)
        }

        return observation
            .publisher(in: database.dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    // MARK: - Statistics

    /// Gets commit statistics for all notes.
    /// - Returns: Dictionary of noteId -> commit count
    func getCommitStats() async throws -> [String: Int] {
        try await database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT noteId, COUNT(*) as count
                FROM commits
                GROUP BY noteId
            """)

            var stats: [String: Int] = [:]
            for row in rows {
                if let noteId = row["noteId"] as String?,
                   let count = row["count"] as Int? {
                    stats[noteId] = count
                }
            }
            return stats
        }
    }

    /// Gets the total number of commits in the database.
    /// - Returns: Total commit count
    func getTotalCommitCount() async throws -> Int {
        try await database.read { db in
            try Commit.fetchCount(db)
        }
    }

    // MARK: - Chain Queries

    /// Finds commits that have no children (leaf commits).
    /// - Returns: Array of leaf commits (commits not referenced as parentHash by others)
    func getLeafCommits() async throws -> [Commit] {
        try await database.read { db in
            try Commit.fetchAll(db, sql: """
                SELECT c.* FROM commits c
                LEFT JOIN commits child ON child.parentHash = c.hash
                WHERE child.id IS NULL
                ORDER BY c.createdAt DESC
            """)
        }
    }

    /// Finds orphaned commits (commits whose parent doesn't exist in database).
    /// - Returns: Array of orphaned commits
    func getOrphanedCommits() async throws -> [Commit] {
        try await database.read { db in
            try Commit.fetchAll(db, sql: """
                SELECT c.* FROM commits c
                WHERE c.parentHash IS NOT NULL
                AND NOT EXISTS (
                    SELECT 1 FROM commits p WHERE p.hash = c.parentHash
                )
                ORDER BY c.createdAt DESC
            """)
        }
    }
}
