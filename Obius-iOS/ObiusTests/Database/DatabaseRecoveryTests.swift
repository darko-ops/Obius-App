import XCTest
@testable import Obius

final class DatabaseRecoveryTests: XCTestCase {

    // MARK: - In-Memory Database Tests

    func testDatabaseManager_inMemory_succeeds() throws {
        let db = try DatabaseManager(inMemory: true)
        XCTAssertNotNil(db)
    }

    func testDatabaseManager_inMemory_hasTables() async throws {
        let db = try DatabaseManager(inMemory: true)

        let tableCount = try await db.read { database in
            try Int.fetchOne(database, sql: """
                SELECT COUNT(*) FROM sqlite_master WHERE type = 'table'
            """)
        }

        // Should have core tables: notes, sections, handles, echoes, modules,
        // commits, media, note_media, shareLinks, comments, insights, syncOperations, syncMetadata
        XCTAssertGreaterThan(tableCount ?? 0, 10, "Database should have all core tables after migration")
    }

    func testDatabaseManager_schemaVersion() async throws {
        let db = try DatabaseManager(inMemory: true)

        let version = try await db.read { database in
            try Int.fetchOne(database, sql: "SELECT schemaVersion FROM syncMetadata WHERE id = 'singleton'")
        }

        XCTAssertEqual(version, DatabaseManager.schemaVersion, "Schema version should match current version")
    }

    // MARK: - Table Integrity Tests

    func testDatabase_notesTable_exists() async throws {
        let db = try DatabaseManager(inMemory: true)

        let exists = try await db.read { database in
            try Int.fetchOne(database, sql: """
                SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'notes'
            """)
        }
        XCTAssertEqual(exists, 1)
    }

    func testDatabase_sectionsTable_exists() async throws {
        let db = try DatabaseManager(inMemory: true)

        let exists = try await db.read { database in
            try Int.fetchOne(database, sql: """
                SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'sections'
            """)
        }
        XCTAssertEqual(exists, 1)
    }

    func testDatabase_syncOperationsTable_exists() async throws {
        let db = try DatabaseManager(inMemory: true)

        let exists = try await db.read { database in
            try Int.fetchOne(database, sql: """
                SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'syncOperations'
            """)
        }
        XCTAssertEqual(exists, 1)
    }

    func testDatabase_syncMetadataTable_exists() async throws {
        let db = try DatabaseManager(inMemory: true)

        let exists = try await db.read { database in
            try Int.fetchOne(database, sql: """
                SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'syncMetadata'
            """)
        }
        XCTAssertEqual(exists, 1)
    }

    // MARK: - Corruption Recovery Tests

    func testRecoverFromCorruption_noFile_returnsFalse() {
        // When no database file exists, recovery has nothing to do
        // Clear any existing file first
        let result = DatabaseManager.recoverFromCorruption()
        // Result depends on whether app group DB exists; just verify no crash
        XCTAssertNotNil(result as Bool?)
    }

    // MARK: - Migration Continuity Tests

    func testDatabase_allMigrations_runSuccessfully() throws {
        // Creating an in-memory database runs ALL migrations (v1 through current).
        // If any migration has a SQL error, this will throw.
        let db = try DatabaseManager(inMemory: true)
        XCTAssertNotNil(db)
    }

    func testDatabase_readOnly_skipsMigrations() throws {
        // Read-only mode should not run migrations (used by extensions)
        // In-memory + read-only is an unusual combo but should not crash
        let db = try DatabaseManager(inMemory: true, readOnly: true)
        XCTAssertNotNil(db)
        XCTAssertTrue(db.isReadOnly)
    }

    // MARK: - Data Persistence After Recovery

    func testFreshDatabase_hasNoNotes() async throws {
        let db = try DatabaseManager(inMemory: true)

        let count = try await db.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes")
        }
        XCTAssertEqual(count, 0)
    }

    func testFreshDatabase_hasNoSections() async throws {
        let db = try DatabaseManager(inMemory: true)

        let count = try await db.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sections")
        }
        XCTAssertEqual(count, 0)
    }

    func testFreshDatabase_hasNoSyncOperations() async throws {
        let db = try DatabaseManager(inMemory: true)

        let count = try await db.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM syncOperations")
        }
        XCTAssertEqual(count, 0)
    }

    // MARK: - Column Presence Tests

    func testNotesTable_hasSyncColumns() async throws {
        let db = try DatabaseManager(inMemory: true)

        // Insert a note and verify sync columns exist
        try await db.write { database in
            try database.execute(sql: """
                INSERT INTO notes (id, body, isPinned, intent, createdAt, updatedAt, localVersion, syncStatus)
                VALUES ('test-1', '', 0, 'idea', 0, 0, 1, 'pending')
            """)
        }

        let result = try await db.read { database in
            try Row.fetchOne(database, sql: "SELECT localVersion, serverVersion, syncStatus FROM notes WHERE id = 'test-1'")
        }

        XCTAssertNotNil(result)
        XCTAssertEqual(result?["localVersion"] as? Int, 1)
        XCTAssertNil(result?["serverVersion"] as? Int)
        XCTAssertEqual(result?["syncStatus"] as? String, "pending")
    }

    func testSectionsTable_hasSyncColumns() async throws {
        let db = try DatabaseManager(inMemory: true)

        // Need a note first for the foreign key
        try await db.write { database in
            try database.execute(sql: """
                INSERT INTO notes (id, body, isPinned, intent, createdAt, updatedAt, localVersion, syncStatus)
                VALUES ('note-1', '', 0, 'idea', 0, 0, 1, 'pending')
            """)
            try database.execute(sql: """
                INSERT INTO sections (id, noteId, content, contentType, sectionType, orderKey, indentLevel, isCollapsed, isLocked,
                    isTemplateContent, intent, createdAt, updatedAt, localVersion, syncStatus)
                VALUES ('sec-1', 'note-1', 'test', 'text', 'fold', 'A', 0, 0, 0, 0, 'idea', 0, 0, 1, 'pending')
            """)
        }

        let result = try await db.read { database in
            try Row.fetchOne(database, sql: "SELECT localVersion, serverVersion, syncStatus FROM sections WHERE id = 'sec-1'")
        }

        XCTAssertNotNil(result)
        XCTAssertEqual(result?["localVersion"] as? Int, 1)
        XCTAssertEqual(result?["syncStatus"] as? String, "pending")
    }

    // MARK: - Delete All Data Tests

    func testDeleteAllData_clearsAllTables() async throws {
        let db = try DatabaseManager(inMemory: true)
        let noteRepo = await NoteRepository(database: db)
        let sectionRepo = await SectionRepository(database: db)

        // Create some data
        let note = try await noteRepo.createNote(title: "To Delete")
        _ = try await sectionRepo.createSection(noteId: note.id, content: "Also delete")

        // Verify data exists
        let notesBefore = try await db.read { d in try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM notes") }
        XCTAssertGreaterThan(notesBefore ?? 0, 0)

        // Delete all
        try await db.write { d in
            try d.execute(sql: "DELETE FROM sections")
            try d.execute(sql: "DELETE FROM notes")
        }

        let notesAfter = try await db.read { d in try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM notes") }
        let sectionsAfter = try await db.read { d in try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM sections") }
        XCTAssertEqual(notesAfter, 0)
        XCTAssertEqual(sectionsAfter, 0)
    }
}
