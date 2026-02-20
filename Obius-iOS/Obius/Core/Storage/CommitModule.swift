import Foundation

/// CommitModule is the bridge between the Hot Store (SQLite) and Cold Store (file system).
/// It handles creating commits from current note state and restoring notes from commits.
@MainActor
class CommitModule: ObservableObject {
    private let coldStore: ColdStore
    private let noteRepository: NoteRepository
    private let sectionRepository: SectionRepository
    private let commitRepository: CommitRepository

    init(
        coldStore: ColdStore,
        noteRepository: NoteRepository,
        sectionRepository: SectionRepository,
        commitRepository: CommitRepository
    ) {
        self.coldStore = coldStore
        self.noteRepository = noteRepository
        self.sectionRepository = sectionRepository
        self.commitRepository = commitRepository
    }

    // MARK: - Create Commit

    /// Creates a commit from the current state of a note in the Hot Store.
    /// - Parameters:
    ///   - noteId: The note to commit
    ///   - mediaRefs: Optional media references to include in the commit
    /// - Returns: The created Commit record
    func createCommit(noteId: String, name: String? = nil, titleOverride: String? = nil, mediaRefs: [MediaReference] = [], isAutoCommit: Bool = false) async throws -> Commit {
        // 1. Fetch current note state from Hot Store
        guard let note = try await noteRepository.getNote(id: noteId) else {
            throw CommitError.noteNotFound
        }

        let sections = try await sectionRepository.getSections(noteId: noteId)

        // 2. Get parent hash (latest commit for this note, if any)
        let parentHash = try await commitRepository.getLatestCommit(noteId: noteId)?.hash

        // 3. Create snapshots (apply title override if provided)
        var noteSnapshot = CommitNoteSnapshot(from: note)
        if let titleOverride = titleOverride {
            noteSnapshot = CommitNoteSnapshot(
                id: noteSnapshot.id,
                title: titleOverride,
                body: noteSnapshot.body,
                intent: noteSnapshot.intent,
                isPinned: noteSnapshot.isPinned,
                createdAt: noteSnapshot.createdAt,
                updatedAt: noteSnapshot.updatedAt,
                interstitialContent: noteSnapshot.interstitialContent
            )
        }
        let sectionSnapshots = sections.map { CommitSectionSnapshot(from: $0) }

        // 4. Compute content hash
        let hash = coldStore.computeCommitHash(
            parentHash: parentHash,
            note: noteSnapshot,
            sections: sectionSnapshots,
            mediaRefs: mediaRefs
        )

        // 5. Create commit content
        let commitContent = CommitContent(
            version: 1,
            hash: hash,
            parentHash: parentHash,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            note: noteSnapshot,
            sections: sectionSnapshots,
            mediaRefs: mediaRefs
        )

        // 6. Write to Cold Store
        let filePath = try coldStore.writeCommit(commitContent)

        // 7. Record commit in Hot Store for quick lookup
        let commit = Commit(
            noteId: noteId,
            name: name,
            hash: hash,
            parentHash: parentHash,
            filePath: filePath,
            isAutoCommit: isAutoCommit
        )

        try await commitRepository.saveCommit(commit)

        return commit
    }

    // MARK: - Node Commit (Named)

    /// Creates a named node commit for a single section.
    /// - Parameters:
    ///   - sectionId: The section to commit
    ///   - name: The user-provided name (without .obx extension)
    /// - Returns: The filename (name.obx)
    func createNodeCommit(sectionId: String, name: String) async throws -> String {
        // 1. Fetch the section
        guard let section = try await sectionRepository.getSection(id: sectionId) else {
            throw CommitError.sectionNotFound
        }

        // 2. Get the source note info
        let note = try await noteRepository.getNote(id: section.noteId)

        // 3. Create section snapshot
        let sectionSnapshot = CommitSectionSnapshot(from: section)

        // 4. Create node content
        let nodeContent = NodeCommitContent(
            name: name,
            section: sectionSnapshot,
            sourceNoteId: section.noteId,
            sourceNoteTitle: note?.displayTitle
        )

        // 5. Write to Cold Store (hash is computed and embedded in the file)
        let (filename, _) = try coldStore.writeNodeCommit(nodeContent, name: name)

        return filename
    }

    /// Checks if a node commit name is available.
    /// - Parameter name: The name to check
    /// - Returns: true if the name is available
    func isNodeNameAvailable(_ name: String) -> Bool {
        !coldStore.nodeCommitExists(name: name)
    }

    /// Gets all node commits.
    /// - Returns: Array of node names
    func getAllNodeCommits() -> [String] {
        coldStore.getAllNodeCommits()
    }

    /// Gets a node commit by name.
    /// - Parameter name: The node name
    /// - Returns: The node content
    func getNodeCommit(name: String) throws -> NodeCommitContent {
        try coldStore.readNodeCommit(name: name)
    }

    /// Deletes a node commit.
    /// - Parameter name: The node name to delete
    func deleteNodeCommit(name: String) throws {
        try coldStore.deleteNodeCommit(name: name)
    }

    // MARK: - Restore Commit

    /// Restores a note to a specific commit state.
    /// This overwrites the current Hot Store state with the commit's snapshot.
    /// - Parameter hash: The commit hash to restore to
    func restoreCommit(hash: String) async throws {
        // 1. Read commit from Cold Store
        let content = try coldStore.readCommit(hash: hash)

        // 2. Verify hash integrity
        let computedHash = coldStore.computeCommitHash(
            parentHash: content.parentHash,
            note: content.note,
            sections: content.sections,
            mediaRefs: content.mediaRefs
        )

        guard computedHash == content.hash else {
            throw CommitError.hashMismatch
        }

        // 3. Restore note state
        try await restoreNoteFromSnapshot(content.note)

        // 4. Restore sections
        try await restoreSectionsFromSnapshots(
            noteId: content.note.id,
            sections: content.sections
        )
    }

    /// Restores a note to a specific commit by commit ID.
    /// - Parameter commitId: The commit ID (not hash) to restore to
    func restoreCommitById(commitId: String) async throws {
        guard let commit = try await commitRepository.getCommit(id: commitId) else {
            throw CommitError.commitNotFound
        }

        try await restoreCommit(hash: commit.hash)
    }

    // MARK: - Commit History

    /// Gets the commit history for a note.
    /// - Parameter noteId: The note to get history for
    /// - Returns: Array of commits, newest first
    func getCommitHistory(noteId: String) async throws -> [Commit] {
        try await commitRepository.getCommits(noteId: noteId)
    }

    /// Gets the full commit content for a specific commit.
    /// - Parameter hash: The commit hash
    /// - Returns: The full commit content from Cold Store
    func getCommitContent(hash: String) throws -> CommitContent {
        try coldStore.readCommit(hash: hash)
    }

    /// Gets the commit chain from a specific commit back to the root.
    /// - Parameter hash: Starting commit hash
    /// - Returns: Array of commit contents, from given commit to root
    func getCommitChain(from hash: String) throws -> [CommitContent] {
        var chain: [CommitContent] = []
        var currentHash: String? = hash

        while let hash = currentHash {
            let content = try coldStore.readCommit(hash: hash)
            chain.append(content)
            currentHash = content.parentHash
        }

        return chain
    }

    // MARK: - Diff

    /// Compares two commits and returns what changed.
    /// - Parameters:
    ///   - oldHash: The older commit hash
    ///   - newHash: The newer commit hash
    /// - Returns: A diff describing changes
    func diffCommits(oldHash: String, newHash: String) throws -> CommitDiff {
        let oldContent = try coldStore.readCommit(hash: oldHash)
        let newContent = try coldStore.readCommit(hash: newHash)

        // Compare notes
        let noteChanged = oldContent.note.title != newContent.note.title ||
                          oldContent.note.body != newContent.note.body ||
                          oldContent.note.intent != newContent.note.intent ||
                          oldContent.note.isPinned != newContent.note.isPinned

        // Compare sections
        let oldSectionIds = Set(oldContent.sections.map { $0.id })
        let newSectionIds = Set(newContent.sections.map { $0.id })

        let addedSections = newSectionIds.subtracting(oldSectionIds)
        let removedSections = oldSectionIds.subtracting(newSectionIds)

        var modifiedSections: Set<String> = []
        for newSection in newContent.sections {
            if let oldSection = oldContent.sections.first(where: { $0.id == newSection.id }) {
                if oldSection.content != newSection.content ||
                   oldSection.intent != newSection.intent ||
                   oldSection.orderKey != newSection.orderKey ||
                   oldSection.indentLevel != newSection.indentLevel {
                    modifiedSections.insert(newSection.id)
                }
            }
        }

        return CommitDiff(
            noteChanged: noteChanged,
            addedSectionIds: addedSections,
            removedSectionIds: removedSections,
            modifiedSectionIds: modifiedSections
        )
    }

    // MARK: - Private Helpers

    private func restoreNoteFromSnapshot(_ snapshot: CommitNoteSnapshot) async throws {
        try await noteRepository.restoreFromSnapshot(
            id: snapshot.id,
            title: snapshot.title,
            body: snapshot.body,
            intent: IntentType(rawValue: snapshot.intent) ?? .idea,
            isPinned: snapshot.isPinned
        )
    }

    private func restoreSectionsFromSnapshots(noteId: String, sections: [CommitSectionSnapshot]) async throws {
        try await sectionRepository.restoreFromSnapshots(noteId: noteId, snapshots: sections)
    }
}

// MARK: - CommitDiff

/// Describes the differences between two commits.
struct CommitDiff {
    let noteChanged: Bool
    let addedSectionIds: Set<String>
    let removedSectionIds: Set<String>
    let modifiedSectionIds: Set<String>

    var hasChanges: Bool {
        noteChanged || !addedSectionIds.isEmpty || !removedSectionIds.isEmpty || !modifiedSectionIds.isEmpty
    }

    var summary: String {
        var parts: [String] = []

        if noteChanged {
            parts.append("note modified")
        }
        if !addedSectionIds.isEmpty {
            parts.append("\(addedSectionIds.count) section(s) added")
        }
        if !removedSectionIds.isEmpty {
            parts.append("\(removedSectionIds.count) section(s) removed")
        }
        if !modifiedSectionIds.isEmpty {
            parts.append("\(modifiedSectionIds.count) section(s) modified")
        }

        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}
