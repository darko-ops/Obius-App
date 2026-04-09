import Foundation
import GRDB
import Combine

@MainActor
final class SectionRepository: ObservableObject {
    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - Observation

    func observeSections(noteId: String) -> AnyPublisher<[Section], Error> {
        database.observeSections(noteId: noteId)
    }

    // MARK: - Create from Shared Content

    /// Inserts a section from shared content, skipping if it already exists.
    func createSectionFromShared(
        id: String,
        noteId: String,
        content: String,
        contentType: String,
        orderKey: String,
        indentLevel: Int,
        intent: String?
    ) async throws {
        try await database.write { db in
            // Skip if already exists
            if try Section.fetchOne(db, key: id) != nil { return }

            let section = Section(
                id: id,
                noteId: noteId,
                content: content,
                contentType: ContentType(rawValue: contentType) ?? .text,
                sectionType: .fold,
                orderKey: orderKey,
                indentLevel: indentLevel,
                intent: IntentType.fromLegacy(intent)
            )
            try section.insert(db)
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    // MARK: - Create

    func createSection(
        noteId: String,
        content: String = "",
        contentType: ContentType = .text,
        sectionType: SectionType = .fold,
        afterSectionId: String? = nil,
        isTemplateContent: Bool = false,
        templatePrefix: String? = nil
    ) async throws -> Section {
        try await database.write { db in
            // Get existing sections to determine order key
            let existingSections = try Section
                .filter(Section.Columns.noteId == noteId)
                .filter(Section.Columns.deletedAt == nil)
                .order(Section.Columns.orderKey)
                .fetchAll(db)

            let orderKey: String
            if let afterId = afterSectionId,
               let afterIndex = existingSections.firstIndex(where: { $0.id == afterId }) {
                let beforeKey = existingSections[afterIndex].orderKey
                let afterKey = afterIndex + 1 < existingSections.count
                    ? existingSections[afterIndex + 1].orderKey
                    : nil
                orderKey = FractionalIndex.between(beforeKey, afterKey)
            } else if existingSections.isEmpty {
                orderKey = FractionalIndex.generateInitialKeys(count: 1)[0]
            } else {
                orderKey = FractionalIndex.after(existingSections.last?.orderKey)
            }

            let section = Section(
                noteId: noteId,
                content: content,
                contentType: contentType,
                sectionType: sectionType,
                orderKey: orderKey,
                isTemplateContent: isTemplateContent,
                templatePrefix: templatePrefix
            )

            try section.insert(db)

            // Touch the parent note
            if var note = try Note.fetchOne(db, key: noteId) {
                note.touch()
                try note.update(db)
            }
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)

            return section
        }
    }

    // MARK: - Read

    func getSection(id: String) async throws -> Section? {
        try await database.read { db in
            try Section.fetchOne(db, key: id)
        }
    }

    func getSections(noteId: String) async throws -> [Section] {
        try await database.read { db in
            try Section
                .filter(Section.Columns.noteId == noteId)
                .filter(Section.Columns.deletedAt == nil)
                .order(Section.Columns.orderKey)
                .fetchAll(db)
        }
    }

    // MARK: - Update

    func updateContent(_ sectionId: String, content: String, richText: String? = nil) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            // Only touch if text content or rich text actually changed.
            let richChanged = richText != nil && section.richContent != richText
            guard section.content != content || richChanged else { return }
            section.content = content
            if let richText = richText {
                section.richContent = richText
            }
            section.touch()
            try section.update(db)

            // Touch the parent note
            if var note = try Note.fetchOne(db, key: section.noteId) {
                note.touch()
                try note.update(db)
            }
        }
    }

    func toggleCollapse(_ sectionId: String) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            section.isCollapsed.toggle()
            section.touch()
            try section.update(db)
        }
    }

    func setIndentLevel(_ sectionId: String, level: Int) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            section.indentLevel = max(0, min(5, level)) // Clamp to 0-5
            section.touch()
            try section.update(db)
        }
    }

    func indent(_ sectionId: String) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            if section.indentLevel < 5 {
                section.indentLevel += 1
                section.touch()
                try section.update(db)
            }
        }
    }

    func outdent(_ sectionId: String) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            if section.indentLevel > 0 {
                section.indentLevel -= 1
                section.touch()
                try section.update(db)
            }
        }
    }

    func setIntent(_ sectionId: String, intent: IntentType) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            section.intent = intent
            section.touch()
            try section.update(db)
        }
    }
    
    func toggleLock(_ sectionId: String) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            section.isLocked.toggle()
            section.touch()
            try section.update(db)
        }
    }
    
    func setTitle(_ sectionId: String, title: String?) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            section.title = title
            section.touch()
            try section.update(db)
        }
    }
    
    // MARK: - Parent/Child Management (Möbius Navigation)
    
    /// Set the parent section ID (for drag-to-indent and hierarchy management)
    func setParentSection(_ sectionId: String, parentId: String?) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            section.parentSectionId = parentId
            
            // Update indent level based on parent
            if let parentId = parentId,
               let parent = try Section.fetchOne(db, key: parentId) {
                section.indentLevel = parent.indentLevel + 1
            } else {
                section.indentLevel = 0
            }
            
            section.touch()
            try section.update(db)
        }
    }
    
    /// Get all child sections of a parent
    func getChildSections(parentId: String) async throws -> [Section] {
        try await database.read { db in
            try Section
                .filter(Section.Columns.parentSectionId == parentId)
                .filter(Section.Columns.deletedAt == nil)
                .order(Section.Columns.orderKey)
                .fetchAll(db)
        }
    }
    
    /// Get sections at a specific level (for Möbius navigation)
    func getSectionsAtLevel(noteId: String, parentId: String?) async throws -> [Section] {
        try await database.read { db in
            try Section
                .filter(Section.Columns.noteId == noteId)
                .filter(Section.Columns.parentSectionId == parentId)
                .filter(Section.Columns.deletedAt == nil)
                .order(Section.Columns.orderKey)
                .fetchAll(db)
        }
    }
    
    /// Check if a section has children
    func hasChildren(_ sectionId: String) async throws -> Bool {
        try await database.read { db in
            let count = try Section
                .filter(Section.Columns.parentSectionId == sectionId)
                .filter(Section.Columns.deletedAt == nil)
                .fetchCount(db)
            return count > 0
        }
    }
    
    /// Get the count of child sections
    func childCount(_ sectionId: String) async throws -> Int {
        try await database.read { db in
            try Section
                .filter(Section.Columns.parentSectionId == sectionId)
                .filter(Section.Columns.deletedAt == nil)
                .fetchCount(db)
        }
    }
    
    /// Move a section and all its children to a new parent
    func reparentSection(_ sectionId: String, newParentId: String?) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            
            let oldParentId = section.parentSectionId
            section.parentSectionId = newParentId
            
            // Calculate new indent level
            let newIndentLevel: Int
            if let parentId = newParentId,
               let parent = try Section.fetchOne(db, key: parentId) {
                newIndentLevel = parent.indentLevel + 1
            } else {
                newIndentLevel = 0
            }
            
            let indentDelta = newIndentLevel - section.indentLevel
            section.indentLevel = newIndentLevel
            section.touch()
            try section.update(db)
            
            // Update all descendants' indent levels
            try Self.updateDescendantIndentLevels(db: db, parentId: sectionId, indentDelta: indentDelta)
        }
    }
    
    /// Recursively update indent levels of all descendants
    private static func updateDescendantIndentLevels(db: Database, parentId: String, indentDelta: Int) throws {
        let children = try Section
            .filter(Section.Columns.parentSectionId == parentId)
            .filter(Section.Columns.deletedAt == nil)
            .fetchAll(db)
        
        for var child in children {
            child.indentLevel = max(0, min(5, child.indentLevel + indentDelta))
            child.touch()
            try child.update(db)
            
            // Recursively update this child's descendants
            try updateDescendantIndentLevels(db: db, parentId: child.id, indentDelta: indentDelta)
        }
    }

    // MARK: - Reorder

    func moveSection(_ sectionId: String, after afterSectionId: String?) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }

            let sections = try Section
                .filter(Section.Columns.noteId == section.noteId)
                .filter(Section.Columns.deletedAt == nil)
                .filter(Section.Columns.id != sectionId)
                .order(Section.Columns.orderKey)
                .fetchAll(db)

            let newOrderKey: String
            if let afterId = afterSectionId,
               let afterIndex = sections.firstIndex(where: { $0.id == afterId }) {
                let beforeKey = sections[afterIndex].orderKey
                let afterKey = afterIndex + 1 < sections.count
                    ? sections[afterIndex + 1].orderKey
                    : nil
                newOrderKey = FractionalIndex.between(beforeKey, afterKey)
            } else if sections.isEmpty {
                newOrderKey = FractionalIndex.generateInitialKeys(count: 1)[0]
            } else if afterSectionId == nil {
                // Move to beginning
                newOrderKey = FractionalIndex.before(sections.first?.orderKey)
            } else {
                // Move to end
                newOrderKey = FractionalIndex.after(sections.last?.orderKey)
            }

            section.orderKey = newOrderKey
            section.touch()
            try section.update(db)
        }
    }

    func moveSectionBetween(_ sectionId: String, before beforeSectionId: String?, after afterSectionId: String?) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }

            let beforeKey = beforeSectionId.flatMap { id in
                try? Section.fetchOne(db, key: id)?.orderKey
            }
            let afterKey = afterSectionId.flatMap { id in
                try? Section.fetchOne(db, key: id)?.orderKey
            }

            section.orderKey = FractionalIndex.between(afterKey, beforeKey)
            section.touch()
            try section.update(db)
        }
    }

    // MARK: - Delete

    func deleteSection(_ sectionId: String) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            let noteId = section.noteId
            section.softDelete()
            try section.update(db)

            // Touch the parent note
            if var note = try Note.fetchOne(db, key: noteId) {
                note.touch()
                try note.update(db)
            }
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    func permanentlyDelete(_ sectionId: String) async throws {
        try await database.write { db in
            try Section.deleteOne(db, key: sectionId)
        }
    }

    // MARK: - Search

    func searchSections(query: String) async throws -> [Section] {
        try await database.searchSections(query: query)
    }

    // MARK: - Handle Loop Support

    /// Link a section to a handle (making it a portal)
    func linkSectionToHandle(sectionId: String, handleId: String) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }

            // Verify the handle exists and copy its content to the section
            guard let handle = try Handle.fetchOne(db, key: handleId) else {
                throw HandleError.notFound(handleId)
            }

            section.handleId = handleId
            section.content = handle.content  // Keep section content in sync for Supabase
            section.touch()
            try section.update(db)

            // Touch the parent note
            if var note = try Note.fetchOne(db, key: section.noteId) {
                note.touch()
                try note.update(db)
            }
        }
    }

    /// Unlink a section from its handle (remove portal mode)
    /// Resolve a sync conflict by accepting current local state and marking for re-push
    func resolveConflict(_ sectionId: String) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            section.syncStatus = .pending
            section.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try section.update(db)
        }
    }

    func unlinkSectionFromHandle(sectionId: String) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            guard section.handleId != nil else { return }  // Already unlinked

            section.handleId = nil
            section.touch()
            try section.update(db)

            // Touch the parent note
            if var note = try Note.fetchOne(db, key: section.noteId) {
                note.touch()
                try note.update(db)
            }
        }
    }

    /// Get all sections linked to a specific handle
    func getSectionsWithHandle(handleId: String) async throws -> [Section] {
        try await database.read { db in
            try Section
                .filter(Section.Columns.handleId == handleId)
                .filter(Section.Columns.deletedAt == nil)
                .order(Section.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Promote a section to a new handle, copying its content
    func promoteToHandle(sectionId: String, handleName: String, handleRepository: HandleRepository) async throws -> Handle {
        // Get the section's current content (may be nil if section was cleaned up)
        let section = try await getSection(id: sectionId)

        // Create the handle — always succeeds even if section is empty or missing
        let handle = try await handleRepository.createHandle(
            name: handleName,
            content: section?.content ?? "",
            intent: section?.intent ?? .idea
        )

        // Link the section to the new handle (if it still exists)
        if section != nil {
            try await linkSectionToHandle(sectionId: sectionId, handleId: handle.id)
        }

        return handle
    }

    // MARK: - Commit Restore

    /// Restores sections from commit snapshots.
    /// Used by CommitModule to restore section state from Cold Store.
    func restoreFromSnapshots(noteId: String, snapshots: [CommitSectionSnapshot]) async throws {
        try await database.write { db in
            // Get existing section IDs for this note
            let existingSections = try Section
                .filter(Section.Columns.noteId == noteId)
                .filter(Section.Columns.deletedAt == nil)
                .fetchAll(db)
            let existingIds = Set(existingSections.map { $0.id })

            // Track snapshot IDs
            let snapshotIds = Set(snapshots.map { $0.id })

            // Soft-delete sections that are not in the snapshot
            for section in existingSections {
                if !snapshotIds.contains(section.id) {
                    var deletedSection = section
                    deletedSection.softDelete()
                    try deletedSection.update(db)
                }
            }

            // Create or update sections from snapshots
            for snapshot in snapshots {
                if existingIds.contains(snapshot.id) {
                    // Update existing section
                    if var section = try Section.fetchOne(db, key: snapshot.id) {
                        section.content = snapshot.content
                        section.contentType = ContentType(rawValue: snapshot.contentType) ?? .text
                        section.sectionType = SectionType(rawValue: snapshot.sectionType) ?? .fold
                        section.intent = IntentType(rawValue: snapshot.intent) ?? .idea
                        section.orderKey = snapshot.orderKey
                        section.indentLevel = snapshot.indentLevel
                        section.parentSectionId = snapshot.parentSectionId
                        section.handleId = snapshot.handleId
                        section.isCollapsed = snapshot.isCollapsed
                        section.isLocked = snapshot.isLocked
                        section.isTemplateContent = snapshot.isTemplateContent
                        section.templatePrefix = snapshot.templatePrefix
                        section.contentBefore = snapshot.contentBefore
                        section.deletedAt = nil  // Ensure not deleted
                        section.touch()
                        try section.update(db)
                    }
                } else {
                    // Create new section from snapshot
                    let section = Section(
                        id: snapshot.id,
                        noteId: noteId,
                        content: snapshot.content,
                        contentType: ContentType(rawValue: snapshot.contentType) ?? .text,
                        sectionType: SectionType(rawValue: snapshot.sectionType) ?? .fold,
                        parentSectionId: snapshot.parentSectionId,
                        orderKey: snapshot.orderKey,
                        indentLevel: snapshot.indentLevel,
                        isCollapsed: snapshot.isCollapsed,
                        isLocked: snapshot.isLocked,
                        isTemplateContent: snapshot.isTemplateContent,
                        templatePrefix: snapshot.templatePrefix,
                        contentBefore: snapshot.contentBefore,
                        intent: IntentType(rawValue: snapshot.intent) ?? .idea,
                        handleId: snapshot.handleId
                    )
                    try section.insert(db)
                }
            }

            // Touch the parent note
            if var note = try Note.fetchOne(db, key: noteId) {
                note.touch()
                try note.update(db)
            }
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }
}
