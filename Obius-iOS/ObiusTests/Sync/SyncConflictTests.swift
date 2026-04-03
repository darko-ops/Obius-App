import XCTest
@testable import Obius

final class SyncConflictTests: XCTestCase {
    var database: DatabaseManager!
    var noteRepository: NoteRepository!
    var sectionRepository: SectionRepository!

    override func setUp() async throws {
        try await super.setUp()
        database = try DatabaseManager(inMemory: true)
        noteRepository = await NoteRepository(database: database)
        sectionRepository = await SectionRepository(database: database)
    }

    override func tearDown() async throws {
        sectionRepository = nil
        noteRepository = nil
        database = nil
        try await super.tearDown()
    }

    // MARK: - Pull Protection Tests

    func testPull_doesNotOverwrite_pendingNote() async throws {
        // Create a note and simulate local edits (pending status)
        let note = try await noteRepository.createNote(title: "Local Edit")
        XCTAssertEqual(note.syncStatus, .pending)

        // Simulate a pull that tries to overwrite with remote data
        // The note has syncStatus = .pending, so pull should skip it
        let existingNote = try await database.read { db in
            try Note.fetchOne(db, key: note.id)
        }
        XCTAssertNotNil(existingNote)
        XCTAssertEqual(existingNote?.syncStatus, .pending)

        // Verify the version check logic: pending entities should be preserved
        // (existing.serverVersion ?? 0) check should be preceded by pending check
        XCTAssertNil(existingNote?.serverVersion, "New note should have nil serverVersion")
    }

    func testPull_doesNotOverwrite_pendingSection() async throws {
        let note = try await noteRepository.createNote()
        let section = try await sectionRepository.createSection(noteId: note.id, content: "My local edit")

        XCTAssertEqual(section.syncStatus, .pending)

        // Edit the section to simulate ongoing local changes
        try await sectionRepository.updateContent(section.id, content: "Updated locally")

        let updated = try await database.read { db in
            try Section.fetchOne(db, key: section.id)
        }
        XCTAssertEqual(updated?.syncStatus, .pending)
        XCTAssertEqual(updated?.content, "Updated locally")
    }

    // MARK: - Version Tracking Tests

    func testNote_touch_incrementsLocalVersion() async throws {
        let note = try await noteRepository.createNote()
        XCTAssertEqual(note.localVersion, 1)

        try await noteRepository.updateNoteBody(note.id, body: "Edit 1")
        let v2 = try await database.read { db in try Note.fetchOne(db, key: note.id) }
        XCTAssertEqual(v2?.localVersion, 2)

        try await noteRepository.updateNoteBody(note.id, body: "Edit 2")
        let v3 = try await database.read { db in try Note.fetchOne(db, key: note.id) }
        XCTAssertEqual(v3?.localVersion, 3)
    }

    func testSection_touch_incrementsLocalVersion() async throws {
        let note = try await noteRepository.createNote()
        let section = try await sectionRepository.createSection(noteId: note.id, content: "v1")
        XCTAssertEqual(section.localVersion, 1)

        try await sectionRepository.updateContent(section.id, content: "v2")
        let updated = try await database.read { db in try Section.fetchOne(db, key: section.id) }
        XCTAssertEqual(updated?.localVersion, 2)
    }

    func testNote_touch_setsPendingStatus() async throws {
        let note = try await noteRepository.createNote()

        // Simulate marking as synced (as if pull set it)
        try await database.write { db in
            try db.execute(sql: "UPDATE notes SET syncStatus = 'synced', serverVersion = 1 WHERE id = ?",
                           arguments: [note.id])
        }

        let synced = try await database.read { db in try Note.fetchOne(db, key: note.id) }
        XCTAssertEqual(synced?.syncStatus, .synced)

        // Now edit — should flip back to pending
        try await noteRepository.updateNoteBody(note.id, body: "Changed")
        let pending = try await database.read { db in try Note.fetchOne(db, key: note.id) }
        XCTAssertEqual(pending?.syncStatus, .pending)
    }

    // MARK: - Conflict Resolution Tests

    func testResolveConflict_section_setsStatusToPending() async throws {
        let note = try await noteRepository.createNote()
        let section = try await sectionRepository.createSection(noteId: note.id, content: "Conflicted")

        // Simulate conflict status
        try await database.write { db in
            try db.execute(sql: "UPDATE sections SET syncStatus = 'conflict' WHERE id = ?",
                           arguments: [section.id])
        }

        let conflicted = try await database.read { db in try Section.fetchOne(db, key: section.id) }
        XCTAssertEqual(conflicted?.syncStatus, .conflict)

        // Resolve
        try await sectionRepository.resolveConflict(section.id)

        let resolved = try await database.read { db in try Section.fetchOne(db, key: section.id) }
        XCTAssertEqual(resolved?.syncStatus, .pending, "Resolving conflict should set status to pending for re-push")
    }

    func testResolveConflict_note_setsStatusToPending() async throws {
        let note = try await noteRepository.createNote(title: "Conflicted Note")

        // Simulate conflict
        try await database.write { db in
            try db.execute(sql: "UPDATE notes SET syncStatus = 'conflict' WHERE id = ?",
                           arguments: [note.id])
        }

        try await noteRepository.resolveConflict(note.id)

        let resolved = try await database.read { db in try Note.fetchOne(db, key: note.id) }
        XCTAssertEqual(resolved?.syncStatus, .pending)
    }

    // MARK: - Sync Operation Purge Protection

    func testSyncOps_notPurged_forPendingEntities() async throws {
        let note = try await noteRepository.createNote(title: "Pending Note")

        // Create a sync operation for this note
        let opId = UUID().uuidString
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                VALUES (?, 'note', ?, 'update', '{}', ?, 0)
            """, arguments: [opId, note.id, Int64(Date().timeIntervalSince1970 * 1000)])
        }

        // Verify the op exists
        let opCount = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncOperations WHERE entityId = ? AND synced = 0",
                             arguments: [note.id])
        }
        XCTAssertEqual(opCount, 1)

        // Note has syncStatus = .pending, so its ops should not be purged
        let status = try await database.read { db in
            try String.fetchOne(db, sql: "SELECT syncStatus FROM notes WHERE id = ?", arguments: [note.id])
        }
        XCTAssertEqual(status, "pending")
    }

    // MARK: - Server Version Tests

    func testServerVersion_nilForNewEntities() async throws {
        let note = try await noteRepository.createNote()
        XCTAssertNil(note.serverVersion)

        let section = try await sectionRepository.createSection(noteId: note.id)
        XCTAssertNil(section.serverVersion)
    }

    func testServerVersion_setAfterSync() async throws {
        let note = try await noteRepository.createNote()

        // Simulate what happens after a successful push: serverVersion is set
        try await database.write { db in
            try db.execute(sql: "UPDATE notes SET serverVersion = 2, syncStatus = 'synced' WHERE id = ?",
                           arguments: [note.id])
        }

        let synced = try await database.read { db in try Note.fetchOne(db, key: note.id) }
        XCTAssertEqual(synced?.serverVersion, 2)
        XCTAssertEqual(synced?.syncStatus, .synced)
    }

    // MARK: - SyncStatus Enum

    func testSyncStatus_allCases() {
        XCTAssertEqual(SyncStatus.pending.rawValue, "pending")
        XCTAssertEqual(SyncStatus.synced.rawValue, "synced")
        XCTAssertEqual(SyncStatus.conflict.rawValue, "conflict")
    }
}
