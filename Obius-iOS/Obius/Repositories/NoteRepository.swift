import Foundation
import GRDB
import Combine

@MainActor
final class NoteRepository: ObservableObject {
    private let database: DatabaseManager
    private var cancellables = Set<AnyCancellable>()
    var syncLogger: SyncOperationLogger?

    @Published private(set) var notes: [Note] = []
    /// Section-aware display titles keyed by note ID.
    /// Views should use `resolvedTitle(for:)` instead of `note.displayTitle`.
    @Published private(set) var autoTitles: [String: String] = [:]

    init(database: DatabaseManager) {
        self.database = database
        observeNotes()
    }

    /// Returns the section-aware display title for a note.
    func resolvedTitle(for note: Note) -> String {
        autoTitles[note.id] ?? note.displayTitle
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
                self?.refreshAutoTitles(for: notes)
            }
            .store(in: &cancellables)
    }

    /// Refresh auto-titles for notes that need section context.
    private func refreshAutoTitles(for notes: [Note]) {
        Task { [weak self] in
            guard let self else { return }
            var titles: [String: String] = [:]
            for note in notes {
                // Only fetch sections for notes without a user or AI title
                let hasUserTitle = note.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                let hasAiTitle = note.aiTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                if hasUserTitle || hasAiTitle {
                    continue
                }
                if let sections = try? await self.database.read({ db in
                    try note.sections.order(Section.Columns.orderKey).fetchAll(db)
                }) {
                    let title = note.displayTitle(sections: sections)
                    if title != "Untitled" {
                        titles[note.id] = title
                    }
                }
            }
            self.autoTitles = titles
        }
    }

    // MARK: - Create

    func createNote(title: String? = nil, intent: IntentType = .idea, moduleId: String? = nil) async throws -> Note {
        // Validate moduleId at insert time. The UI's @AppStorage selectedModuleId
        // can lag behind sync's empty-module cleanup, so we may be handed an id
        // that points to a row that was just soft-deleted — which would land the
        // new note as an orphan and make it invisible in the current module view
        // until the next cleanup pass reassigns it.
        let resolvedModuleId = try await database.read { db -> String? in
            guard let requested = moduleId else { return nil }
            let liveCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM modules WHERE id = ? AND deletedAt IS NULL",
                arguments: [requested]
            ) ?? 0
            if liveCount > 0 { return requested }
            // Soft-deleted (or missing). Try to remap to a live module of the same name.
            if let staleName = try String.fetchOne(
                db, sql: "SELECT name FROM modules WHERE id = ?", arguments: [requested]
            ),
            let liveByName = try String.fetchOne(
                db,
                sql: "SELECT id FROM modules WHERE name = ? AND deletedAt IS NULL ORDER BY createdAt LIMIT 1",
                arguments: [staleName]
            ) {
                return liveByName
            }
            // No same-name live module — fall back to any live module.
            return try String.fetchOne(
                db,
                sql: "SELECT id FROM modules WHERE deletedAt IS NULL ORDER BY createdAt LIMIT 1"
            )
        }

        let note = Note(
            title: title,
            intent: intent,
            moduleId: resolvedModuleId
        )

        try await database.write { db in
            try note.insert(db)
            try DatabaseManager.recomputeEngagementScore(noteId: note.id, in: db)
        }

        return note
    }

    /// Resolve a sync conflict by accepting current local state and marking for re-push
    func resolveConflict(_ noteId: String) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.syncStatus = .pending
            note.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try note.update(db)
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    func updateNoteBody(_ noteId: String, body: String, richText: String? = nil, clearRichText: Bool = false) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            // Only touch if body text or rich text actually changed.
            let richChanged = richText != nil && note.bodyRichText != richText
            guard note.body != body || richChanged || clearRichText else { return }
            note.body = body
            if let richText = richText {
                note.bodyRichText = richText
            } else if clearRichText {
                note.bodyRichText = nil
            }
            note.touch()
            try note.update(db)
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    func updateInterstitialContent(_ noteId: String, afterSectionId: String?, content: String, richText: String? = nil) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            let key = afterSectionId.map { "after_\($0)" } ?? "end"
            let oldContent = note.interstitialContent[key] ?? ""
            let oldRich = note.interstitialRichContent[key]
            // Only touch if content actually changed
            guard oldContent != content || oldRich != richText else { return }
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
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    // MARK: - Atomic Section Delete + Interstitial Merge

    /// Soft-deletes a section while atomically merging its interstitial slot
    /// into the previous section's slot (or note body when it's the first
    /// section). The whole operation runs in one `database.write` so a
    /// concurrent interstitial-typing debounce can't race the merge: GRDB
    /// serializes writes, so any competing write either commits before our
    /// transaction reads the note or queues behind our merge.
    ///
    /// Behaviour matches the previous multi-step path in NoteEditorViewModel:
    /// reparents direct children to the deleted section's parent (recomputing
    /// indent levels), preserves interstitial content (plain + rich), clears
    /// the orphan slot, and recomputes the engagement score.
    func deleteSectionAndMergeInterstitials(noteId: String, sectionId: String) async throws {
        let didDelete = try await database.write { db -> Bool in
            guard var note = try Note.fetchOne(db, key: noteId) else { return false }
            let liveSections = try Section
                .filter(Section.Columns.noteId == noteId)
                .filter(Section.Columns.deletedAt == nil)
                .order(Section.Columns.orderKey)
                .fetchAll(db)

            guard let index = liveSections.firstIndex(where: { $0.id == sectionId }) else {
                // Already deleted concurrently — nothing left to merge.
                return false
            }
            let section = liveSections[index]

            // Reparent direct children to the deleted section's parent.
            // Indent levels (and grandchildren's) shift relative to the new parent.
            let directChildren = liveSections.filter { $0.parentSectionId == sectionId }
            for var child in directChildren {
                let newParentId = section.parentSectionId
                let newIndent: Int
                if let parentId = newParentId,
                   let parent = try Section.fetchOne(db, key: parentId) {
                    newIndent = parent.indentLevel + 1
                } else {
                    newIndent = 0
                }
                let indentDelta = newIndent - child.indentLevel
                child.parentSectionId = newParentId
                child.indentLevel = newIndent
                child.touch()
                try child.update(db)
                if indentDelta != 0 {
                    try SectionRepository.updateDescendantIndentLevels(
                        db: db,
                        parentId: child.id,
                        indentDelta: indentDelta
                    )
                }
            }

            // Merge the orphaned interstitial into the previous section's slot
            // (or note body when the deleted section is the first one).
            let deletedKey = "after_\(sectionId)"
            let orphanedText = note.interstitialContent[deletedKey] ?? ""
            let orphanedRich = note.interstitialRichContent[deletedKey]
            var noteChanged = false

            if !orphanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if index > 0 {
                    let prevId = liveSections[index - 1].id
                    let prevKey = "after_\(prevId)"
                    let existingText = note.interstitialContent[prevKey] ?? ""
                    let existingRich = note.interstitialRichContent[prevKey]
                    let merged = TextMergeUtilities.mergePlain(base: existingText, appended: orphanedText)
                    let mergedRich = existingText.isEmpty
                        ? orphanedRich
                        : TextMergeUtilities.appendPlainToRichText(
                            base: existingRich,
                            basePlain: existingText,
                            appendedPlain: orphanedText,
                            appendedRich: orphanedRich
                        )
                    note.interstitialContent[prevKey] = merged
                    if let mergedRich = mergedRich {
                        note.interstitialRichContent[prevKey] = mergedRich
                    } else {
                        note.interstitialRichContent.removeValue(forKey: prevKey)
                    }
                } else {
                    let existingBody = note.body ?? ""
                    let merged = TextMergeUtilities.mergePlain(base: existingBody, appended: orphanedText)
                    let mergedRich = TextMergeUtilities.appendPlainToRichText(
                        base: note.bodyRichText,
                        basePlain: existingBody,
                        appendedPlain: orphanedText,
                        appendedRich: orphanedRich
                    )
                    note.body = merged
                    note.bodyRichText = mergedRich
                }
                noteChanged = true
            }

            // Always drop the orphaned slot — the section it referred to is going away.
            if note.interstitialContent.removeValue(forKey: deletedKey) != nil { noteChanged = true }
            if note.interstitialRichContent.removeValue(forKey: deletedKey) != nil { noteChanged = true }

            if noteChanged {
                note.touch()
                try note.update(db)
            }

            // Soft-delete the section in the same transaction.
            if var fresh = try Section.fetchOne(db, key: sectionId) {
                fresh.softDelete()
                try fresh.update(db)
            }

            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
            return true
        }

        if didDelete {
            syncLogger?.logSectionDelete(sectionId)
        }
    }

    // MARK: - Atomic Rewrite

    /// Parameters for an atomic page rewrite. All mutations commit in a single
    /// transaction so `observeNoteWithSections` emits exactly once and the editor
    /// never sees an intermediate "body populated, 0 sections" state.
    struct RewritePagePlan {
        struct SectionUpdate {
            let sectionId: String
            let content: String
            let richText: String?
            let clearRichText: Bool
        }
        struct Interstitial {
            let afterSectionId: String?
            let content: String
            let richText: String?
        }
        let noteId: String
        let body: String
        let bodyRichText: String?
        let clearBodyRichText: Bool
        let keepSectionIds: Set<String>
        let sectionUpdates: [SectionUpdate]
        let interstitials: [Interstitial]
    }

    /// Apply a full page rewrite in one DB transaction. Ensures callers can't
    /// observe the note in a half-updated state (e.g., body rewritten but
    /// sections not yet pruned).
    func applyRewritePage(_ plan: RewritePagePlan) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: plan.noteId) else { return }
            var noteDirty = false

            // 1. Body
            let bodyRichChanged = plan.bodyRichText != nil && note.bodyRichText != plan.bodyRichText
            if note.body != plan.body || bodyRichChanged || plan.clearBodyRichText {
                note.body = plan.body
                if let rich = plan.bodyRichText {
                    note.bodyRichText = rich
                } else if plan.clearBodyRichText {
                    note.bodyRichText = nil
                }
                noteDirty = true
            }

            // 2. Soft-delete sections not in keep set
            let allSections = try Section
                .filter(Section.Columns.noteId == plan.noteId)
                .filter(Section.Columns.deletedAt == nil)
                .fetchAll(db)
            for var section in allSections {
                if !plan.keepSectionIds.contains(section.id) {
                    section.softDelete()
                    try section.update(db)
                }
            }

            // 3. Update kept sections
            for upd in plan.sectionUpdates {
                guard var section = try Section.fetchOne(db, key: upd.sectionId) else { continue }
                let richChanged = (upd.richText != nil && section.richContent != upd.richText) ||
                                  (upd.clearRichText && section.richContent != nil)
                guard section.content != upd.content || richChanged else { continue }
                section.content = upd.content
                if let rich = upd.richText {
                    section.richContent = rich
                } else if upd.clearRichText {
                    section.richContent = nil
                }
                section.touch()
                try section.update(db)
            }

            // 4. Interstitials — apply to the same in-memory note so body and
            // interstitial changes commit together.
            for inter in plan.interstitials {
                let key = inter.afterSectionId.map { "after_\($0)" } ?? "end"
                let oldContent = note.interstitialContent[key] ?? ""
                let oldRich = note.interstitialRichContent[key]
                guard oldContent != inter.content || oldRich != inter.richText else { continue }
                if inter.content.isEmpty {
                    note.interstitialContent.removeValue(forKey: key)
                    note.interstitialRichContent.removeValue(forKey: key)
                } else {
                    note.interstitialContent[key] = inter.content
                    if let rich = inter.richText {
                        note.interstitialRichContent[key] = rich
                    } else {
                        note.interstitialRichContent.removeValue(forKey: key)
                    }
                }
                noteDirty = true
            }

            if noteDirty {
                note.touch()
                try note.update(db)
            }

            try DatabaseManager.recomputeEngagementScore(noteId: plan.noteId, in: db)
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
            try DatabaseManager.recomputeEngagementScore(noteId: note.id, in: db)
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
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    func updateNoteAITitle(_ noteId: String, aiTitle: String?) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.aiTitle = aiTitle
            note.touch()
            try note.update(db)
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    func updateNoteAITags(_ noteId: String, aiTags: [String]) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.aiTags = aiTags
            note.touch()
            try note.update(db)
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    func incrementViewCount(_ noteId: String) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE notes SET viewCount = viewCount + 1 WHERE id = ?",
                arguments: [noteId]
            )
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    func togglePinned(_ noteId: String) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.isPinned.toggle()
            note.touch()
            try note.update(db)
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    func setIntent(_ noteId: String, intent: IntentType) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.intent = intent
            note.touch()
            try note.update(db)
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    func updateTags(_ noteId: String, tags: [String]) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.tags = tags
            note.touch()
            try note.update(db)
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    func setGroupName(noteId: String, groupName: String?) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.groupName = groupName
            note.isPinned = groupName != nil  // Grouped notes are always pinned
            note.touch()
            try note.update(db)
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    func setModuleId(noteId: String, moduleId: String?) async throws {
        try await database.write { db in
            guard var note = try Note.fetchOne(db, key: noteId) else { return }
            note.moduleId = moduleId
            note.touch()
            try note.update(db)
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
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
                    // If all related references are gone, dismiss the insight
                    if newValue == nil && insight.status != .dismissed {
                        insight.status = .dismissed
                    }
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
                    // If all related references are gone, dismiss the insight
                    if newValue == nil && insight.status != .dismissed {
                        insight.status = .dismissed
                    }
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
            try DatabaseManager.recomputeEngagementScore(noteId: id, in: db)
        }
    }
}
