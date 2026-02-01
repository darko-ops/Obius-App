import XCTest
@testable import Obius

final class SyncTypesTests: XCTestCase {

    // MARK: - RemoteNote Tests

    func testRemoteNote_toLocal() {
        let remoteNote = RemoteNote(
            id: "note-123",
            userId: "user-456",
            title: "Test Note",
            aiTitle: "AI Title",
            aiSummary: "AI Summary",
            isPinned: true,
            colorIntent: "important",
            createdAt: "2024-01-01T12:00:00.000Z",
            updatedAt: "2024-01-02T12:00:00.000Z",
            deletedAt: nil,
            version: 5
        )

        let localNote = remoteNote.toLocal()

        XCTAssertEqual(localNote.id, "note-123")
        XCTAssertEqual(localNote.title, "Test Note")
        XCTAssertEqual(localNote.aiTitle, "AI Title")
        XCTAssertTrue(localNote.isPinned)
        XCTAssertEqual(localNote.intent, .task)  // "important" maps to .task
        XCTAssertEqual(localNote.localVersion, 5)
        XCTAssertEqual(localNote.serverVersion, 5)
        XCTAssertEqual(localNote.syncStatus, .synced)
        XCTAssertNil(localNote.deletedAt)
    }

    func testRemoteNote_toLocal_withDeletion() {
        let remoteNote = RemoteNote(
            id: "note-123",
            userId: "user-456",
            title: nil,
            aiTitle: nil,
            aiSummary: nil,
            isPinned: false,
            colorIntent: "default",
            createdAt: "2024-01-01T12:00:00.000Z",
            updatedAt: "2024-01-02T12:00:00.000Z",
            deletedAt: "2024-01-03T12:00:00.000Z",
            version: 3
        )

        let localNote = remoteNote.toLocal()

        XCTAssertNotNil(localNote.deletedAt)
        XCTAssertTrue(localNote.isDeleted)
    }

    func testRemoteNote_intentFallback() {
        let remoteNote = RemoteNote(
            id: "note-123",
            userId: "user-456",
            title: nil,
            aiTitle: nil,
            aiSummary: nil,
            isPinned: false,
            colorIntent: "unknown_color",
            createdAt: "2024-01-01T12:00:00.000Z",
            updatedAt: "2024-01-02T12:00:00.000Z",
            deletedAt: nil,
            version: 1
        )

        let localNote = remoteNote.toLocal()

        // Should fall back to .idea
        XCTAssertEqual(localNote.intent, .idea)
    }
    
    func testRemoteNote_intentMapping() {
        // Test all legacy color intent mappings
        let testCases: [(String, IntentType)] = [
            ("idea", .idea),
            ("default", .idea),
            ("important", .task),
            ("task", .task),
            ("reference", .evidence),
            ("question", .question),
            ("evidence", .evidence),
        ]
        
        for (colorIntent, expectedIntent) in testCases {
            let remoteNote = RemoteNote(
                id: "note-\(colorIntent)",
                userId: "user",
                title: nil,
                aiTitle: nil,
                aiSummary: nil,
                isPinned: false,
                colorIntent: colorIntent,
                createdAt: "2024-01-01T12:00:00.000Z",
                updatedAt: "2024-01-01T12:00:00.000Z",
                deletedAt: nil,
                version: 1
            )
            
            let localNote = remoteNote.toLocal()
            XCTAssertEqual(localNote.intent, expectedIntent, "Expected \(colorIntent) to map to \(expectedIntent)")
        }
    }

    // MARK: - RemoteSection Tests

    func testRemoteSection_toLocal() {
        let remoteSection = RemoteSection(
            id: "section-123",
            noteId: "note-456",
            userId: "user-789",
            content: "Test content",
            contentType: "text",
            parentSectionId: nil,
            orderKey: "A",
            indentLevel: 1,
            isCollapsed: false,
            colorIntent: "idea",
            createdAt: "2024-01-01T12:00:00.000Z",
            updatedAt: "2024-01-02T12:00:00.000Z",
            deletedAt: nil,
            version: 3
        )

        let localSection = remoteSection.toLocal()

        XCTAssertEqual(localSection.id, "section-123")
        XCTAssertEqual(localSection.noteId, "note-456")
        XCTAssertEqual(localSection.content, "Test content")
        XCTAssertEqual(localSection.contentType, .text)
        XCTAssertNil(localSection.title)  // Title is local-only
        XCTAssertEqual(localSection.orderKey, "A")
        XCTAssertEqual(localSection.indentLevel, 1)
        XCTAssertFalse(localSection.isCollapsed)
        XCTAssertFalse(localSection.isLocked)  // isLocked is local-only
        XCTAssertEqual(localSection.intent, .idea)
        XCTAssertEqual(localSection.localVersion, 3)
        XCTAssertEqual(localSection.serverVersion, 3)
        XCTAssertEqual(localSection.syncStatus, .synced)
    }

    func testRemoteSection_toLocal_codeType() {
        let remoteSection = RemoteSection(
            id: "section-123",
            noteId: "note-456",
            userId: "user-789",
            content: "func test() {}",
            contentType: "code",
            parentSectionId: "parent-123",
            orderKey: "B",
            indentLevel: 2,
            isCollapsed: true,
            colorIntent: nil,
            createdAt: "2024-01-01T12:00:00.000Z",
            updatedAt: "2024-01-02T12:00:00.000Z",
            deletedAt: nil,
            version: 1
        )

        let localSection = remoteSection.toLocal()

        XCTAssertEqual(localSection.contentType, .code)
        XCTAssertEqual(localSection.parentSectionId, "parent-123")
        XCTAssertTrue(localSection.isCollapsed)
        XCTAssertEqual(localSection.intent, .idea)  // nil maps to .idea
    }

    // MARK: - AnyCodable Tests

    func testAnyCodable_encodeString() throws {
        let codable = AnyCodable("test string")
        let encoder = JSONEncoder()
        let data = try encoder.encode(codable)
        let string = String(data: data, encoding: .utf8)

        XCTAssertEqual(string, "\"test string\"")
    }

    func testAnyCodable_encodeInt() throws {
        let codable = AnyCodable(42)
        let encoder = JSONEncoder()
        let data = try encoder.encode(codable)
        let string = String(data: data, encoding: .utf8)

        XCTAssertEqual(string, "42")
    }

    func testAnyCodable_encodeBool() throws {
        let codable = AnyCodable(true)
        let encoder = JSONEncoder()
        let data = try encoder.encode(codable)
        let string = String(data: data, encoding: .utf8)

        XCTAssertEqual(string, "true")
    }

    func testAnyCodable_encodeArray() throws {
        let codable = AnyCodable([1, 2, 3])
        let encoder = JSONEncoder()
        let data = try encoder.encode(codable)
        let string = String(data: data, encoding: .utf8)

        XCTAssertEqual(string, "[1,2,3]")
    }

    func testAnyCodable_encodeDict() throws {
        let codable = AnyCodable(["key": "value"])
        let encoder = JSONEncoder()
        let data = try encoder.encode(codable)
        let string = String(data: data, encoding: .utf8)

        XCTAssertEqual(string, "{\"key\":\"value\"}")
    }

    func testAnyCodable_decodeString() throws {
        let json = "\"test string\""
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let codable = try decoder.decode(AnyCodable.self, from: data)

        XCTAssertEqual(codable.value as? String, "test string")
    }

    func testAnyCodable_decodeInt() throws {
        let json = "42"
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let codable = try decoder.decode(AnyCodable.self, from: data)

        XCTAssertEqual(codable.value as? Int, 42)
    }

    // MARK: - SyncPullResponse Tests

    func testSyncPullResponse_decode() throws {
        let json = """
        {
            "notes": [],
            "sections": [],
            "deleted_note_ids": ["note-1", "note-2"],
            "deleted_section_ids": ["section-1"],
            "server_timestamp": "2024-01-01T12:00:00.000Z",
            "has_more": false
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(SyncPullResponse.self, from: data)

        XCTAssertTrue(response.notes.isEmpty)
        XCTAssertTrue(response.sections.isEmpty)
        XCTAssertEqual(response.deletedNoteIds, ["note-1", "note-2"])
        XCTAssertEqual(response.deletedSectionIds, ["section-1"])
        XCTAssertEqual(response.serverTimestamp, "2024-01-01T12:00:00.000Z")
        XCTAssertFalse(response.hasMore)
    }

    // MARK: - ConflictInfo Tests

    func testConflictInfo_decode() throws {
        let json = """
        {
            "operation_id": "op-123",
            "entity_type": "note",
            "entity_id": "note-456",
            "server_version": 5,
            "client_version": 3,
            "resolution": "server_wins",
            "merged_entity": null
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let conflict = try decoder.decode(ConflictInfo.self, from: data)

        XCTAssertEqual(conflict.operationId, "op-123")
        XCTAssertEqual(conflict.entityType, "note")
        XCTAssertEqual(conflict.entityId, "note-456")
        XCTAssertEqual(conflict.serverVersion, 5)
        XCTAssertEqual(conflict.clientVersion, 3)
        XCTAssertEqual(conflict.resolution, "server_wins")
        XCTAssertNil(conflict.mergedEntity)
    }
    
    // MARK: - IntentType Legacy Conversion Tests
    
    func testIntentType_legacyValue() {
        XCTAssertEqual(IntentType.idea.legacyValue, "idea")
        XCTAssertEqual(IntentType.question.legacyValue, "idea")  // No server equivalent yet
        XCTAssertEqual(IntentType.task.legacyValue, "task")
        XCTAssertEqual(IntentType.evidence.legacyValue, "reference")
    }
}
