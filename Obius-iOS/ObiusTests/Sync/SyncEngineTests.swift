import XCTest
@testable import Obius

final class SyncEngineTests: XCTestCase {
    var database: DatabaseManager!

    override func setUp() async throws {
        try await super.setUp()
        database = try DatabaseManager(inMemory: true)
    }

    override func tearDown() async throws {
        database = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testSyncEngine_initialState() async throws {
        let engine = SyncEngine(database: database)
        let state = await engine.syncState

        XCTAssertEqual(state, .idle)
    }

    func testSyncEngine_initialize_createsDeviceId() async throws {
        let engine = SyncEngine(database: database)
        await engine.initialize()

        // Check device ID was created in database
        let deviceId = try await database.read { db in
            try String.fetchOne(db, sql: "SELECT deviceId FROM syncMetadata WHERE id = 'singleton'")
        }

        XCTAssertNotNil(deviceId)
        XCTAssertFalse(deviceId!.isEmpty)
    }

    func testSyncEngine_initialize_deviceIdPersists() async throws {
        let engine1 = SyncEngine(database: database)
        await engine1.initialize()

        let deviceId1 = try await database.read { db in
            try String.fetchOne(db, sql: "SELECT deviceId FROM syncMetadata WHERE id = 'singleton'")
        }

        // Create new engine instance
        let engine2 = SyncEngine(database: database)
        await engine2.initialize()

        let deviceId2 = try await database.read { db in
            try String.fetchOne(db, sql: "SELECT deviceId FROM syncMetadata WHERE id = 'singleton'")
        }

        XCTAssertEqual(deviceId1, deviceId2)
    }

    // MARK: - SyncState Tests

    func testSyncState_equality() {
        XCTAssertEqual(SyncEngine.SyncState.idle, SyncEngine.SyncState.idle)
        XCTAssertEqual(SyncEngine.SyncState.syncing, SyncEngine.SyncState.syncing)
        XCTAssertEqual(SyncEngine.SyncState.offline, SyncEngine.SyncState.offline)
        XCTAssertEqual(SyncEngine.SyncState.error("test"), SyncEngine.SyncState.error("test"))
        XCTAssertNotEqual(SyncEngine.SyncState.error("a"), SyncEngine.SyncState.error("b"))
        XCTAssertNotEqual(SyncEngine.SyncState.idle, SyncEngine.SyncState.syncing)
    }

    // MARK: - SyncError Tests

    func testSyncError_notInitialized() {
        let error = SyncError.notInitialized
        XCTAssertEqual(error.errorDescription, "Sync engine not initialized")
    }

    func testSyncError_offline() {
        let error = SyncError.offline
        XCTAssertEqual(error.errorDescription, "No internet connection")
    }

    func testSyncError_aiError() {
        let error = SyncError.aiError("Model unavailable")
        XCTAssertEqual(error.errorDescription, "AI error: Model unavailable")
    }

    func testSyncError_serverError() {
        let error = SyncError.serverError("Internal server error")
        XCTAssertEqual(error.errorDescription, "Server error: Internal server error")
    }

    // MARK: - SyncOperationRecord Tests

    func testSyncOperationRecord_tableName() {
        XCTAssertEqual(SyncOperationRecord.databaseTableName, "syncOperations")
    }

    func testSyncOperationRecord_insertAndFetch() async throws {
        // Insert a test operation
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                VALUES (?, ?, ?, ?, ?, ?, 0)
            """, arguments: [
                "op-123",
                "note",
                "note-456",
                "create",
                "{\"title\":\"Test\"}",
                Int64(Date().timeIntervalSince1970 * 1000)
            ])
        }

        let records = try await database.read { db in
            try SyncOperationRecord.fetchAll(db)
        }

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.operationId, "op-123")
        XCTAssertEqual(records.first?.entityType, "note")
        XCTAssertEqual(records.first?.entityId, "note-456")
        XCTAssertEqual(records.first?.operationType, "create")
        XCTAssertEqual(records.first?.payload, "{\"title\":\"Test\"}")
        XCTAssertFalse(records.first?.synced ?? true)
    }

    func testSyncOperationRecord_filterBySynced() async throws {
        // Insert multiple operations with different sync status
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                VALUES (?, ?, ?, ?, ?, ?, 0)
            """, arguments: ["op-1", "note", "n-1", "create", "{}", 1000])

            try db.execute(sql: """
                INSERT INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                VALUES (?, ?, ?, ?, ?, ?, 1)
            """, arguments: ["op-2", "note", "n-2", "create", "{}", 2000])

            try db.execute(sql: """
                INSERT INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                VALUES (?, ?, ?, ?, ?, ?, 0)
            """, arguments: ["op-3", "section", "s-1", "update", "{}", 3000])
        }

        let pending = try await database.read { db in
            try SyncOperationRecord
                .filter(Column("synced") == false)
                .fetchAll(db)
        }

        XCTAssertEqual(pending.count, 2)
    }

    func testSyncOperationRecord_orderedByTimestamp() async throws {
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                VALUES (?, ?, ?, ?, ?, ?, 0)
            """, arguments: ["op-3", "note", "n-3", "create", "{}", 3000])

            try db.execute(sql: """
                INSERT INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                VALUES (?, ?, ?, ?, ?, ?, 0)
            """, arguments: ["op-1", "note", "n-1", "create", "{}", 1000])

            try db.execute(sql: """
                INSERT INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                VALUES (?, ?, ?, ?, ?, ?, 0)
            """, arguments: ["op-2", "note", "n-2", "create", "{}", 2000])
        }

        let ordered = try await database.read { db in
            try SyncOperationRecord
                .order(Column("timestamp"))
                .fetchAll(db)
        }

        XCTAssertEqual(ordered.map { $0.operationId }, ["op-1", "op-2", "op-3"])
    }

    // MARK: - Sync Timestamp Tests

    func testSyncTimestamp_initiallyNil() async throws {
        let timestamp = try await database.read { db in
            try Int64.fetchOne(db, sql: "SELECT lastSyncTimestamp FROM syncMetadata WHERE id = 'singleton'")
        }

        // No metadata row exists initially
        XCTAssertNil(timestamp)
    }

    func testSyncTimestamp_storedAfterInitialize() async throws {
        let engine = SyncEngine(database: database)
        await engine.initialize()

        let timestamp = try await database.read { db in
            try Int64.fetchOne(db, sql: "SELECT lastSyncTimestamp FROM syncMetadata WHERE id = 'singleton'")
        }

        XCTAssertNotNil(timestamp)
        XCTAssertEqual(timestamp, 0) // Initial value
    }

    func testSyncTimestamp_update() async throws {
        // First initialize
        let engine = SyncEngine(database: database)
        await engine.initialize()

        // Update timestamp
        let newTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        try await database.write { db in
            try db.execute(sql: """
                UPDATE syncMetadata SET lastSyncTimestamp = ? WHERE id = 'singleton'
            """, arguments: [newTimestamp])
        }

        let stored = try await database.read { db in
            try Int64.fetchOne(db, sql: "SELECT lastSyncTimestamp FROM syncMetadata WHERE id = 'singleton'")
        }

        XCTAssertEqual(stored, newTimestamp)
    }

    // MARK: - Pending Changes Count Tests

    func testPendingChangesCount_initiallyZero() async throws {
        let engine = SyncEngine(database: database)
        await engine.initialize()

        let count = await engine.pendingChangesCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Database Schema Tests

    func testSyncMetadataTable_exists() async throws {
        let tables = try await database.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type='table' AND name='syncMetadata'
            """)
        }

        XCTAssertTrue(tables.contains("syncMetadata"))
    }

    func testSyncOperationsTable_exists() async throws {
        let tables = try await database.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type='table' AND name='syncOperations'
            """)
        }

        XCTAssertTrue(tables.contains("syncOperations"))
    }

    func testSyncOperationsTable_schema() async throws {
        let columns = try await database.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(syncOperations)")
        }

        let columnNames = columns.map { $0["name"] as! String }

        XCTAssertTrue(columnNames.contains("id"))
        XCTAssertTrue(columnNames.contains("operationId"))
        XCTAssertTrue(columnNames.contains("entityType"))
        XCTAssertTrue(columnNames.contains("entityId"))
        XCTAssertTrue(columnNames.contains("operationType"))
        XCTAssertTrue(columnNames.contains("payload"))
        XCTAssertTrue(columnNames.contains("timestamp"))
        XCTAssertTrue(columnNames.contains("synced"))
    }
}

// MARK: - Integration Tests

extension SyncEngineTests {

    func testFullSyncOperationFlow() async throws {
        let engine = SyncEngine(database: database)
        let logger = SyncOperationLogger(database: database)

        await engine.initialize()

        // Create a note and log it
        let note = Note(
            id: UUID().uuidString,
            title: "Test Note",
            aiTitle: nil,
            isPinned: false,
            intent: .idea,
            localVersion: 1,
            serverVersion: nil,
            syncStatus: .pending
        )

        // Insert note into database
        try await database.write { db in
            try note.insert(db)
        }

        // Log the operation
        logger.logNoteCreate(note)

        // Wait for async operation
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify operation was logged
        let pendingOps = try await database.read { db in
            try SyncOperationRecord
                .filter(Column("synced") == false)
                .fetchCount(db)
        }

        XCTAssertEqual(pendingOps, 1)

        // Verify note exists
        let savedNote = try await database.read { db in
            try Note.fetchOne(db, key: note.id)
        }

        XCTAssertNotNil(savedNote)
        XCTAssertEqual(savedNote?.title, "Test Note")
    }
}
