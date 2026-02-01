import XCTest
@testable import Obius

final class NoteRepositoryTests: XCTestCase {
    var database: DatabaseManager!
    var repository: NoteRepository!

    override func setUp() async throws {
        try await super.setUp()
        // Use in-memory database for tests
        database = try DatabaseManager(inMemory: true)
        repository = await NoteRepository(database: database)
    }

    override func tearDown() async throws {
        repository = nil
        database = nil
        try await super.tearDown()
    }

    // MARK: - Create Tests

    func testCreateNote_withDefaults() async throws {
        let note = try await repository.createNote()

        XCTAssertNotNil(note.id)
        XCTAssertNil(note.title)
        XCTAssertNil(note.aiTitle)
        XCTAssertFalse(note.isPinned)
        XCTAssertEqual(note.intent, .idea)
        XCTAssertEqual(note.syncStatus, .pending)
        XCTAssertEqual(note.localVersion, 1)
    }

    func testCreateNote_withTitle() async throws {
        let note = try await repository.createNote(title: "Test Note")

        XCTAssertEqual(note.title, "Test Note")
        XCTAssertEqual(note.displayTitle, "Test Note")
    }

    func testCreateNote_withIntent() async throws {
        let note = try await repository.createNote(intent: .task)

        XCTAssertEqual(note.intent, .task)
    }

    func testCreateNote_createsInitialSection() async throws {
        let note = try await repository.createNote()
        let noteWithSections = try await repository.getNoteWithSections(id: note.id)

        XCTAssertNotNil(noteWithSections)
        XCTAssertEqual(noteWithSections?.sections.count, 1)
        XCTAssertEqual(noteWithSections?.sections.first?.content, "")
    }

    // MARK: - Read Tests

    func testGetNote_existing() async throws {
        let created = try await repository.createNote(title: "Find Me")
        let found = try await repository.getNote(id: created.id)

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, created.id)
        XCTAssertEqual(found?.title, "Find Me")
    }

    func testGetNote_nonExistent() async throws {
        let found = try await repository.getNote(id: "non-existent-id")

        XCTAssertNil(found)
    }

    func testGetNoteWithSections() async throws {
        let note = try await repository.createNote(title: "With Sections")
        let result = try await repository.getNoteWithSections(id: note.id)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.note.id, note.id)
        XCTAssertFalse(result?.sections.isEmpty ?? true)
    }

    // MARK: - Update Tests

    func testUpdateNoteTitle() async throws {
        let note = try await repository.createNote(title: "Original")
        try await repository.updateNoteTitle(note.id, title: "Updated")

        let updated = try await repository.getNote(id: note.id)
        XCTAssertEqual(updated?.title, "Updated")
        XCTAssertEqual(updated?.syncStatus, .pending)
    }

    func testUpdateNoteTitle_toNil() async throws {
        let note = try await repository.createNote(title: "Has Title")
        try await repository.updateNoteTitle(note.id, title: nil)

        let updated = try await repository.getNote(id: note.id)
        XCTAssertNil(updated?.title)
    }

    func testTogglePinned() async throws {
        let note = try await repository.createNote()
        XCTAssertFalse(note.isPinned)

        try await repository.togglePinned(note.id)
        var updated = try await repository.getNote(id: note.id)
        XCTAssertTrue(updated?.isPinned ?? false)

        try await repository.togglePinned(note.id)
        updated = try await repository.getNote(id: note.id)
        XCTAssertFalse(updated?.isPinned ?? true)
    }

    func testSetIntent() async throws {
        let note = try await repository.createNote()
        XCTAssertEqual(note.intent, .idea)

        try await repository.setIntent(note.id, intent: .question)
        let updated = try await repository.getNote(id: note.id)
        XCTAssertEqual(updated?.intent, .question)
    }

    // MARK: - Delete Tests

    func testDeleteNote_softDelete() async throws {
        let note = try await repository.createNote(title: "Delete Me")
        try await repository.deleteNote(note.id)

        let deleted = try await repository.getNote(id: note.id)
        XCTAssertNotNil(deleted?.deletedAt)
        XCTAssertTrue(deleted?.isDeleted ?? false)
    }

    func testDeleteNote_excludedFromList() async throws {
        _ = try await repository.createNote(title: "Keep Me")
        let toDelete = try await repository.createNote(title: "Delete Me")

        try await repository.deleteNote(toDelete.id)

        // Give time for observation to update
        try await Task.sleep(nanoseconds: 100_000_000)

        let notes = await repository.notes
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "Keep Me")
    }

    func testPermanentlyDelete() async throws {
        let note = try await repository.createNote(title: "Gone Forever")
        try await repository.permanentlyDelete(note.id)

        let found = try await repository.getNote(id: note.id)
        XCTAssertNil(found)
    }

    // MARK: - Observation Tests

    func testNotesObservation_orderedByUpdatedAt() async throws {
        let note1 = try await repository.createNote(title: "First")
        try await Task.sleep(nanoseconds: 10_000_000)
        let note2 = try await repository.createNote(title: "Second")
        try await Task.sleep(nanoseconds: 10_000_000)
        let note3 = try await repository.createNote(title: "Third")

        try await Task.sleep(nanoseconds: 100_000_000)

        let notes = await repository.notes
        XCTAssertEqual(notes.count, 3)
        // Most recently updated first
        XCTAssertEqual(notes[0].id, note3.id)
        XCTAssertEqual(notes[1].id, note2.id)
        XCTAssertEqual(notes[2].id, note1.id)
    }

    func testNotesObservation_pinnedFirst() async throws {
        let unpinned = try await repository.createNote(title: "Unpinned")
        let pinned = try await repository.createNote(title: "Pinned")
        try await repository.togglePinned(pinned.id)

        try await Task.sleep(nanoseconds: 100_000_000)

        let notes = await repository.notes
        XCTAssertEqual(notes.first?.id, pinned.id)
    }
}
