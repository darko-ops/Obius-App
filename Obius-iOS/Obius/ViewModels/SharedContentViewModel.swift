import Foundation
import Combine

@MainActor
final class SharedContentViewModel: ObservableObject {
    @Published var title: String?
    @Published var shareType: ShareType = .live
    @Published var note: SharedNote?
    @Published var sections: [SharedSection]?
    @Published var commitContent: String?
    @Published var commitName: String?
    @Published var commitSections: [SharedSection] = []
    @Published var commitNoteBody: String?
    @Published var commitHash: String?
    @Published var commitShortId: String?
    @Published var creatorName: String?
    @Published var createdAt: Date?
    @Published var comments: [SharedComment] = []
    @Published var viewCount: Int = 0
    @Published var isLoading = false
    @Published var isArchiving = false
    @Published var isArchived = false
    @Published var errorMessage: String?

    private var shareLinkId: String?
    private var realtimeSubscriber: RealtimeShareSubscriber?
    private var cancellables = Set<AnyCancellable>()

    func loadContent(slug: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await ShareManager.shared.fetchSharedContent(slug: slug)

            shareType = ShareType(rawValue: response.shareType) ?? .live

            shareLinkId = response.shareLinkId
            note = response.note
            // Sort client-side by orderKey using Swift's byte-wise String comparison
            // so preview order matches the sharer's SQLite BINARY ordering regardless
            // of the server's TEXT collation.
            sections = response.sections?.sorted { $0.orderKey < $1.orderKey }
            commitContent = response.commitContent
            commitName = response.commitName
            commitHash = response.commitHash
            commitShortId = response.commitShortId
            creatorName = response.creatorName
            comments = response.comments
            viewCount = response.viewCount

            // Parse the ISO 8601 created date
            if let dateStr = response.createdAt {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                createdAt = formatter.date(from: dateStr)
                    ?? ISO8601DateFormatter().date(from: dateStr)
            }

            // Parse commit JSON into sections for formatted display
            // (may override title with the actual note title from inside the commit)
            if shareType == .commit, let raw = response.commitContent {
                parseCommitContent(raw)
            }

            // Compute title: explicit title first, then auto-title from content
            if let noteTitle = response.note?.title, !noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = noteTitle
            } else if title == nil {
                // Auto-generate from body/section text (same logic as Note.displayTitle)
                title = autoTitle(body: response.note?.body, sections: response.sections) ?? response.commitName ?? "Shared Content"
            }

            // Set up realtime for live shares
            if shareType == .live, let noteId = response.note?.id {
                setupRealtime(noteId: noteId, slug: slug)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func addComment(body: String) async {
        guard let linkId = shareLinkId ?? extractShareLinkId() else { return }

        do {
            let comment = try await ShareManager.shared.addComment(
                shareLinkId: linkId,
                body: body
            )
            comments.append(comment)
            // Local archive is now outdated since a new comment was added
            if isArchived {
                isArchived = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Realtime

    private func setupRealtime(noteId: String, slug: String) {
        let subscriber = RealtimeShareSubscriber(noteId: noteId, slug: slug)

        subscriber.$note
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedNote in
                self?.note = updatedNote
                self?.title = updatedNote.title ?? self?.title
            }
            .store(in: &cancellables)

        subscriber.$sections
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedSections in
                self?.sections = updatedSections.sorted { $0.orderKey < $1.orderKey }
            }
            .store(in: &cancellables)

        subscriber.$comments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedComments in
                if !updatedComments.isEmpty {
                    self?.comments = updatedComments
                }
            }
            .store(in: &cancellables)

        subscriber.subscribe()
        self.realtimeSubscriber = subscriber
    }

    /// Parses the raw JSON commit content into structured sections for display.
    private func parseCommitContent(_ raw: String) {
        guard let data = raw.data(using: .utf8) else { return }

        // CommitContent has: hash, createdAt, note (CommitNoteSnapshot), sections ([CommitSectionSnapshot])
        struct ParsedCommit: Decodable {
            struct NoteSnap: Decodable {
                let title: String?
                let body: String
            }
            struct SectionSnap: Decodable {
                let id: String
                let content: String
                let contentType: String
                let sectionType: String?
                let orderKey: String
                let indentLevel: Int
                let handleId: String?
            }
            let hash: String?
            let createdAt: Int64?
            let note: NoteSnap
            let sections: [SectionSnap]
        }

        do {
            let parsed = try JSONDecoder().decode(ParsedCommit.self, from: data)

            // Prefer the actual note title from inside the commit over the file name
            if let noteTitle = parsed.note.title, !noteTitle.isEmpty {
                title = noteTitle
            }

            // Use commit hash if not already set from share link
            if commitHash == nil, let hash = parsed.hash {
                commitHash = hash
            }

            // Use commit timestamp if available (more accurate than share link creation)
            if let ts = parsed.createdAt {
                createdAt = Date(timeIntervalSince1970: Double(ts) / 1000)
            }

            if !parsed.note.body.isEmpty {
                commitNoteBody = parsed.note.body
            }

            commitSections = parsed.sections
                .sorted { $0.orderKey < $1.orderKey }
                .map { snap in
                    SharedSection(
                        id: snap.id,
                        content: snap.content,
                        contentType: snap.contentType,
                        sectionType: snap.sectionType ?? "fold",
                        orderKey: snap.orderKey,
                        indentLevel: snap.indentLevel,
                        handleId: snap.handleId
                    )
                }
        } catch {
            // Parsing failed — commitContent will still show as raw text fallback
            print("SharedContentViewModel: Failed to parse commit JSON: \(error)")
        }
    }

    // MARK: - Archive / Add to Artifacts

    /// Checks if this content is already saved locally.
    func checkIfArchived(commitRepository: CommitRepository) async {
        if shareType == .commit, let hash = commitHash {
            if let _ = try? await commitRepository.getCommit(hash: hash) {
                isArchived = true
            }
        }
    }

    /// Creates a local note from the shared content and adds it to Artifacts.
    /// `moduleId` scopes the imported note to the recipient's currently-selected project
    /// so it appears in the project they were viewing when they tapped Add.
    func addToArtifacts(coldStore: ColdStore, commitRepository: CommitRepository, noteRepository: NoteRepository, sectionRepository: SectionRepository, moduleId: String? = nil) async {
        guard let sharedNote = note else { return }

        isArchiving = true
        defer { isArchiving = false }

        do {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let noteTitle = title ?? sharedNote.title

            // Create the note locally so it appears on the Artifacts page.
            // interstitialContent carries the free-form text between/after fold nodes —
            // without it the imported page renders as bare nodes with no connecting prose.
            let localNote = Note(
                id: sharedNote.id,
                title: noteTitle,
                body: sharedNote.body,
                interstitialContent: sharedNote.interstitialContent,
                createdAt: now,
                updatedAt: now,
                moduleId: moduleId
            )

            // Insert or update the note locally
            try await noteRepository.saveNote(localNote)

            // Create sections locally
            if let sharedSections = sections {
                for section in sharedSections {
                    try await sectionRepository.createSectionFromShared(
                        id: section.id,
                        noteId: sharedNote.id,
                        content: section.content,
                        contentType: section.contentType,
                        sectionType: section.sectionType,
                        orderKey: section.orderKey,
                        indentLevel: section.indentLevel,
                        intent: section.colorIntent
                    )
                }
            }

            isArchived = true
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    /// Archives the shared commit to the local Cold Store and indexes it in the Hot Store.
    func archiveCommit(coldStore: ColdStore, commitRepository: CommitRepository) async {
        guard let raw = commitContent, let data = raw.data(using: .utf8) else { return }

        isArchiving = true
        defer { isArchiving = false }

        do {
            let content = try JSONDecoder().decode(CommitContent.self, from: data)

            // Check if already archived
            if let _ = try await commitRepository.getCommit(hash: content.hash) {
                isArchived = true
                return
            }

            // Write to Cold Store
            let filePath = try coldStore.writeCommit(content)

            // Index in Hot Store
            let commit = Commit(
                noteId: content.note.id,
                name: commitName,
                hash: content.hash,
                parentHash: content.parentHash,
                filePath: filePath,
                createdAt: content.createdAt
            )
            try await commitRepository.saveCommit(commit)

            isArchived = true
        } catch {
            errorMessage = "Failed to archive: \(error.localizedDescription)"
        }
    }

    /// Derives a title from note body and section content (first 3 words), mirroring Note.displayTitle.
    private func autoTitle(body: String?, sections: [SharedSection]?) -> String? {
        var sources: [String] = []

        if let body = body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            sources.append(body)
        }

        if let sections = sections {
            for section in sections {
                let ct = section.contentType
                if ct == "text" || ct == "checklist" || ct == "code" || ct == "quote" {
                    let t = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { sources.append(t) }
                }
            }
        }

        var words: [String] = []
        for source in sources {
            let sourceWords = source.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            for word in sourceWords {
                words.append(word)
                if words.count >= 3 { break }
            }
            if words.count >= 3 { break }
        }
        guard !words.isEmpty else { return nil }
        return words.prefix(3).joined(separator: " ")
    }

    private func extractShareLinkId() -> String? {
        // The shareLinkId would come from the server response in a full implementation
        // For now, comments use the slug-based API
        nil
    }

    deinit {
        let subscriber = realtimeSubscriber
        Task { @MainActor in
            subscriber?.unsubscribe()
        }
    }
}
