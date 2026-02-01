import XCTest
@testable import Obius

final class NoteModelTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInit_defaults() {
        let note = Note()

        XCTAssertFalse(note.id.isEmpty)
        XCTAssertNil(note.title)
        XCTAssertNil(note.aiTitle)
        XCTAssertFalse(note.isPinned)
        XCTAssertEqual(note.intent, .idea)
        XCTAssertEqual(note.localVersion, 1)
        XCTAssertNil(note.serverVersion)
        XCTAssertEqual(note.syncStatus, .pending)
        XCTAssertNil(note.deletedAt)
    }

    func testInit_customValues() {
        let note = Note(
            id: "custom-id",
            title: "Custom Title",
            isPinned: true,
            intent: .task,
            localVersion: 5,
            serverVersion: 4,
            syncStatus: .synced
        )

        XCTAssertEqual(note.id, "custom-id")
        XCTAssertEqual(note.title, "Custom Title")
        XCTAssertTrue(note.isPinned)
        XCTAssertEqual(note.intent, .task)
        XCTAssertEqual(note.localVersion, 5)
        XCTAssertEqual(note.serverVersion, 4)
        XCTAssertEqual(note.syncStatus, .synced)
    }

    // MARK: - Display Title Tests

    func testDisplayTitle_withTitle() {
        let note = Note(title: "My Title")
        XCTAssertEqual(note.displayTitle, "My Title")
    }

    func testDisplayTitle_withAiTitle() {
        let note = Note(aiTitle: "AI Generated")
        XCTAssertEqual(note.displayTitle, "AI Generated")
    }

    func testDisplayTitle_titleOverAiTitle() {
        let note = Note(title: "User Title", aiTitle: "AI Title")
        XCTAssertEqual(note.displayTitle, "User Title")
    }

    func testDisplayTitle_untitled() {
        let note = Note()
        XCTAssertEqual(note.displayTitle, "Untitled")
    }

    // MARK: - isDeleted Tests

    func testIsDeleted_notDeleted() {
        let note = Note()
        XCTAssertFalse(note.isDeleted)
    }

    func testIsDeleted_deleted() {
        let note = Note(deletedAt: Int64(Date().timeIntervalSince1970 * 1000))
        XCTAssertTrue(note.isDeleted)
    }

    // MARK: - Touch Tests

    func testTouch_incrementsVersion() {
        var note = Note(localVersion: 1)
        note.touch()

        XCTAssertEqual(note.localVersion, 2)
        XCTAssertEqual(note.syncStatus, .pending)
    }

    func testTouch_updatesTimestamp() {
        var note = Note()
        let originalUpdatedAt = note.updatedAt

        // Wait a bit
        Thread.sleep(forTimeInterval: 0.01)

        note.touch()

        XCTAssertGreaterThan(note.updatedAt, originalUpdatedAt)
    }

    // MARK: - Soft Delete Tests

    func testSoftDelete() {
        var note = Note()
        XCTAssertNil(note.deletedAt)
        XCTAssertFalse(note.isDeleted)

        note.softDelete()

        XCTAssertNotNil(note.deletedAt)
        XCTAssertTrue(note.isDeleted)
        XCTAssertEqual(note.syncStatus, .pending)
    }
    
    // MARK: - Intent Tests
    
    func testSetIntent() {
        var note = Note(intent: .idea)
        XCTAssertEqual(note.intent, .idea)
        
        note.setIntent(.task)
        XCTAssertEqual(note.intent, .task)
        XCTAssertEqual(note.syncStatus, .pending)
    }
    
    func testAllIntentTypes() {
        XCTAssertEqual(IntentType.idea.rawValue, "idea")
        XCTAssertEqual(IntentType.question.rawValue, "question")
        XCTAssertEqual(IntentType.task.rawValue, "task")
        XCTAssertEqual(IntentType.evidence.rawValue, "evidence")
    }

    // MARK: - Date Conversion Tests

    func testCreatedDate() {
        let timestamp: Int64 = 1704067200000 // 2024-01-01 00:00:00 UTC
        let note = Note(createdAt: timestamp)

        let expectedDate = Date(timeIntervalSince1970: 1704067200)
        XCTAssertEqual(note.createdDate.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 1)
    }

    func testUpdatedDate() {
        let timestamp: Int64 = 1704153600000 // 2024-01-02 00:00:00 UTC
        let note = Note(updatedAt: timestamp)

        let expectedDate = Date(timeIntervalSince1970: 1704153600)
        XCTAssertEqual(note.updatedDate.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - Hashable Tests

    func testHashable() {
        let note1 = Note(id: "same-id")
        let note2 = Note(id: "same-id")
        let note3 = Note(id: "different-id")

        XCTAssertEqual(note1, note2)
        XCTAssertNotEqual(note1, note3)

        var set = Set<Note>()
        set.insert(note1)
        set.insert(note2)

        XCTAssertEqual(set.count, 1)
    }
}
