import XCTest
@testable import Obius

final class SyncOperationLoggerTests: XCTestCase {
    var database: DatabaseManager!
    var logger: SyncOperationLogger!

    override func setUp() async throws {
        try await super.setUp()
        database = try DatabaseManager(inMemory: true)
        logger = SyncOperationLogger(database: database)
    }

    override func tearDown() async throws {
        logger = nil
        database = nil
        try await super.tearDown()
    }

    // MARK: - Note Operation Tests

    func testLogNoteCreate() async throws {
        let note = createTestNote()
        logger.logNoteCreate(note)

        // Wait for async operation
        try await Task.sleep(nanoseconds: 100_000_000)

        let operations = try await fetchPendingOperations()
        XCTAssertEqual(operations.count, 1)

        let op = operations.first!
        XCTAssertEqual(op.entityType, "note")
        XCTAssertEqual(op.entityId, note.id)
        XCTAssertEqual(op.operationType, "create")
        XCTAssertFalse(op.synced)
    }

    func testLogNoteUpdate() async throws {
        var note = createTestNote()
        note.title = "Updated Title"
        logger.logNoteUpdate(note)

        try await Task.sleep(nanoseconds: 100_000_000)

        let operations = try await fetchPendingOperations()
        XCTAssertEqual(operations.count, 1)

        let op = operations.first!
        XCTAssertEqual(op.operationType, "update")
        XCTAssertTrue(op.payload.contains("Updated Title"))
    }

    func testLogNoteDelete() async throws {
        let noteId = UUID().uuidString
        logger.logNoteDelete(noteId)

        try await Task.sleep(nanoseconds: 100_000_000)

        let operations = try await fetchPendingOperations()
        XCTAssertEqual(operations.count, 1)

        let op = operations.first!
        XCTAssertEqual(op.entityType, "note")
        XCTAssertEqual(op.entityId, noteId)
        XCTAssertEqual(op.operationType, "delete")
    }

    // MARK: - Section Operation Tests

    func testLogSectionCreate() async throws {
        let section = createTestSection()
        logger.logSectionCreate(section)

        try await Task.sleep(nanoseconds: 100_000_000)

        let operations = try await fetchPendingOperations()
        XCTAssertEqual(operations.count, 1)

        let op = operations.first!
        XCTAssertEqual(op.entityType, "section")
        XCTAssertEqual(op.entityId, section.id)
        XCTAssertEqual(op.operationType, "create")
    }

    func testLogSectionUpdate() async throws {
        var section = createTestSection()
        section.content = "Updated content"
        logger.logSectionUpdate(section)

        try await Task.sleep(nanoseconds: 100_000_000)

        let operations = try await fetchPendingOperations()
        XCTAssertEqual(operations.count, 1)

        let op = operations.first!
        XCTAssertEqual(op.operationType, "update")
        XCTAssertTrue(op.payload.contains("Updated content"))
    }

    func testLogSectionDelete() async throws {
        let sectionId = UUID().uuidString
        logger.logSectionDelete(sectionId)

        try await Task.sleep(nanoseconds: 100_000_000)

        let operations = try await fetchPendingOperations()
        XCTAssertEqual(operations.count, 1)

        let op = operations.first!
        XCTAssertEqual(op.entityType, "section")
        XCTAssertEqual(op.entityId, sectionId)
        XCTAssertEqual(op.operationType, "delete")
    }

    // MARK: - Multiple Operations

    func testMultipleOperations() async throws {
        let note = createTestNote()
        let section = createTestSection()

        logger.logNoteCreate(note)
        logger.logSectionCreate(section)
        logger.logNoteUpdate(note)

        try await Task.sleep(nanoseconds: 200_000_000)

        let operations = try await fetchPendingOperations()
        XCTAssertEqual(operations.count, 3)
    }

    func testOperationsHaveUniqueIds() async throws {
        let note = createTestNote()
        logger.logNoteCreate(note)
        logger.logNoteUpdate(note)

        try await Task.sleep(nanoseconds: 100_000_000)

        let operations = try await fetchPendingOperations()
        let operationIds = operations.map { $0.operationId }
        let uniqueIds = Set(operationIds)

        XCTAssertEqual(uniqueIds.count, operationIds.count)
    }

    func testOperationsHaveTimestamps() async throws {
        let note = createTestNote()
        logger.logNoteCreate(note)

        try await Task.sleep(nanoseconds: 100_000_000)

        let operations = try await fetchPendingOperations()
        XCTAssertTrue(operations.first!.timestamp > 0)
    }

    // MARK: - Payload Content Tests

    func testNotePayloadContainsAllFields() async throws {
        var note = createTestNote()
        note.title = "Test Title"
        note.aiTitle = "AI Generated Title"
        note.isPinned = true
        note.setIntent(.task)  // Using the new API

        logger.logNoteCreate(note)

        try await Task.sleep(nanoseconds: 100_000_000)

        let operations = try await fetchPendingOperations()
        let payload = operations.first!.payload

        XCTAssertTrue(payload.contains("Test Title"))
        XCTAssertTrue(payload.contains("AI Generated Title"))
        XCTAssertTrue(payload.contains("\"is_pinned\":true") || payload.contains("\"is_pinned\" : true"))
        // The legacy value for .task is "task"
        XCTAssertTrue(payload.contains("task"))
    }

    func testSectionPayloadContainsAllFields() async throws {
        var section = createTestSection()
        section.content = "Test content"
        section.contentType = .code
        section.indentLevel = 2
        section.isCollapsed = true
        section.setIntent(.idea)  // Using the new API

        logger.logSectionCreate(section)

        try await Task.sleep(nanoseconds: 100_000_000)

        let operations = try await fetchPendingOperations()
        let payload = operations.first!.payload

        XCTAssertTrue(payload.contains("Test content"))
        XCTAssertTrue(payload.contains("code"))
        XCTAssertTrue(payload.contains("idea"))
    }

    // MARK: - Helpers

    private func createTestNote() -> Note {
        Note(
            id: UUID().uuidString,
            title: nil,
            aiTitle: nil,
            isPinned: false,
            intent: .idea,
            localVersion: 1,
            serverVersion: nil,
            syncStatus: .pending
        )
    }

    private func createTestSection() -> Section {
        Section(
            id: UUID().uuidString,
            noteId: UUID().uuidString,
            content: "",
            contentType: .text,
            orderKey: "A",
            indentLevel: 0,
            isCollapsed: false,
            isLocked: false,
            intent: .idea,
            localVersion: 1,
            serverVersion: nil,
            syncStatus: .pending
        )
    }

    private func fetchPendingOperations() async throws -> [SyncOperationRecord] {
        try await database.read { db in
            try SyncOperationRecord.fetchAll(db)
        }
    }
}
