import XCTest
@testable import Obius

final class SectionModelTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInit_defaults() {
        let section = Section(noteId: "note-123", orderKey: "A")

        XCTAssertFalse(section.id.isEmpty)
        XCTAssertEqual(section.noteId, "note-123")
        XCTAssertEqual(section.content, "")
        XCTAssertEqual(section.contentType, .text)
        XCTAssertNil(section.title)
        XCTAssertNil(section.parentSectionId)
        XCTAssertEqual(section.orderKey, "A")
        XCTAssertEqual(section.indentLevel, 0)
        XCTAssertFalse(section.isCollapsed)
        XCTAssertFalse(section.isLocked)
        XCTAssertEqual(section.intent, .idea)
        XCTAssertEqual(section.syncStatus, .pending)
    }

    func testInit_customValues() {
        let section = Section(
            id: "section-456",
            noteId: "note-789",
            content: "Test content",
            contentType: .code,
            title: "Custom Title",
            parentSectionId: "parent-123",
            orderKey: "B",
            indentLevel: 2,
            isCollapsed: true,
            isLocked: true,
            intent: .task
        )

        XCTAssertEqual(section.id, "section-456")
        XCTAssertEqual(section.noteId, "note-789")
        XCTAssertEqual(section.content, "Test content")
        XCTAssertEqual(section.contentType, .code)
        XCTAssertEqual(section.title, "Custom Title")
        XCTAssertEqual(section.parentSectionId, "parent-123")
        XCTAssertEqual(section.orderKey, "B")
        XCTAssertEqual(section.indentLevel, 2)
        XCTAssertTrue(section.isCollapsed)
        XCTAssertTrue(section.isLocked)
        XCTAssertEqual(section.intent, .task)
    }

    // MARK: - isEmpty Tests

    func testIsEmpty_empty() {
        let section = Section(noteId: "note", orderKey: "A", content: "")
        XCTAssertTrue(section.isEmpty)
    }

    func testIsEmpty_whitespace() {
        let section = Section(noteId: "note", orderKey: "A", content: "   \n\t  ")
        XCTAssertTrue(section.isEmpty)
    }

    func testIsEmpty_hasContent() {
        let section = Section(noteId: "note", orderKey: "A", content: "Hello")
        XCTAssertFalse(section.isEmpty)
    }

    // MARK: - Preview Tests

    func testPreview_short() {
        let section = Section(noteId: "note", orderKey: "A", content: "Short content")
        XCTAssertEqual(section.preview, "Short content")
    }

    func testPreview_truncated() {
        let longContent = String(repeating: "a", count: 150)
        let section = Section(noteId: "note", orderKey: "A", content: longContent)

        XCTAssertTrue(section.preview.count <= 82) // 80 + "…"
        XCTAssertTrue(section.preview.hasSuffix("…"))
    }

    func testPreview_trims() {
        let section = Section(noteId: "note", orderKey: "A", content: "  Trimmed  \n")
        XCTAssertEqual(section.preview, "Trimmed")
    }
    
    func testPreview_firstLineOnly() {
        let section = Section(noteId: "note", orderKey: "A", content: "First line\nSecond line\nThird line")
        XCTAssertEqual(section.preview, "First line")
    }
    
    // MARK: - Display Title Tests
    
    func testDisplayTitle_withTitle() {
        let section = Section(noteId: "note", orderKey: "A", title: "My Title")
        XCTAssertEqual(section.displayTitle, "My Title")
    }
    
    func testDisplayTitle_fromContent() {
        let section = Section(noteId: "note", orderKey: "A", content: "First line of content")
        XCTAssertEqual(section.displayTitle, "First line of content")
    }
    
    func testDisplayTitle_untitled() {
        let section = Section(noteId: "note", orderKey: "A", content: "")
        XCTAssertEqual(section.displayTitle, "Untitled Section")
    }

    // MARK: - isDeleted Tests

    func testIsDeleted_notDeleted() {
        let section = Section(noteId: "note", orderKey: "A")
        XCTAssertFalse(section.isDeleted)
    }

    func testIsDeleted_deleted() {
        let section = Section(
            noteId: "note",
            orderKey: "A",
            deletedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        XCTAssertTrue(section.isDeleted)
    }

    // MARK: - Touch Tests

    func testTouch() {
        var section = Section(noteId: "note", orderKey: "A", localVersion: 1)
        let originalUpdatedAt = section.updatedAt

        Thread.sleep(forTimeInterval: 0.01)
        section.touch()

        XCTAssertEqual(section.localVersion, 2)
        XCTAssertEqual(section.syncStatus, .pending)
        XCTAssertGreaterThan(section.updatedAt, originalUpdatedAt)
    }

    // MARK: - Soft Delete Tests

    func testSoftDelete() {
        var section = Section(noteId: "note", orderKey: "A")
        XCTAssertNil(section.deletedAt)

        section.softDelete()

        XCTAssertNotNil(section.deletedAt)
        XCTAssertTrue(section.isDeleted)
        XCTAssertEqual(section.syncStatus, .pending)
    }
    
    // MARK: - Intent Tests
    
    func testSetIntent() {
        var section = Section(noteId: "note", orderKey: "A", intent: .idea)
        XCTAssertEqual(section.intent, .idea)
        
        section.setIntent(.evidence)
        XCTAssertEqual(section.intent, .evidence)
        XCTAssertEqual(section.syncStatus, .pending)
    }
    
    // MARK: - Lock Tests
    
    func testToggleLocked() {
        var section = Section(noteId: "note", orderKey: "A", isLocked: false)
        XCTAssertFalse(section.isLocked)
        
        section.toggleLocked()
        XCTAssertTrue(section.isLocked)
        XCTAssertEqual(section.syncStatus, .pending)
        
        section.toggleLocked()
        XCTAssertFalse(section.isLocked)
    }

    // MARK: - ContentType Tests

    func testContentType_allCases() {
        XCTAssertEqual(ContentType.text.rawValue, "text")
        XCTAssertEqual(ContentType.checklist.rawValue, "checklist")
        XCTAssertEqual(ContentType.code.rawValue, "code")
        XCTAssertEqual(ContentType.quote.rawValue, "quote")
    }

    // MARK: - Hashable Tests

    func testHashable() {
        let section1 = Section(id: "same-id", noteId: "note", orderKey: "A")
        let section2 = Section(id: "same-id", noteId: "note", orderKey: "A")
        let section3 = Section(id: "different-id", noteId: "note", orderKey: "A")

        XCTAssertEqual(section1, section2)
        XCTAssertNotEqual(section1, section3)
    }
}
