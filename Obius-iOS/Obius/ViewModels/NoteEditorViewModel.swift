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
    @Published var focusedSectionId: String?
    @Published var copiedSections: [Section] = []
    @Published var suggestedEntities: [ExtractedEntity] = []
    private var entityExtractionTask: Task<Void, Never>?

    // Computed hierarchical structure
    var sectionTree: [SectionNode] {
        buildSectionTree(from: sections)
    }

    // Visible sections (respecting collapse state)
    var visibleSections: [Section] {
        getVisibleSections(from: sections)
    }

    var displayTitle: String {
        note?.displayTitle(sections: sections) ?? "Untitled"
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

    func updateTags(_ tags: [String]) async throws {
        try await noteRepository.updateTags(noteId, tags: tags)
    }

    /// Gather all completed hashtags (followed by a space) across body, sections,
    /// and interstitials, then set the note's tags to match.
    /// Tags are added when a space follows `#word` and removed when the `#word` is deleted.
    func syncHashtags() {
        var allText = [note?.body ?? ""]
        for section in sections {
            allText.append(section.content)
        }
        for (_, value) in note?.interstitialContent ?? [:] {
            allText.append(value)
        }
        let combined = allText.joined(separator: " ")
        let found = HashtagHelper.extractTags(from: combined)

        // Build case-insensitive unique list preserving first-seen casing
        var seen = Set<String>()
        var uniqueTags: [String] = []
        for tag in found {
            let lower = tag.lowercased()
            if seen.insert(lower).inserted {
                uniqueTags.append(tag)
            }
        }

        let current = note?.tags ?? []
        let currentSet = Set(current.map { $0.lowercased() })
        let newSet = Set(uniqueTags.map { $0.lowercased() })

        if currentSet != newSet {
            Task { try? await noteRepository.updateTags(noteId, tags: uniqueTags) }
        }
    }

    /// Unique handles linked to sections on this page
    var pageHandles: [Handle] {
        var seen = Set<String>()
        var result: [Handle] = []
        for section in sections {
            if let handle = getHandle(for: section), seen.insert(handle.id).inserted {
                result.append(handle)
            }
        }
        return result
    }

    func updateBody(_ body: String, richText: String? = nil) async throws {
        try await noteRepository.updateNoteBody(noteId, body: body, richText: richText)
        syncHashtags()
        triggerEntityExtraction()
    }

    func updateInterstitialContent(afterSectionId: String?, content: String, richText: String? = nil) async throws {
        try await noteRepository.updateInterstitialContent(noteId, afterSectionId: afterSectionId, content: content, richText: richText)
        syncHashtags()
        triggerEntityExtraction()
    }

    func getInterstitialContent(afterSectionId: String?) -> String {
        let key = afterSectionId.map { "after_\($0)" } ?? "end"
        return note?.interstitialContent[key] ?? ""
    }

    func getInterstitialRichContent(afterSectionId: String?) -> String? {
        let key = afterSectionId.map { "after_\($0)" } ?? "end"
        return note?.interstitialRichContent[key]
    }

    // MARK: - Image Section Support

    func addImageSection(after sectionId: String? = nil) async throws -> Section {
        let section = try await sectionRepository.createSection(
            noteId: noteId,
            content: "",
            contentType: .image,
            afterSectionId: sectionId
        )
        return section
    }

    // MARK: - Audio Section Support

    func addAudioSection(after sectionId: String? = nil) async throws -> Section {
        let section = try await sectionRepository.createSection(
            noteId: noteId,
            content: "",
            contentType: .audio,
            afterSectionId: sectionId
        )
        return section
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

    func updateSectionContent(_ sectionId: String, content: String, richText: String? = nil) async throws {
        try await sectionRepository.updateContent(sectionId, content: content, richText: richText)
    }

    func deleteSection(_ sectionId: String) async throws {
        // Also delete all child sections
        let children = getDescendants(of: sectionId)
        for child in children {
            try await sectionRepository.deleteSection(child.id)
        }

        try await sectionRepository.deleteSection(sectionId)
    }
    
    /// Check whether a section is "dangling" — empty with no content anywhere after it.
    /// Only dangling sections should be auto-deleted; empty sections that hold space
    /// between content (interstitial text, subsequent non-empty sections) must be kept.
    private func isSectionDangling(_ sectionId: String) -> Bool {
        guard let index = sections.firstIndex(where: { $0.id == sectionId }) else { return false }

        // Check the interstitial content immediately after this section
        let interstitialKey = "after_\(sectionId)"
        if let text = note?.interstitialContent[interstitialKey],
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false // Has interstitial content right after it
        }

        // Check all subsequent sections and their interstitials
        for i in (index + 1)..<sections.count {
            let later = sections[i]

            // Any non-empty section means this section is not dangling
            if later.handleId != nil { return false }
            if later.contentType == .image || later.contentType == .audio { return false }
            let laterContentEmpty = later.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let laterPrefixEmpty = (later.templatePrefix ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !laterContentEmpty || !laterPrefixEmpty { return false }

            // Check interstitial after this later section
            let laterKey = "after_\(later.id)"
            if let text = note?.interstitialContent[laterKey],
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }

        // Check the "end" interstitial (after all sections)
        if let text = note?.interstitialContent["end"],
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        return true // Nothing after this section has content — it's dangling
    }

    /// Automatically delete a section if it's empty and dangling (called when focus moves away)
    private func cleanupEmptySection(_ sectionId: String) async {
        // Don't delete the last section
        guard sections.count > 1 else { return }

        // Fetch fresh section data from repository to avoid stale data race condition
        guard let section = try? await sectionRepository.getSection(id: sectionId) else { return }

        // Don't delete portal sections (linked to a handle)
        if section.handleId != nil { return }

        // Don't delete image or audio sections (they have no text content by design)
        if section.contentType == .image { return }
        if section.contentType == .audio { return }

        // Check both content and templatePrefix - don't delete template sections
        let contentEmpty = section.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let prefixEmpty = (section.templatePrefix ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isEmpty = contentEmpty && prefixEmpty

        // Only delete if empty AND dangling (no content after it)
        if isEmpty && isSectionDangling(sectionId) {
            try? await deleteSection(sectionId)
        }
    }

    /// Clean up dangling empty sections (called when leaving the note editor).
    /// Only removes trailing empty sections that have no content after them.
    func cleanupAllEmptySections() async {
        // Don't delete if only 1 section
        guard sections.count > 1 else { return }

        // Work backwards — only delete consecutive dangling empty sections from the tail
        for section in sections.reversed() {
            guard sections.count > 1 else { break }

            // Don't delete portal sections (linked to a handle)
            if section.handleId != nil { break }

            // Don't delete image or audio sections
            if section.contentType == .image { break }
            if section.contentType == .audio { break }

            // Check both content and templatePrefix
            let contentEmpty = section.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let prefixEmpty = (section.templatePrefix ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isEmpty = contentEmpty && prefixEmpty

            if isEmpty && isSectionDangling(section.id) {
                try? await deleteSection(section.id)
            } else {
                // Hit a non-empty or anchored section — stop
                break
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

        // Check if any section has content (including template prefixes, handle links, or images)
        let hasNonEmptySection = sections.contains { section in
            // Portal sections (linked to a handle) are never empty
            if section.handleId != nil { return true }
            // Image/audio sections are never empty (they represent media content)
            if section.contentType == .image { return true }
            if section.contentType == .audio { return true }
            let contentEmpty = section.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let prefixEmpty = (section.templatePrefix ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return !contentEmpty || !prefixEmpty
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

    /// Generate an AI title if the note has content but no user-set or AI title.
    func generateAITitleIfNeeded() {
        guard let note = note else {
            print("🤖 [AI Title] Skipped — note is nil")
            return
        }

        // Don't overwrite a user-set title
        let hasUserTitle = !(note.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasUserTitle {
            print("🤖 [AI Title] Skipped — user title exists")
            return
        }

        // Don't regenerate if already has an AI title
        let hasAITitle = !(note.aiTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasAITitle {
            print("🤖 [AI Title] Skipped — AI title already set: \(note.aiTitle ?? "")")
            return
        }

        // Gather all text content
        var texts: [String] = []
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { texts.append(body) }

        for section in sections where section.contentType == .text || section.contentType == .checklist || section.contentType == .code || section.contentType == .quote {
            let t = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { texts.append(t) }
        }

        for (_, value) in note.interstitialContent {
            let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { texts.append(t) }
        }

        let combined = texts.joined(separator: "\n")
        // Need meaningful content (at least 10 chars) to generate a title
        guard combined.count >= 10 else {
            print("🤖 [AI Title] Skipped — content too short (\(combined.count) chars)")
            return
        }

        print("🤖 [AI Title] Generating for note \(noteId.prefix(8))… (\(combined.count) chars)")

        // Truncate to avoid sending too much text
        let truncated = String(combined.prefix(500))

        Task {
            do {
                let title = try await ClaudeService.generateTitle(from: truncated)
                guard !title.isEmpty else {
                    print("🤖 [AI Title] API returned empty title")
                    return
                }
                try await noteRepository.updateNoteAITitle(noteId, aiTitle: title)
                print("🤖 [AI Title] Saved: \"\(title)\"")
            } catch {
                print("🤖 [AI Title] FAILED: \(error.localizedDescription)")
            }
        }
    }

    /// All tags for display: user hashtags + AI-generated concept tags, deduplicated.
    var allTags: [String] {
        let manual = note?.tags ?? []
        let ai = note?.aiTags ?? []
        var seen = Set<String>()
        var result: [String] = []
        for tag in manual + ai {
            let lower = tag.lowercased()
            if seen.insert(lower).inserted {
                result.append(tag)
            }
        }
        return result
    }

    /// Tags that came from AI only (not present in manual tags). Used for display styling.
    var aiOnlyTags: Set<String> {
        let manualLower = Set((note?.tags ?? []).map { $0.lowercased() })
        return Set((note?.aiTags ?? []).map { $0.lowercased() }.filter { !manualLower.contains($0) })
    }

    /// Remove a tag from both manual and AI tag arrays.
    func removeTag(_ tag: String) async {
        var manualTags = note?.tags ?? []
        manualTags.removeAll { $0.lowercased() == tag.lowercased() }
        try? await noteRepository.updateTags(noteId, tags: manualTags)

        var aiTags = note?.aiTags ?? []
        aiTags.removeAll { $0.lowercased() == tag.lowercased() }
        try? await noteRepository.updateNoteAITags(noteId, aiTags: aiTags)
    }

    /// Generate AI concept tags for notes with substantial content.
    func generateAITagsIfNeeded() {
        guard let note = note else {
            print("🏷️ [AI Tags] Skipped — note is nil")
            return
        }

        // Don't regenerate if already has AI tags
        guard note.aiTags.isEmpty else {
            print("🏷️ [AI Tags] Skipped — already has AI tags: \(note.aiTags)")
            return
        }

        // Gather all text content
        var texts: [String] = []
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { texts.append(body) }

        for section in sections where section.contentType == .text || section.contentType == .checklist || section.contentType == .code || section.contentType == .quote {
            let t = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { texts.append(t) }
        }

        for (_, value) in note.interstitialContent {
            let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { texts.append(t) }
        }

        let combined = texts.joined(separator: "\n")
        // Only tag substantial notes (100+ chars) — skip small jots
        guard combined.count >= 100 else {
            print("🏷️ [AI Tags] Skipped — content too short (\(combined.count) chars, need 100+)")
            return
        }

        print("🏷️ [AI Tags] Generating for note \(noteId.prefix(8))… (\(combined.count) chars)")

        let truncated = String(combined.prefix(500))

        Task {
            do {
                let tags = try await ClaudeService.generateTags(from: truncated)
                guard !tags.isEmpty else {
                    print("🏷️ [AI Tags] API returned empty tags")
                    return
                }
                try await noteRepository.updateNoteAITags(noteId, aiTags: tags)
                print("🏷️ [AI Tags] Saved: \(tags)")
            } catch {
                print("🏷️ [AI Tags] FAILED: \(error.localizedDescription)")
            }
        }
    }

    func copySection(_ sectionId: String) {
        guard let root = sections.first(where: { $0.id == sectionId }) else {
            print("📋 Copy FAILED: section \(sectionId.prefix(8)) not found in \(sections.count) sections")
            return
        }
        // Collect the root section and all its descendants
        copiedSections = [root] + getDescendants(of: sectionId)
        print("📋 Copied \(copiedSections.count) section(s): \(root.content.prefix(30))")
    }

    func pasteSectionAfter(_ afterId: String?) async throws {
        guard let rootSection = copiedSections.first else {
            print("📋 Paste FAILED: no copied sections")
            return
        }
        let targetId = afterId?.isEmpty == true ? sections.last?.id : afterId
        print("📋 Pasting \(copiedSections.count) section(s) after \(targetId?.prefix(8) ?? "end")")

        // Map old IDs to new IDs so we can remap parentSectionId
        var idMap: [String: String] = [:]

        // Create the root section after the target
        do {
            let newRoot = try await createPastedSection(rootSection, afterSectionId: targetId, parentSectionId: nil)
            print("📋 Created root section: \(newRoot.id.prefix(8)) content: \(newRoot.content.prefix(20))")
            idMap[rootSection.id] = newRoot.id

            // Create all descendant sections, preserving parent relationships
            for section in copiedSections.dropFirst() {
                let newParentId = section.parentSectionId.flatMap { idMap[$0] }
                let newSection = try await createPastedSection(section, afterSectionId: nil, parentSectionId: newParentId)
                print("📋 Created child section: \(newSection.id.prefix(8))")
                idMap[section.id] = newSection.id
            }

            focusedSectionId = newRoot.id
            print("📋 Paste complete. Total sections now: \(sections.count)")
        } catch {
            print("📋 Paste CREATE ERROR: \(error)")
            throw error
        }
    }

    /// Helper to create a single pasted section with all its properties
    private func createPastedSection(_ source: Section, afterSectionId: String?, parentSectionId: String?) async throws -> Section {
        let newSection = try await sectionRepository.createSection(
            noteId: noteId,
            content: source.content,
            contentType: source.contentType,
            sectionType: source.sectionType,
            afterSectionId: afterSectionId,
            isTemplateContent: source.isTemplateContent,
            templatePrefix: source.templatePrefix
        )

        // Copy indent level
        try await sectionRepository.setIndentLevel(newSection.id, level: source.indentLevel)

        // Copy rich content
        if let richContent = source.richContent {
            try await sectionRepository.updateContent(newSection.id, content: source.content, richText: richContent)
        }

        // Copy intent
        try await sectionRepository.setIntent(newSection.id, intent: source.intent)

        // Copy title
        if let title = source.title {
            try await sectionRepository.setTitle(newSection.id, title: title)
        }

        // Set parent relationship
        if let parentId = parentSectionId {
            try await sectionRepository.setParentSection(newSection.id, parentId: parentId)
        }

        return newSection
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
            // Preserve interstitial content after the deleted section by merging it
            // into the previous section's interstitial (or the previous section's content)
            if let index = sections.firstIndex(where: { $0.id == sectionId }) {
                let deletedKey = "after_\(sectionId)"
                let orphanedText = note?.interstitialContent[deletedKey] ?? ""
                let orphanedRich = note?.interstitialRichContent[deletedKey]

                if !orphanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if index > 0 {
                        // Merge into the previous section's interstitial
                        let prevId = sections[index - 1].id
                        let prevKey = "after_\(prevId)"
                        let existingText = note?.interstitialContent[prevKey] ?? ""
                        let merged = existingText.isEmpty ? orphanedText : existingText + "\n" + orphanedText
                        // Use the orphaned rich text if there's no existing content, otherwise drop rich (plain merge)
                        let mergedRich = existingText.isEmpty ? orphanedRich : nil
                        try? await noteRepository.updateInterstitialContent(noteId, afterSectionId: prevId, content: merged, richText: mergedRich)
                    }
                }
                // Clean up the orphaned interstitial key
                try? await noteRepository.updateInterstitialContent(noteId, afterSectionId: sectionId, content: "")

                if index > 0 {
                    focusedSectionId = sections[index - 1].id
                }
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
    /// For portals, the section's own content is kept in sync with the handle via SQL propagation
    /// in HandleRepository.updateHandleContent. Using section.content avoids race conditions
    /// between the handle observer and section observer on the main queue.
    func getDisplayContent(for section: Section) -> String {
        if section.handleId != nil {
            // Portal: section.content is always synced with handle content
            // via the SQL propagation in HandleRepository.updateHandleContent.
            // Fall back to handle cache only if section content is empty
            // (e.g. freshly linked before first propagation).
            if section.content.isEmpty,
               let handleId = section.handleId,
               let handleContent = handleManager.getContent(handleId: handleId),
               !handleContent.isEmpty {
                return handleContent
            }
            return section.content
        }
        return section.content
    }

    /// Get the handle for a section (if it's a portal)
    func getHandle(for section: Section) -> Handle? {
        guard let handleId = section.handleId else { return nil }
        return handleManager.getHandle(id: handleId)
    }

    /// Update content - either handle content if portal, or section content
    func updateDisplayContent(_ sectionId: String, content: String, richText: String? = nil) async throws {
        guard let section = getSection(sectionId) else { return }

        if let handleId = section.handleId {
            // This is a portal - update the handle content and propagate rich text
            try await handleManager.updateContent(handleId: handleId, content: content, richText: richText)
        } else {
            // Normal section - update section content
            try await sectionRepository.updateContent(sectionId, content: content, richText: richText)
        }
        syncHashtags()
        triggerEntityExtraction()
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

    // MARK: - Entity Extraction

    func triggerEntityExtraction() {
        entityExtractionTask?.cancel()
        entityExtractionTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second debounce
            guard !Task.isCancelled else { return }
            guard sections.count >= 3 else { return }

            let sectionData = sections.prefix(20).map { (id: $0.id, content: $0.content) }
            let existingHandleNames = Set(HandleManager.shared.handles.map(\.name))

            do {
                let entities = try await ClaudeService.extractEntities(from: sectionData)
                let filtered = entities.filter { !existingHandleNames.contains($0.handleName) }
                await MainActor.run { suggestedEntities = filtered }
            } catch {
                print("[EntityExtraction] Failed: \(error)")
            }
        }
    }

    func dismissEntity(_ entity: ExtractedEntity) {
        suggestedEntities.removeAll { $0.name == entity.name }
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
