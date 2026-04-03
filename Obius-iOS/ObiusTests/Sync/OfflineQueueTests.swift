import XCTest
@testable import Obius

final class OfflineQueueTests: XCTestCase {
    var database: DatabaseManager!
    var noteRepository: NoteRepository!
    var sectionRepository: SectionRepository!
    var logger: SyncOperationLogger!

    override func setUp() async throws {
        try await super.setUp()
        database = try DatabaseManager(inMemory: true)
        noteRepository = await NoteRepository(database: database)
        sectionRepository = await SectionRepository(database: database)
        logger = SyncOperationLogger(database: database)
    }

    override func tearDown() async throws {
        logger = nil
        sectionRepository = nil
        noteRepository = nil
        database = nil
        try await super.tearDown()
    }

    // MARK: - Operation Logging

    func testLogNoteCreate_queuesOperation() async throws {
        let note = try await noteRepository.createNote(title: "Offline Note")
        await logger.logNoteCreateSync(note)

        let ops = try await fetchPendingOperations()
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.entityType, "note")
        XCTAssertEqual(ops.first?.entityId, note.id)
        XCTAssertEqual(ops.first?.operationType, "create")
        XCTAssertFalse(ops.first?.synced ?? true)
    }

    func testLogSectionCreate_queuesOperation() async throws {
        let note = try await noteRepository.createNote()
        let section = try await sectionRepository.createSection(noteId: note.id, content: "Offline Section")
        await logger.logSectionCreateSync(section)

        let ops = try await fetchPendingOperations()
        let sectionOps = ops.filter { $0.entityType == "section" }
        XCTAssertEqual(sectionOps.count, 1)
        XCTAssertEqual(sectionOps.first?.entityId, section.id)
    }

    func testLogNoteUpdate_queuesOperation() async throws {
        let note = try await noteRepository.createNote(title: "Original")
        await logger.logNoteUpdateSync(note)

        let ops = try await fetchPendingOperations()
        let updateOps = ops.filter { $0.operationType == "update" }
        XCTAssertGreaterThanOrEqual(updateOps.count, 1)
    }

    func testLogNoteDelete_queuesOperation() async throws {
        let note = try await noteRepository.createNote()
        logger.logNoteDelete(note.id)

        try await Task.sleep(nanoseconds: 200_000_000)

        let ops = try await fetchPendingOperations()
        let deleteOps = ops.filter { $0.operationType == "delete" && $0.entityId == note.id }
        XCTAssertEqual(deleteOps.count, 1)
    }

    // MARK: - Queue Ordering

    func testOperations_orderedByTimestamp() async throws {
        let note1 = try await noteRepository.createNote(title: "First")
        await logger.logNoteCreateSync(note1)

        try await Task.sleep(nanoseconds: 50_000_000) // 50ms gap

        let note2 = try await noteRepository.createNote(title: "Second")
        await logger.logNoteCreateSync(note2)

        let ops = try await fetchPendingOperations()
        let noteOps = ops.filter { $0.entityType == "note" }
        XCTAssertGreaterThanOrEqual(noteOps.count, 2)

        // Verify ordering
        if noteOps.count >= 2 {
            XCTAssertLessThanOrEqual(noteOps[0].timestamp, noteOps[1].timestamp)
        }
    }

    // MARK: - Queue Persistence

    func testPendingOps_persistAcrossReads() async throws {
        let note = try await noteRepository.createNote()
        await logger.logNoteCreateSync(note)

        let count1 = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncOperations WHERE synced = 0")
        }

        // Read again — should be the same
        let count2 = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncOperations WHERE synced = 0")
        }

        XCTAssertEqual(count1, count2)
        XCTAssertGreaterThan(count1 ?? 0, 0)
    }

    func testSyncedOps_notInPendingQueue() async throws {
        let note = try await noteRepository.createNote()
        await logger.logNoteCreateSync(note)

        // Mark as synced
        try await database.write { db in
            try db.execute(sql: "UPDATE syncOperations SET synced = 1 WHERE entityId = ?",
                           arguments: [note.id])
        }

        let pending = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncOperations WHERE synced = 0 AND entityId = ?",
                             arguments: [note.id])
        }
        XCTAssertEqual(pending, 0, "Synced operations should not appear as pending")
    }

    // MARK: - Deduplication

    func testDuplicateSync_updatesExisting() async throws {
        let note = try await noteRepository.createNote(title: "V1")
        await logger.logNoteCreateSync(note)

        // Log an update for the same entity
        await logger.logNoteUpdateSync(note)

        // The sync variant should deduplicate — removing old unsynced ops for the same entity
        let ops = try await fetchPendingOperations()
        let noteOps = ops.filter { $0.entityId == note.id }
        XCTAssertEqual(noteOps.count, 1, "Sync log should deduplicate operations for same entity")
    }

    // MARK: - Payload Content

    func testNotePayload_containsRequiredFields() async throws {
        let note = try await noteRepository.createNote(title: "Payload Test")
        try await noteRepository.updateNoteBody(note.id, body: "Body content")

        let updated = try await database.read { db in try Note.fetchOne(db, key: note.id)! }
        await logger.logNoteUpdateSync(updated)

        let ops = try await fetchPendingOperations()
        let noteOp = ops.first { $0.entityId == note.id }
        XCTAssertNotNil(noteOp)

        // Verify payload contains expected data
        let payload = noteOp!.payload
        XCTAssertTrue(payload.contains("Body content") || payload.contains("body"),
                      "Payload should contain note body or body field")
    }

    func testSectionPayload_containsContent() async throws {
        let note = try await noteRepository.createNote()
        let section = try await sectionRepository.createSection(noteId: note.id, content: "Section payload test")
        await logger.logSectionCreateSync(section)

        let ops = try await fetchPendingOperations()
        let sectionOp = ops.first { $0.entityId == section.id }
        XCTAssertNotNil(sectionOp)

        let payload = sectionOp!.payload
        XCTAssertTrue(payload.contains("Section payload test"),
                      "Section payload should contain content text")
    }

    // MARK: - Callback

    func testOnOperationLogged_callbackFires() async throws {
        var callbackFired = false
        logger.onOperationLogged = {
            callbackFired = true
        }

        let note = try await noteRepository.createNote()
        logger.logNoteCreate(note)

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(callbackFired, "onOperationLogged callback should fire after logging")
    }

    // MARK: - Multiple Entity Types

    func testQueue_handlesMultipleEntityTypes() async throws {
        let note = try await noteRepository.createNote()
        let section = try await sectionRepository.createSection(noteId: note.id, content: "Test")

        await logger.logNoteCreateSync(note)
        await logger.logSectionCreateSync(section)

        let ops = try await fetchPendingOperations()
        let entityTypes = Set(ops.map(\.entityType))
        XCTAssertTrue(entityTypes.contains("note"))
        XCTAssertTrue(entityTypes.contains("section"))
    }

    // MARK: - Helpers

    private func fetchPendingOperations() async throws -> [SyncOperationRecord] {
        try await database.read { db in
            try SyncOperationRecord.fetchAll(db, sql: """
                SELECT * FROM syncOperations WHERE synced = 0 ORDER BY timestamp
            """)
        }
    }
}
