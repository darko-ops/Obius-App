import XCTest
@testable import Obius

final class SectionRepositoryTests: XCTestCase {
    var database: DatabaseManager!
    var noteRepository: NoteRepository!
    var sectionRepository: SectionRepository!
    var testNote: Note!

    override func setUp() async throws {
        try await super.setUp()
        database = try DatabaseManager(inMemory: true)
        noteRepository = await NoteRepository(database: database)
        sectionRepository = await SectionRepository(database: database)

        // Create a test note for sections
        testNote = try await noteRepository.createNote(title: "Test Note")
    }

    override func tearDown() async throws {
        testNote = nil
        sectionRepository = nil
        noteRepository = nil
        database = nil
        try await super.tearDown()
    }

    // MARK: - Create Tests

    func testCreateSection_withDefaults() async throws {
        let section = try await sectionRepository.createSection(noteId: testNote.id)

        XCTAssertNotNil(section.id)
        XCTAssertEqual(section.noteId, testNote.id)
        XCTAssertEqual(section.content, "")
        XCTAssertEqual(section.contentType, .text)
        XCTAssertEqual(section.indentLevel, 0)
        XCTAssertFalse(section.isCollapsed)
        XCTAssertFalse(section.isLocked)
        XCTAssertEqual(section.intent, .idea)
        XCTAssertEqual(section.syncStatus, .pending)
    }

    func testCreateSection_withContent() async throws {
        let section = try await sectionRepository.createSection(
            noteId: testNote.id,
            content: "Test content"
        )

        XCTAssertEqual(section.content, "Test content")
    }

    func testCreateSection_afterExisting() async throws {
        let first = try await sectionRepository.createSection(noteId: testNote.id, content: "First")
        let second = try await sectionRepository.createSection(
            noteId: testNote.id,
            content: "Second",
            afterSectionId: first.id
        )

        let sections = try await sectionRepository.getSections(noteId: testNote.id)

        // Find indices
        let firstIndex = sections.firstIndex(where: { $0.id == first.id })
        let secondIndex = sections.firstIndex(where: { $0.id == second.id })

        XCTAssertNotNil(firstIndex)
        XCTAssertNotNil(secondIndex)

        // Second should come after first based on orderKey
        XCTAssertTrue(second.orderKey > first.orderKey)
    }

    // MARK: - Update Tests

    func testUpdateContent() async throws {
        let section = try await sectionRepository.createSection(noteId: testNote.id, content: "Original")
        try await sectionRepository.updateContent(section.id, content: "Updated content")

        let updated = try await sectionRepository.getSection(id: section.id)
        XCTAssertEqual(updated?.content, "Updated content")
    }

    func testToggleCollapse() async throws {
        let section = try await sectionRepository.createSection(noteId: testNote.id)
        XCTAssertFalse(section.isCollapsed)

        try await sectionRepository.toggleCollapse(section.id)
        var updated = try await sectionRepository.getSection(id: section.id)
        XCTAssertTrue(updated?.isCollapsed ?? false)

        try await sectionRepository.toggleCollapse(section.id)
        updated = try await sectionRepository.getSection(id: section.id)
        XCTAssertFalse(updated?.isCollapsed ?? true)
    }
    
    func testToggleLock() async throws {
        let section = try await sectionRepository.createSection(noteId: testNote.id)
        XCTAssertFalse(section.isLocked)

        try await sectionRepository.toggleLock(section.id)
        var updated = try await sectionRepository.getSection(id: section.id)
        XCTAssertTrue(updated?.isLocked ?? false)

        try await sectionRepository.toggleLock(section.id)
        updated = try await sectionRepository.getSection(id: section.id)
        XCTAssertFalse(updated?.isLocked ?? true)
    }

    func testIndent() async throws {
        let section = try await sectionRepository.createSection(noteId: testNote.id)
        XCTAssertEqual(section.indentLevel, 0)

        try await sectionRepository.indent(section.id)
        var updated = try await sectionRepository.getSection(id: section.id)
        XCTAssertEqual(updated?.indentLevel, 1)

        try await sectionRepository.indent(section.id)
        updated = try await sectionRepository.getSection(id: section.id)
        XCTAssertEqual(updated?.indentLevel, 2)
    }

    func testIndent_maxLevel() async throws {
        let section = try await sectionRepository.createSection(noteId: testNote.id)

        // Indent to max level (5)
        for _ in 0..<10 {
            try await sectionRepository.indent(section.id)
        }

        let updated = try await sectionRepository.getSection(id: section.id)
        XCTAssertEqual(updated?.indentLevel, 5)
    }

    func testOutdent() async throws {
        let section = try await sectionRepository.createSection(noteId: testNote.id)
        try await sectionRepository.setIndentLevel(section.id, level: 3)

        try await sectionRepository.outdent(section.id)
        let updated = try await sectionRepository.getSection(id: section.id)
        XCTAssertEqual(updated?.indentLevel, 2)
    }

    func testOutdent_atZero() async throws {
        let section = try await sectionRepository.createSection(noteId: testNote.id)
        XCTAssertEqual(section.indentLevel, 0)

        try await sectionRepository.outdent(section.id)
        let updated = try await sectionRepository.getSection(id: section.id)
        XCTAssertEqual(updated?.indentLevel, 0) // Should not go negative
    }

    func testSetIntent() async throws {
        let section = try await sectionRepository.createSection(noteId: testNote.id)
        XCTAssertEqual(section.intent, .idea)

        try await sectionRepository.setIntent(section.id, intent: .task)
        var updated = try await sectionRepository.getSection(id: section.id)
        XCTAssertEqual(updated?.intent, .task)

        try await sectionRepository.setIntent(section.id, intent: .evidence)
        updated = try await sectionRepository.getSection(id: section.id)
        XCTAssertEqual(updated?.intent, .evidence)
    }

    // MARK: - Reorder Tests

    func testMoveSection() async throws {
        // Create three sections
        let a = try await sectionRepository.createSection(noteId: testNote.id, content: "A")
        let b = try await sectionRepository.createSection(noteId: testNote.id, content: "B", afterSectionId: a.id)
        let c = try await sectionRepository.createSection(noteId: testNote.id, content: "C", afterSectionId: b.id)

        // Move C after A (between A and B)
        try await sectionRepository.moveSection(c.id, after: a.id)

        let sections = try await sectionRepository.getSections(noteId: testNote.id)
        let contents = sections.map { $0.content }

        // Expected order: A, C, B (plus the initial empty section from note creation)
        XCTAssertTrue(contents.contains("A"))
        XCTAssertTrue(contents.contains("C"))
        XCTAssertTrue(contents.contains("B"))
    }

    // MARK: - Delete Tests

    func testDeleteSection() async throws {
        let section = try await sectionRepository.createSection(noteId: testNote.id, content: "Delete me")
        try await sectionRepository.deleteSection(section.id)

        let deleted = try await sectionRepository.getSection(id: section.id)
        XCTAssertNotNil(deleted?.deletedAt)
    }

    func testDeleteSection_excludedFromList() async throws {
        let keep = try await sectionRepository.createSection(noteId: testNote.id, content: "Keep")
        let remove = try await sectionRepository.createSection(noteId: testNote.id, content: "Remove")

        try await sectionRepository.deleteSection(remove.id)

        let sections = try await sectionRepository.getSections(noteId: testNote.id)
        let contents = sections.map { $0.content }

        XCTAssertTrue(contents.contains("Keep"))
        XCTAssertFalse(contents.contains("Remove"))
    }

    // MARK: - Search Tests

    func testSearchSections() async throws {
        _ = try await sectionRepository.createSection(noteId: testNote.id, content: "Hello world")
        _ = try await sectionRepository.createSection(noteId: testNote.id, content: "Goodbye world")
        _ = try await sectionRepository.createSection(noteId: testNote.id, content: "Hello there")

        let results = try await sectionRepository.searchSections(query: "Hello")

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.content.contains("Hello") })
    }

    func testSearchSections_noResults() async throws {
        _ = try await sectionRepository.createSection(noteId: testNote.id, content: "Some content")

        let results = try await sectionRepository.searchSections(query: "nonexistent")

        XCTAssertTrue(results.isEmpty)
    }
}
