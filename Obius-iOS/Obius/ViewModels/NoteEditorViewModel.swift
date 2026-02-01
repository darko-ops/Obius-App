import Foundation
import Combine

@MainActor
final class NoteEditorViewModel: ObservableObject {
    private let noteRepository: NoteRepository
    private let sectionRepository: SectionRepository
    private let handleRepository: HandleRepository
    private let noteId: String
    private var cancellables = Set<AnyCancellable>()
    private var previousFocusedSectionId: String?

    // Handle Manager for real-time handle content
    private let handleManager = HandleManager.shared

    @Published var note: Note?
    @Published var sections: [Section] = []
    @Published var isLoading: Bool = true
    @Published var focusedSectionId: String? {
        didSet {
            print("🎯 Focus changed: \(oldValue?.prefix(8) ?? "nil") -> \(focusedSectionId?.prefix(8) ?? "nil")")
            // Clean up empty section when focus moves away
            if let previousId = oldValue, previousId != focusedSectionId {
                Task {
                    await cleanupEmptySection(previousId)
                }
            }
        }
    }

    // Computed hierarchical structure
    var sectionTree: [SectionNode] {
        buildSectionTree(from: sections)
    }

    // Visible sections (respecting collapse state)
    var visibleSections: [Section] {
        getVisibleSections(from: sections)
    }

    var displayTitle: String {
        note?.displayTitle ?? "Untitled"
    }

    init(noteId: String, noteRepository: NoteRepository, sectionRepository: SectionRepository, handleRepository: HandleRepository) {
        self.noteId = noteId
        self.noteRepository = noteRepository
        self.sectionRepository = sectionRepository
        self.handleRepository = handleRepository

        observeNote()
    }

    private func observeNote() {
        noteRepository.observeNoteWithSections(id: noteId)
            .receive(on: DispatchQueue.main)
            .catch { error -> Just<NoteWithSections?> in
                print("Error observing note: \(error)")
                return Just(nil)
            }
            .sink { [weak self] noteWithSections in
                self?.isLoading = false
                self?.note = noteWithSections?.note
                self?.sections = noteWithSections?.sections ?? []
            }
            .store(in: &cancellables)
    }

    // MARK: - Section Tree Building

    private func buildSectionTree(from sections: [Section]) -> [SectionNode] {
        var nodes: [String: SectionNode] = [:]
        var rootNodes: [SectionNode] = []

        // Create nodes for all sections
        for section in sections {
            nodes[section.id] = SectionNode(section: section)
        }

        // Build tree structure
        for section in sections {
            let node = nodes[section.id]!
            if let parentId = section.parentSectionId, let parentNode = nodes[parentId] {
                parentNode.children.append(node)
            } else {
                rootNodes.append(node)
            }
        }

        return rootNodes
    }

    private func getVisibleSections(from sections: [Section]) -> [Section] {
        var visible: [Section] = []
        var collapsedParents: Set<String> = []

        for section in sections {
            // Check if any ancestor is collapsed
            var isHidden = false
            var currentParentId = section.parentSectionId

            while let parentId = currentParentId {
                if collapsedParents.contains(parentId) {
                    isHidden = true
                    break
                }
                if let parent = sections.first(where: { $0.id == parentId }) {
                    if parent.isCollapsed {
                        collapsedParents.insert(parentId)
                        isHidden = true
                        break
                    }
                    currentParentId = parent.parentSectionId
                } else {
                    break
                }
            }

            if !isHidden {
                visible.append(section)
            }

            if section.isCollapsed {
                collapsedParents.insert(section.id)
            }
        }

        return visible
    }

    // Get child sections of a given section
    func getChildren(of sectionId: String) -> [Section] {
        sections.filter { $0.parentSectionId == sectionId }
    }

    // Check if section has children
    func hasChildren(_ sectionId: String) -> Bool {
        sections.contains { $0.parentSectionId == sectionId }
    }

    // MARK: - Note Actions

    func updateTitle(_ title: String) async throws {
        try await noteRepository.updateNoteTitle(noteId, title: title.isEmpty ? nil : title)
    }

    func togglePinned() async throws {
        try await noteRepository.togglePinned(noteId)
    }

    func setIntent(_ intent: IntentType) async throws {
        try await noteRepository.setIntent(noteId, intent: intent)
    }

    func updateBody(_ body: String) async throws {
        try await noteRepository.updateNoteBody(noteId, body: body)
    }

    func updateInterstitialContent(afterSectionId: String?, content: String) async throws {
        try await noteRepository.updateInterstitialContent(noteId, afterSectionId: afterSectionId, content: content)
    }

    func getInterstitialContent(afterSectionId: String?) -> String {
        let key = afterSectionId.map { "after_\($0)" } ?? "end"
        return note?.interstitialContent[key] ?? ""
    }

    // MARK: - Section Actions

    func addSection(after sectionId: String? = nil) async throws {
        let section = try await sectionRepository.createSection(
            noteId: noteId,
            afterSectionId: sectionId
        )
        focusedSectionId = section.id
    }

    func addSectionWithContent(after sectionId: String? = nil, content: String) async throws {
        let section = try await sectionRepository.createSection(
            noteId: noteId,
            content: content,
            afterSectionId: sectionId
        )
        focusedSectionId = section.id
    }

    func addChildSection(to parentSectionId: String) async throws {
        // Create a section after the parent and set its parent ID
        let section = try await sectionRepository.createSection(
            noteId: noteId,
            afterSectionId: parentSectionId
        )

        // Set the parent and increase indent level
        try await sectionRepository.setIndentLevel(section.id, level: 1)

        focusedSectionId = section.id
    }

    func updateSectionContent(_ sectionId: String, content: String) async throws {
        try await sectionRepository.updateContent(sectionId, content: content)
    }

    func deleteSection(_ sectionId: String) async throws {
        // Don't delete the last section
        guard sections.count > 1 else { return }

        // Also delete all child sections
        let children = getDescendants(of: sectionId)
        for child in children {
            try await sectionRepository.deleteSection(child.id)
        }

        try await sectionRepository.deleteSection(sectionId)
    }
    
    /// Automatically delete a section if it's empty (called when focus moves away)
    private func cleanupEmptySection(_ sectionId: String) async {
        print("🧹 cleanupEmptySection called for: \(sectionId.prefix(8))")
        print("   sections.count = \(sections.count)")

        // Don't delete the last section
        guard sections.count > 1 else {
            print("   ❌ Not deleting - only 1 section left")
            return
        }

        // Fetch fresh section data from repository to avoid stale data race condition
        guard let section = try? await sectionRepository.getSection(id: sectionId) else {
            print("   ❌ Section not found in repository")
            return
        }

        let isEmpty = section.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        print("   content: '\(section.content.prefix(20))' isEmpty: \(isEmpty)")

        if isEmpty {
            print("   ✅ Deleting empty section")
            try? await deleteSection(sectionId)
        }
    }

    /// Clean up all empty sections (called when leaving the note editor)
    func cleanupAllEmptySections() async {
        // Don't delete if only 1 section
        guard sections.count > 1 else { return }

        for section in sections {
            let isEmpty = section.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if isEmpty && sections.count > 1 {
                try? await deleteSection(section.id)
            }
        }
    }

    /// Check if the note is completely empty (no content anywhere)
    var isNoteEmpty: Bool {
        guard let note = note else { return true }

        // Check if title has content (treat "Untitled" as no content)
        let trimmedTitle = note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasTitle = !trimmedTitle.isEmpty && trimmedTitle.lowercased() != "untitled"
        if hasTitle { return false }

        // Check if body has content
        let hasBody = !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasBody { return false }

        // Check if any section has content
        let hasNonEmptySection = sections.contains { section in
            !section.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if hasNonEmptySection { return false }

        // Check if any interstitial content exists
        let hasInterstitialContent = note.interstitialContent.values.contains { content in
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if hasInterstitialContent { return false }

        return true
    }

    /// Clean up the note if it's empty (called when leaving the note editor)
    func cleanupEmptyNoteIfNeeded() async {
        // First clean up empty sections
        await cleanupAllEmptySections()

        // Then check if the entire note is empty and delete it
        if isNoteEmpty {
            print("🗑️ Deleting empty note: \(noteId.prefix(8))")
            try? await noteRepository.deleteNote(noteId)
        }
    }

    func duplicateSection(_ sectionId: String) async throws {
        guard let section = sections.first(where: { $0.id == sectionId }) else { return }

        let newSection = try await sectionRepository.createSection(
            noteId: noteId,
            content: section.content,
            contentType: section.contentType,
            afterSectionId: sectionId
        )

        // Copy indent level
        try await sectionRepository.setIndentLevel(newSection.id, level: section.indentLevel)

        focusedSectionId = newSection.id
    }

    func toggleCollapse(_ sectionId: String) async throws {
        try await sectionRepository.toggleCollapse(sectionId)
    }

    func collapseAll() async throws {
        for section in sections where !section.isCollapsed {
            try await sectionRepository.toggleCollapse(section.id)
        }
    }

    func expandAll() async throws {
        for section in sections where section.isCollapsed {
            try await sectionRepository.toggleCollapse(section.id)
        }
    }

    func indent(_ sectionId: String) async throws {
        try await sectionRepository.indent(sectionId)
    }

    func outdent(_ sectionId: String) async throws {
        try await sectionRepository.outdent(sectionId)
    }

    func setSectionIntent(_ sectionId: String, intent: IntentType) async throws {
        try await sectionRepository.setIntent(sectionId, intent: intent)
    }
    
    func toggleSectionLock(_ sectionId: String) async throws {
        try await sectionRepository.toggleLock(sectionId)
    }

    /// Apply a template by creating sections from the template
    func applyTemplate(_ template: SectionTemplate) async throws {
        // Get the last section to add after
        let lastSectionId = sections.last?.id

        var previousSectionId = lastSectionId

        for templateSection in template.sections {
            // Map template item type to section type
            let sectionType: SectionType = templateSection.itemType == .line ? .line : .fold

            // Create the section
            let newSection = try await sectionRepository.createSection(
                noteId: noteId,
                content: templateSection.content,
                sectionType: sectionType,
                afterSectionId: previousSectionId
            )

            // Set intent if not default (only for folds)
            if sectionType == .fold && templateSection.intent != .idea {
                try await sectionRepository.setIntent(newSection.id, intent: templateSection.intent)
            }

            // Set indent level if not 0
            if templateSection.indentLevel > 0 {
                try await sectionRepository.setIndentLevel(newSection.id, level: templateSection.indentLevel)
            }

            previousSectionId = newSection.id
        }

        // Focus the first new section
        if let firstTemplateSection = template.sections.first,
           let newFirstSection = sections.first(where: { $0.content == firstTemplateSection.content }) {
            focusedSectionId = newFirstSection.id
        }
    }

    /// Apply a template before a specific section (template sections appear above, existing content stays below)
    func applyTemplateToSection(_ template: SectionTemplate, beforeSectionId: String) async throws {
        // Find the section before the target section to insert after
        guard let targetIndex = sections.firstIndex(where: { $0.id == beforeSectionId }) else { return }

        // Get the section ID to insert after (the one before our target, or nil if target is first)
        let afterSectionId = targetIndex > 0 ? sections[targetIndex - 1].id : nil

        var previousSectionId = afterSectionId

        for templateSection in template.sections {
            // Map template item type to section type
            let sectionType: SectionType = templateSection.itemType == .line ? .line : .fold

            // Create the section
            let newSection = try await sectionRepository.createSection(
                noteId: noteId,
                content: templateSection.content,
                sectionType: sectionType,
                afterSectionId: previousSectionId
            )

            // Set intent if not default (only for folds)
            if sectionType == .fold && templateSection.intent != .idea {
                try await sectionRepository.setIntent(newSection.id, intent: templateSection.intent)
            }

            // Set indent level if not 0
            if templateSection.indentLevel > 0 {
                try await sectionRepository.setIndentLevel(newSection.id, level: templateSection.indentLevel)
            }

            previousSectionId = newSection.id
        }
    }

    // MARK: - Parent/Child Management (Möbius Navigation)
    
    /// Set the parent section ID (for drag-to-indent)
    func setParentSection(_ sectionId: String, parentId: String?) async throws {
        try await sectionRepository.setParentSection(sectionId, parentId: parentId)
    }
    
    /// Get sections at a specific navigation level
    func getSectionsAtLevel(parentId: String?) -> [Section] {
        sections.filter { $0.parentSectionId == parentId }
    }
    
    /// Get the count of children for a section
    func childCount(_ sectionId: String) -> Int {
        sections.filter { $0.parentSectionId == sectionId }.count
    }
    
    /// Get a section by ID
    func getSection(_ sectionId: String) -> Section? {
        sections.first { $0.id == sectionId }
    }

    func moveSection(_ sectionId: String, to index: Int) async throws {
        let targetIndex = max(0, min(index, sections.count - 1))
        let afterSectionId = targetIndex > 0 ? sections[targetIndex - 1].id : nil
        try await sectionRepository.moveSection(sectionId, after: afterSectionId)
    }

    func moveSectionUp(_ sectionId: String) async throws {
        guard let currentIndex = sections.firstIndex(where: { $0.id == sectionId }),
              currentIndex > 0 else { return }

        let targetIndex = currentIndex - 1
        try await moveSection(sectionId, to: targetIndex)
    }

    func moveSectionDown(_ sectionId: String) async throws {
        guard let currentIndex = sections.firstIndex(where: { $0.id == sectionId }),
              currentIndex < sections.count - 1 else { return }

        let targetIndex = currentIndex + 2 // +2 because we insert after
        try await moveSection(sectionId, to: targetIndex)
    }

    // MARK: - Keyboard Shortcuts

    func handleReturn(sectionId: String) async throws {
        try await addSection(after: sectionId)
    }

    func handleBackspace(sectionId: String, isEmpty: Bool) async throws {
        if isEmpty && sections.count > 1 {
            // Delete empty section and focus previous
            if let index = sections.firstIndex(where: { $0.id == sectionId }), index > 0 {
                focusedSectionId = sections[index - 1].id
            }
            try await deleteSection(sectionId)
        }
    }

    func handleTab(sectionId: String) async throws {
        try await indent(sectionId)
    }

    func handleShiftTab(sectionId: String) async throws {
        try await outdent(sectionId)
    }

    // MARK: - Helpers

    private func getDescendants(of sectionId: String) -> [Section] {
        var descendants: [Section] = []
        let children = getChildren(of: sectionId)

        for child in children {
            descendants.append(child)
            descendants.append(contentsOf: getDescendants(of: child.id))
        }

        return descendants
    }

    // MARK: - Handle Loop Support

    /// Promote a section's content to a new global handle
    /// - Parameters:
    ///   - sectionId: The section to promote
    ///   - handleName: The name for the new handle (without @)
    /// - Returns: The created handle
    func promoteToHandle(sectionId: String, handleName: String) async throws -> Handle {
        try await sectionRepository.promoteToHandle(
            sectionId: sectionId,
            handleName: handleName,
            handleRepository: handleRepository
        )
    }

    /// Link a section to an existing handle (making it a portal)
    func linkToExistingHandle(sectionId: String, handleId: String) async throws {
        try await sectionRepository.linkSectionToHandle(sectionId: sectionId, handleId: handleId)
    }

    /// Unlink a section from its handle
    func unlinkFromHandle(sectionId: String) async throws {
        // Get the handle content first to preserve it in the section
        if let section = getSection(sectionId),
           let handleId = section.handleId,
           let handle = handleManager.getHandle(id: handleId) {
            // Update section content with handle content before unlinking
            try await sectionRepository.updateContent(sectionId, content: handle.content)
        }
        try await sectionRepository.unlinkSectionFromHandle(sectionId: sectionId)
    }

    /// Get the display content for a section (handle content if portal, otherwise section content)
    func getDisplayContent(for section: Section) -> String {
        if let handleId = section.handleId,
           let handleContent = handleManager.getContent(handleId: handleId) {
            return handleContent
        }
        return section.content
    }

    /// Get the handle for a section (if it's a portal)
    func getHandle(for section: Section) -> Handle? {
        guard let handleId = section.handleId else { return nil }
        return handleManager.getHandle(id: handleId)
    }

    /// Update content - either handle content if portal, or section content
    func updateDisplayContent(_ sectionId: String, content: String) async throws {
        guard let section = getSection(sectionId) else { return }

        if let handleId = section.handleId {
            // This is a portal - update the handle content
            try await handleManager.updateContent(handleId: handleId, content: content)
        } else {
            // Normal section - update section content
            try await sectionRepository.updateContent(sectionId, content: content)
        }
    }

    /// Detect if content starts with @HandleName and hydrate section with that handle
    /// Returns the handle if found and linked, nil otherwise
    func detectAndHydrateHandle(sectionId: String, content: String) async throws -> Handle? {
        guard let handle = handleManager.detectHandleAtStart(in: content) else {
            return nil
        }

        // Link the section to the handle
        try await linkToExistingHandle(sectionId: sectionId, handleId: handle.id)

        return handle
    }

    /// Create a new section linked to an existing handle
    func addSectionLinkedToHandle(handleId: String, after sectionId: String? = nil) async throws {
        let section = try await sectionRepository.createSection(
            noteId: noteId,
            afterSectionId: sectionId
        )

        // Link to the handle
        try await sectionRepository.linkSectionToHandle(sectionId: section.id, handleId: handleId)

        focusedSectionId = section.id
    }
}

// MARK: - Section Node (for tree view)

class SectionNode: Identifiable, ObservableObject {
    let id: String
    let section: Section
    @Published var children: [SectionNode] = []

    var isExpanded: Bool {
        !section.isCollapsed
    }

    init(section: Section) {
        self.id = section.id
        self.section = section
    }
}
