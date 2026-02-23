import Foundation
import GRDB
import Combine

@MainActor
final class NoteRepository: ObservableObject {
    private let database: DatabaseManager
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var notes: [Note] = []

    init(database: DatabaseManager) {
        self.database = database
        observeNotes()
    }

    private func observeNotes() {
        database.observeNotes()
            .receive(on: DispatchQueue.main)
            .catch { error -> Just<[Note]> in
                print("Error observing notes: \(error)")
                return Just([])
            }
            .sink { [weak self] notes in
                self?.notes = notes
            }
            .store(in: &cancellables)
    }

    // MARK: - Create

    func createNote(title: String? = nil, intent: IntentType = .idea, moduleId: String? = nil) async throws -> Note {
        let note = Note(
            title: title,
            intent: intent,
            moduleId: moduleId
        )

        try await database.write { db in
            try note.insert(db)
        }

        // No longer create initial section - user can type directly on the note
        // and add sections manually via "Add section" button

        return note
    }

    func updateNoteBody(_ noteId: String, body: String, richText: String? = nil) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.body = body
            note.bodyRichText = richText
            note.touch()
            try note.update(db)
        }
    }

    func updateInterstitialContent(_ noteId: String, afterSectionId: String?, content: String, richText: String? = nil) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            let key = afterSectionId.map { "after_\($0)" } ?? "end"
            if content.isEmpty {
                note.interstitialContent.removeValue(forKey: key)
                note.interstitialRichContent.removeValue(forKey: key)
            } else {
                note.interstitialContent[key] = content
                if let richText = richText {
                    note.interstitialRichContent[key] = richText
                } else {
                    note.interstitialRichContent.removeValue(forKey: key)
                }
            }
            note.touch()
            try note.update(db)
        }
    }

    // MARK: - Read

    func getNote(id: String) async throws -> Note? {
        try await database.read { db in
            try Note.fetchOne(db, key: id)
        }
    }

    func getNoteWithSections(id: String) async throws -> NoteWithSections? {
        try await database.read { db in
            guard let note = try Note.fetchOne(db, key: id) else {
                return nil
            }
            let sections = try note.sections.fetchAll(db)
            return NoteWithSections(note: note, sections: sections)
        }
    }

    func observeNoteWithSections(id: String) -> AnyPublisher<NoteWithSections?, Error> {
        database.observeNoteWithSections(noteId: id)
    }

    // MARK: - Update

    func updateNote(_ note: Note) async throws {
        var updated = note
        updated.touch()

        try await database.write { db in
            try updated.update(db)
        }
    }

    /// Insert or update a note (used when importing shared content).
    func saveNote(_ note: Note) async throws {
        try await database.write { db in
            try note.save(db)
        }
    }

    func updateNoteTitle(_ noteId: String, title: String?) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.title = title
            note.touch()
            try note.update(db)
        }
    }

    func updateNoteAITitle(_ noteId: String, aiTitle: String?) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.aiTitle = aiTitle
            note.touch()
            try note.update(db)
        }
    }

    func updateNoteAITags(_ noteId: String, aiTags: [String]) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.aiTags = aiTags
            note.touch()
            try note.update(db)
        }
    }

    func togglePinned(_ noteId: String) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.isPinned.toggle()
            note.touch()
            try note.update(db)
        }
    }

    func setIntent(_ noteId: String, intent: IntentType) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.intent = intent
            note.touch()
            try note.update(db)
        }
    }

    func updateTags(_ noteId: String, tags: [String]) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.tags = tags
            note.touch()
            try note.update(db)
        }
    }

    func setGroupName(noteId: String, groupName: String?) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.groupName = groupName
            note.isPinned = groupName != nil  // Grouped notes are always pinned
            note.touch()
            try note.update(db)
        }
    }

    func setModuleId(noteId: String, moduleId: String?) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.moduleId = moduleId
            note.touch()
            try note.update(db)
        }
    }

    // MARK: - Delete

    func deleteNote(_ noteId: String) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.softDelete()
            try note.update(db)

            // Also soft-delete all sections
            try db.execute(sql: """
                UPDATE sections
                SET deletedAt = ?, syncStatus = 'pending', localVersion = localVersion + 1
                WHERE noteId = ?
            """, arguments: [Int64(Date().timeIntervalSince1970 * 1000), noteId])

            let now = Int64(Date().timeIntervalSince1970 * 1000)

            // Dismiss any insights whose primary source is this note
            try db.execute(sql: """
                UPDATE insights
                SET status = 'dismissed', updatedAt = ?
                WHERE sourceNoteId = ? AND status != 'dismissed'
            """, arguments: [now, noteId])

            // Clean this note ID from relatedNoteId references
            let affected = try Insight
                .filter(Insight.Columns.relatedNoteId != nil)
                .fetchAll(db)

            for var insight in affected {
                guard let related = insight.relatedNoteId else { continue }
                let ids = related.split(separator: ",").map(String.init)
                let cleaned = ids.filter { $0 != noteId }
                let newValue = cleaned.isEmpty ? nil : cleaned.joined(separator: ",")
                if newValue != related {
                    insight.relatedNoteId = newValue
                    insight.updatedAt = now
                    try insight.update(db)
                }
            }
        }
    }

    func permanentlyDelete(_ noteId: String) async throws {
        try await database.write { db in
            try Note.deleteOne(db, key: noteId)

            let now = Int64(Date().timeIntervalSince1970 * 1000)

            // Dismiss insights whose primary source is this note
            try db.execute(sql: """
                UPDATE insights
                SET status = 'dismissed', updatedAt = ?
                WHERE sourceNoteId = ? AND status != 'dismissed'
            """, arguments: [now, noteId])

            // Clean this note ID from relatedNoteId references
            let affected = try Insight
                .filter(Insight.Columns.relatedNoteId != nil)
                .fetchAll(db)

            for var insight in affected {
                guard let related = insight.relatedNoteId else { continue }
                let ids = related.split(separator: ",").map(String.init)
                let cleaned = ids.filter { $0 != noteId }
                let newValue = cleaned.isEmpty ? nil : cleaned.joined(separator: ",")
                if newValue != related {
                    insight.relatedNoteId = newValue
                    insight.updatedAt = now
                    try insight.update(db)
                }
            }
        }
    }

    // MARK: - Search

    func searchNotes(query: String) async throws -> [Note] {
        let sections = try await database.searchSections(query: query)
        let noteIds = Set(sections.map { $0.noteId })

        return try await database.read { db in
            try Note
                .filter(noteIds.contains(Note.Columns.id))
                .filter(Note.Columns.deletedAt == nil)
                .order(Note.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Commit Restore

    /// Restores a note from a commit snapshot.
    /// Used by CommitModule to restore note state from Cold Store.
    func restoreFromSnapshot(
        id: String,
        title: String?,
        body: String,
        intent: IntentType,
        isPinned: Bool
    ) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: id) else {
                // Note doesn't exist - create it from snapshot
                let newNote = Note(
                    id: id,
                    title: title,
                    body: body,
                    isPinned: isPinned,
                    intent: intent
                )
                try newNote.insert(db)
                return
            }

            // Update existing note
            note.title = title
            note.body = body
            note.intent = intent
            note.isPinned = isPinned
            note.touch()
            try note.update(db)
        }
    }
}
