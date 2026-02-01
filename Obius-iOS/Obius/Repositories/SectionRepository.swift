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

    // MARK: - Create

    func createSection(
        noteId: String,
        content: String = "",
        contentType: ContentType = .text,
        sectionType: SectionType = .fold,
        afterSectionId: String? = nil
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
                orderKey: orderKey
            )

            try section.insert(db)

            // Touch the parent note
            if var note = try Note.fetchOne(db, key: noteId) {
                note.touch()
                try note.update(db)
            }

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

    func updateContent(_ sectionId: String, content: String) async throws {
        try await database.write { db in
            guard var section = try Section.fetchOne(db, key: sectionId) else { return }
            section.content = content
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
            section.softDelete()
            try section.update(db)

            // Touch the parent note
            if var note = try Note.fetchOne(db, key: section.noteId) {
                note.touch()
                try note.update(db)
            }
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

            // Verify the handle exists
            guard try Handle.fetchOne(db, key: handleId) != nil else {
                throw HandleError.notFound(handleId)
            }

            section.handleId = handleId
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
        // Get the section's current content
        guard let section = try await getSection(id: sectionId) else {
            throw HandleError.notFound(sectionId)
        }

        // Create the handle with the section's content
        let handle = try await handleRepository.createHandle(
            name: handleName,
            content: section.content,
            intent: section.intent
        )

        // Link the section to the new handle
        try await linkSectionToHandle(sectionId: sectionId, handleId: handle.id)

        return handle
    }
}
