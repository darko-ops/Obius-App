import Foundation

/// Lightweight summary of a commit for AI context.
struct VersionSummary {
    let name: String
    let relativeTime: String
    let bodyPreview: String
    let sectionPreviews: [String]
}

/// Two-stage context retriever for the AI Workspace.
/// Replaces the brute-force buildRichContext() with:
///   Stage 1: Local FTS5 keyword search (fast, offline-capable)
///   Stage 2: Semantic rerank via Supabase (Pro tier, online only)
@MainActor
final class ContextAssembler {
    private let noteIndexRepo: NoteIndexRepository
    private let sectionRepository: SectionRepository
    private let noteRepository: NoteRepository
    private let handleRepository: HandleRepository
    private let database: DatabaseManager
    private let syncEngine: SyncEngine

    /// Maximum tokens to include in assembled context.
    private let maxBudget = 3500
    /// Budget for project-wide context (more generous since it's the primary context).
    private let projectBudget = 5000

    init(
        noteIndexRepo: NoteIndexRepository,
        sectionRepository: SectionRepository,
        noteRepository: NoteRepository,
        handleRepository: HandleRepository,
        database: DatabaseManager,
        syncEngine: SyncEngine
    ) {
        self.noteIndexRepo = noteIndexRepo
        self.sectionRepository = sectionRepository
        self.noteRepository = noteRepository
        self.handleRepository = handleRepository
        self.database = database
        self.syncEngine = syncEngine
    }

    // MARK: - Public API

    /// Assemble context for an AI request.
    /// - Parameters:
    ///   - query: The user's message text.
    ///   - focusedNote: The currently selected page (full JSON context).
    ///   - focusedSections: Cached sections for the focused page.
    ///   - selectedHandles: Loops the user has explicitly selected.
    ///   - focusedSectionId: A specific section the user wants to edit (section-level trigger).
    /// - Returns: A context string ready to pass as `noteContext` to ClaudeService.
    func assembleContext(
        query: String,
        focusedNote: Note?,
        focusedSections: [Section],
        selectedHandles: [Handle],
        focusedSectionId: String? = nil,
        versionHistory: [VersionSummary] = []
    ) async -> String {
        var contextParts: [String] = []
        var remainingBudget = maxBudget

        // 1. Focused section context (highest priority when section-level editing)
        if let sectionId = focusedSectionId,
           let section = focusedSections.first(where: { $0.id == sectionId }) {
            let sectionContext = buildFocusedSectionContext(
                section: section,
                allSections: focusedSections,
                note: focusedNote
            )
            contextParts.append(sectionContext)
            remainingBudget -= NoteIndexRepository.estimateTokens(sectionContext)
        }

        // 2. Focused page context (full structured JSON)
        if let note = focusedNote {
            let pageContext = buildStructuredPageContext(page: note, sections: focusedSections)
            contextParts.append(pageContext)
            remainingBudget -= NoteIndexRepository.estimateTokens(pageContext)
        }

        // 3. Version history (recent commits for the focused page)
        if !versionHistory.isEmpty {
            let historyContext = buildVersionHistoryContext(versions: versionHistory)
            contextParts.append(historyContext)
            remainingBudget -= NoteIndexRepository.estimateTokens(historyContext)
        }

        // 4. Selected loops
        if !selectedHandles.isEmpty {
            let loopContext: String = selectedHandles.map { handle -> String in
                let cleaned = handle.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = cleaned.isEmpty ? "(empty)" : cleaned
                return "Loop: @\(handle.displayName) (id: \(handle.id))\nContent:\n\(preview)"
            }.joined(separator: "\n\n---\n\n")
            contextParts.append("Selected loop content:\n\n\(loopContext)")
            remainingBudget -= NoteIndexRepository.estimateTokens(loopContext)
        }

        // 5. Retrieve related sections (two-stage)
        if remainingBudget > 200 {
            let relatedContext = await retrieveRelatedContext(
                query: query,
                excludeNoteId: focusedNote?.id,
                budget: remainingBudget
            )
            if !relatedContext.isEmpty {
                contextParts.append(relatedContext)
            }
        }

        return contextParts.joined(separator: "\n\n")
    }

    // MARK: - Project-Wide Context

    /// Assemble context for project-wide edit mode.
    /// Includes summaries of all pages in the module so the AI understands the full project.
    func assembleProjectContext(
        query: String,
        moduleId: String,
        selectedHandles: [Handle]
    ) async -> String {
        var contextParts: [String] = []
        var remainingBudget = projectBudget

        // 1. Project overview — summaries of all pages in this module
        let projectNotes = noteRepository.notes.filter {
            !$0.isDeleted && $0.moduleId == moduleId
        }

        if !projectNotes.isEmpty {
            var pageSummaries: [String] = ["PROJECT CONTEXT — All pages in this project (\(projectNotes.count) total):"]

            for note in projectNotes.prefix(30) {
                guard remainingBudget > 100 else { break }

                let title = note.displayTitle
                let bodyPreview = Self.cleanContentForAI(note.body, truncate: true)

                // Fetch sections for this note
                let sections = (try? await sectionRepository.getSections(noteId: note.id)) ?? []
                let sectionPreviews = sections
                    .filter { $0.contentType != .image && $0.contentType != .audio && $0.deletedAt == nil }
                    .prefix(5)
                    .compactMap { section -> String? in
                        let content = Self.cleanContentForAI(section.content, truncate: true)
                        guard !content.isEmpty else { return nil }
                        let handleTag = section.handleId
                            .flatMap { HandleManager.shared.getHandle(id: $0) }
                            .map { "@\($0.displayName): " } ?? ""
                        return "  - \(handleTag)\(content)"
                    }

                // Build interstitial previews
                let interstitialPreviews = Array(note.interstitialContent.values
                    .compactMap { value -> String? in
                        let cleaned = Self.cleanContentForAI(value, truncate: true)
                        return cleaned.isEmpty ? nil : "  > \(cleaned)"
                    }
                    .prefix(3))

                var entry = "---\nPage: \"\(title)\" (id: \(note.id))"
                if !bodyPreview.isEmpty {
                    entry += "\nBody: \(bodyPreview)"
                }
                if !sectionPreviews.isEmpty {
                    entry += "\nNodes:\n" + sectionPreviews.joined(separator: "\n")
                }
                if !interstitialPreviews.isEmpty {
                    entry += "\nNotes:\n" + interstitialPreviews.joined(separator: "\n")
                }

                let tokenCost = NoteIndexRepository.estimateTokens(entry)
                guard remainingBudget - tokenCost > 0 else { break }
                pageSummaries.append(entry)
                remainingBudget -= tokenCost
            }

            contextParts.append(pageSummaries.joined(separator: "\n"))
        }

        // 2. Selected loops
        if !selectedHandles.isEmpty {
            let loopContext: String = selectedHandles.map { handle -> String in
                let cleaned = handle.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = cleaned.isEmpty ? "(empty)" : cleaned
                return "Loop: @\(handle.displayName) (id: \(handle.id))\nContent:\n\(preview)"
            }.joined(separator: "\n\n---\n\n")
            contextParts.append("Selected loop content:\n\n\(loopContext)")
            remainingBudget -= NoteIndexRepository.estimateTokens(loopContext)
        }

        // 3. Retrieve related sections via search
        if remainingBudget > 200 {
            let relatedContext = await retrieveRelatedContext(
                query: query,
                excludeNoteId: nil,
                budget: remainingBudget
            )
            if !relatedContext.isEmpty {
                contextParts.append(relatedContext)
            }
        }

        return contextParts.joined(separator: "\n\n")
    }

    // MARK: - Version History Context

    private func buildVersionHistoryContext(versions: [VersionSummary]) -> String {
        var parts: [String] = ["Previous versions of this page (newest first):"]
        for version in versions {
            var entry = "---\nVersion: \(version.name) | \(version.relativeTime)"
            if !version.bodyPreview.isEmpty {
                entry += "\nBody: \(version.bodyPreview)"
            }
            if !version.sectionPreviews.isEmpty {
                entry += "\nNodes:\n" + version.sectionPreviews.joined(separator: "\n")
            }
            parts.append(entry)
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Stage 1: Local Keyword Retrieval

    private func retrieveRelatedContext(
        query: String,
        excludeNoteId: String?,
        budget: Int
    ) async -> String {
        // Stage 1: FTS5 keyword search
        let ftsResults = await noteIndexRepo.search(
            query: query,
            limit: 15,
            excludeNoteId: excludeNoteId
        )

        // Stage 2: Semantic rerank (Pro tier only)
        var semanticResults: [SemanticSearchResult] = []
        let canSemantic = TierManager.shared.limits.semanticSearch
        if canSemantic {
            do {
                semanticResults = try await syncEngine.semanticSearch(query: query, limit: 15)
                // Filter out focused note's sections
                if let excludeId = excludeNoteId {
                    semanticResults = semanticResults.filter { $0.noteId != excludeId }
                }
            } catch {
                // Graceful degradation — continue with FTS results only
                print("[ContextAssembler] Semantic search failed, using FTS only: \(error)")
            }
        }

        // Merge results: semantic results get priority, then FTS results fill gaps
        var rankedSectionIds: [String] = []
        var seen = Set<String>()

        // Semantic results first (higher quality)
        for result in semanticResults {
            if seen.insert(result.sectionId).inserted {
                rankedSectionIds.append(result.sectionId)
            }
        }

        // FTS results fill remaining slots
        for result in ftsResults {
            if seen.insert(result.id).inserted {
                rankedSectionIds.append(result.id)
            }
        }

        // Build context within budget
        var parts: [String] = []
        var usedBudget = 0
        var noteIdToTitle: [String: String] = [:]

        for sectionId in rankedSectionIds {
            guard usedBudget < budget else { break }

            do {
                guard let section = try await sectionRepository.getSection(id: sectionId) else { continue }
                let content = Self.cleanContentForAI(section.content, truncate: false)
                guard !content.isEmpty else { continue }

                let tokenCost = NoteIndexRepository.estimateTokens(content)
                guard usedBudget + tokenCost <= budget else { continue }

                // Get note title for context (cache to avoid repeated lookups)
                var noteTitle = ""
                let noteId = section.noteId
                if let cached = noteIdToTitle[noteId] {
                    noteTitle = cached
                } else if let note = try await noteRepository.getNote(id: noteId) {
                    noteTitle = note.displayTitle
                    noteIdToTitle[noteId] = noteTitle
                }

                let handleTag = section.handleId
                    .flatMap { HandleManager.shared.getHandle(id: $0) }
                    .map { "@\($0.displayName): " } ?? ""

                let header = noteTitle.isEmpty ? "" : "From \"\(noteTitle)\": "
                parts.append("\(header)\(handleTag)\(content)")
                usedBudget += tokenCost
            } catch {
                continue
            }
        }

        if parts.isEmpty { return "" }
        return "Related content from your project:\n\n\(parts.joined(separator: "\n\n"))"
    }

    // MARK: - Focused Section Context

    private func buildFocusedSectionContext(
        section: Section,
        allSections: [Section],
        note: Note?
    ) -> String {
        var parts: [String] = []
        parts.append("TARGET SECTION (the user wants to edit this specific section):")
        parts.append("Section ID: \(section.id)")
        // Use markdown from rich text so the AI can see existing formatting
        parts.append("Content: \(Self.contentForAI(section.content, richText: section.richContent))")
        parts.append("Type: \(section.contentType.rawValue)")
        parts.append("Intent: \(section.intent.rawValue)")

        // Include surrounding sections for context
        let active = allSections.filter { $0.deletedAt == nil }
        if let idx = active.firstIndex(where: { $0.id == section.id }) {
            if idx > 0 {
                let prev = active[idx - 1]
                parts.append("\nPreceding section: \(Self.contentForAI(prev.content, richText: prev.richContent, truncate: true))")
            }
            if idx < active.count - 1 {
                let next = active[idx + 1]
                parts.append("Following section: \(Self.contentForAI(next.content, richText: next.richContent, truncate: true))")
            }
        }

        // Include page body and interstitial text so the AI has full narrative context
        if let note = note {
            let body = Self.contentForAI(note.body, richText: note.bodyRichText)
            if !body.isEmpty {
                parts.append("\nPage body text:\n\(body)")
            }
            // Interstitial text after specific sections
            for (key, value) in note.interstitialContent {
                let richText = note.interstitialRichContent[key]
                let cleaned = Self.contentForAI(value, richText: richText)
                if !cleaned.isEmpty {
                    if key == "end" {
                        parts.append("Text after all sections:\n\(cleaned)")
                    } else {
                        parts.append("Interstitial text (\(key)):\n\(cleaned)")
                    }
                }
            }
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Structured Page Context

    /// Build a structured JSON representation of the focused page for AI context.
    func buildStructuredPageContext(page: Note, sections: [Section]) -> String {
        let activeSections = sections.filter { $0.deletedAt == nil }

        var sectionDicts: [[String: Any]] = []
        for (index, section) in activeSections.prefix(50).enumerated() {
            let content = Self.contentForAI(section.content, richText: section.richContent)
            var dict: [String: Any] = [
                "id": section.id,
                "content": content,
                "type": section.sectionType == .fold ? "node" : "line",
                "content_type": section.contentType.rawValue,
                "indent": section.indentLevel,
                "intent": section.intent.rawValue,
                "order": index
            ]
            if let hId = section.handleId,
               let h = HandleManager.shared.getHandle(id: hId) {
                dict["handle"] = "@\(h.displayName)"
                dict["handle_id"] = hId
            }
            sectionDicts.append(dict)
        }

        // Build interstitial map — prefer markdown from rich text
        var interstitials: [String: String] = [:]
        for (key, value) in page.interstitialContent {
            let richText = page.interstitialRichContent[key]
            let content = Self.contentForAI(value, richText: richText)
            if !content.isEmpty {
                interstitials[key] = content
            }
        }

        let noteDict: [String: Any] = [
            "id": page.id,
            "title": page.displayTitle,
            "intent": page.intent.rawValue,
            "body": Self.contentForAI(page.body, richText: page.bodyRichText),
            "sections": sectionDicts,
            "interstitial_content": interstitials,
            "tags": page.tags + page.aiTags
        ]

        let wrapper: [String: Any] = ["focused_page": noteDict]

        if let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }

        return "Focused page (id: \(page.id)): \"\(page.displayTitle)\""
    }

    // MARK: - Utilities

    /// Strip non-readable content (base64 RTF, encoded data) from text.
    static func cleanContentForAI(_ text: String, truncate: Bool = true) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("e]") || trimmed.hasPrefix("ew0") || trimmed.hasPrefix("eyJ") ||
           trimmed.contains("{\\rtf") || trimmed.contains("\\fonttbl") {
            return ""
        }
        return truncate ? String(trimmed.prefix(300)) : trimmed
    }

    /// Get content for AI context, preferring markdown reconstructed from rich text.
    /// This lets the AI see existing formatting (headings, bold, italic) so it doesn't re-apply it.
    static func contentForAI(_ plainText: String, richText: String?, truncate: Bool = false) -> String {
        if let richText = richText,
           let markdown = RichTextHelper.toMarkdown(richText) {
            let cleaned = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return truncate ? String(cleaned.prefix(300)) : cleaned
            }
        }
        return cleanContentForAI(plainText, truncate: truncate)
    }
}
