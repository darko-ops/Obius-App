import Foundation
import GRDB

@MainActor
final class InsightEngine {
    private let noteRepository: NoteRepository
    private let sectionRepository: SectionRepository
    private let handleRepository: HandleRepository
    private let insightRepository: InsightRepository
    private let database: DatabaseManager

    init(
        noteRepository: NoteRepository,
        sectionRepository: SectionRepository,
        handleRepository: HandleRepository,
        insightRepository: InsightRepository,
        database: DatabaseManager
    ) {
        self.noteRepository = noteRepository
        self.sectionRepository = sectionRepository
        self.handleRepository = handleRepository
        self.insightRepository = insightRepository
        self.database = database
    }

    /// Runs all detectors, deduplicates, and bulk-inserts new insights.
    func scan() async {
        let notes = noteRepository.notes.filter { !$0.isDeleted }

        // Fetch all sections grouped by noteId
        var sectionsByNote: [String: [Section]] = [:]
        for note in notes {
            do {
                let sections = try await sectionRepository.getSections(noteId: note.id)
                sectionsByNote[note.id] = sections
            } catch {
                print("[InsightEngine] Failed to fetch sections for note \(note.id): \(error)")
            }
        }

        var newInsights: [Insight] = []

        // Run each detector
        newInsights.append(contentsOf: await detectSuggestedTasks(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: await detectOpenQuestions(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectStaleContent(notes: notes))
        newInsights.append(contentsOf: detectGrowingNotes(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: await detectLonelyHandles(sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectNonsenseContent(notes: notes, sectionsByNote: sectionsByNote))

        // Deduplicate against existing non-dismissed insights
        var deduped: [Insight] = []
        for insight in newInsights {
            do {
                let exists = try await insightRepository.insightExists(
                    type: insight.insightType,
                    sourceNoteId: insight.sourceNoteId,
                    sourceSectionId: insight.sourceSectionId
                )
                if !exists {
                    deduped.append(insight)
                }
            } catch {
                print("[InsightEngine] Dedup check failed: \(error)")
            }
        }

        // Bulk insert
        if !deduped.isEmpty {
            do {
                try await insightRepository.createInsights(deduped)
            } catch {
                print("[InsightEngine] Bulk insert failed: \(error)")
            }
        }

        // Purge old dismissed insights
        try? await insightRepository.purgeDismissed()
    }

    // MARK: - Suggested Tasks

    private func detectSuggestedTasks(notes: [Note], sectionsByNote: [String: [Section]]) async -> [Insight] {
        let taskPhrases = [
            "need to", "should", "have to", "must", "todo", "to-do",
            "follow up", "deadline", "by tomorrow", "action item",
            "remind me", "don't forget", "make sure"
        ]

        var insights: [Insight] = []

        for note in notes {
            guard let sections = sectionsByNote[note.id] else { continue }

            for section in sections {
                // Skip sections already classified as tasks
                guard section.intent != .task else { continue }
                // Only scan text-based content
                guard section.contentType == .text || section.contentType == .checklist || section.contentType == .quote else { continue }

                let content = section.content.lowercased()
                let matched = taskPhrases.first { content.contains($0) }

                if matched != nil {
                    let preview = String(section.content.prefix(120))
                    let pageTitle = note.displayTitle(sections: sections)

                    insights.append(Insight(
                        insightType: .suggestedTask,
                        title: "Possible task in \(pageTitle)",
                        body: preview,
                        sourceNoteId: note.id,
                        sourceSectionId: section.id
                    ))

                    if insights.count >= 5 { return insights }
                }
            }
        }

        return insights
    }

    // MARK: - Open Questions

    private func detectOpenQuestions(notes: [Note], sectionsByNote: [String: [Section]]) async -> [Insight] {
        let questionPrefixes = [
            "how do", "what if", "why does", "should i", "should we",
            "can we", "is there", "what is", "where do", "when should",
            "who should", "which", "could we", "how can", "what are",
            "why is", "who is", "where is", "when is", "is it"
        ]

        var insights: [Insight] = []

        for note in notes {
            guard let sections = sectionsByNote[note.id] else { continue }

            for section in sections {
                // Skip sections already classified as questions
                guard section.intent != .question else { continue }
                guard section.contentType == .text || section.contentType == .quote || section.contentType == .checklist else { continue }

                let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { continue }

                // Scan each line individually so embedded questions are caught
                let lines = content.components(separatedBy: .newlines)
                var matchedLine: String?

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    let lower = trimmed.lowercased()

                    let endsWithQuestion = trimmed.hasSuffix("?")
                    let startsWithQuestion = questionPrefixes.contains { lower.hasPrefix($0) }
                    let containsQuestion = trimmed.contains("?")

                    if endsWithQuestion || startsWithQuestion || containsQuestion {
                        matchedLine = trimmed
                        break
                    }
                }

                if let matched = matchedLine {
                    let preview = String(matched.prefix(120))
                    let pageTitle = note.displayTitle(sections: sections)

                    insights.append(Insight(
                        insightType: .openQuestion,
                        title: "Question in \(pageTitle)",
                        body: preview,
                        sourceNoteId: note.id,
                        sourceSectionId: section.id
                    ))

                    if insights.count >= 5 { return insights }
                }
            }
        }

        return insights
    }

    // MARK: - Stale Content

    private func detectStaleContent(notes: [Note]) -> [Insight] {
        let fourteenDaysAgo = Int64(Date().timeIntervalSince1970 * 1000) - (14 * 86_400_000)
        var insights: [Insight] = []

        for note in notes {
            guard note.updatedAt < fourteenDaysAgo else { continue }

            // Only flag notes with meaningful content
            let hasTitle = note.title != nil && !note.title!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasBody = note.body.trimmingCharacters(in: .whitespacesAndNewlines).count > 20

            guard hasTitle || hasBody else { continue }

            let daysSince = Int((Int64(Date().timeIntervalSince1970 * 1000) - note.updatedAt) / 86_400_000)
            let pageTitle = note.displayTitle

            insights.append(Insight(
                insightType: .staleContent,
                title: "\(pageTitle) is stale",
                body: "Last edited \(daysSince) days ago",
                sourceNoteId: note.id
            ))

            if insights.count >= 3 { return insights }
        }

        return insights
    }

    // MARK: - Growing Notes

    private func detectGrowingNotes(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        var insights: [Insight] = []

        for note in notes {
            guard let sections = sectionsByNote[note.id] else { continue }
            guard sections.count >= 10 else { continue }

            let pageTitle = note.displayTitle(sections: sections)

            insights.append(Insight(
                insightType: .growingNote,
                title: "\(pageTitle) has \(sections.count) sections",
                body: "Consider splitting or organizing this note",
                sourceNoteId: note.id
            ))

            if insights.count >= 2 { return insights }
        }

        return insights
    }

    // MARK: - Lonely Handles

    private func detectLonelyHandles(sectionsByNote: [String: [Section]]) async -> [Insight] {
        let handles = handleRepository.handles
        var insights: [Insight] = []

        // Skip handles that have echoes — echoes are designed to be single-reference
        let echoHandleIds = Set(EchoManager.shared.activeEchoes.map { $0.handleId })

        // Count how many sections reference each handle
        var handleRefCount: [String: Int] = [:]
        for (_, sections) in sectionsByNote {
            for section in sections {
                if let handleId = section.handleId {
                    handleRefCount[handleId, default: 0] += 1
                }
            }
        }

        for handle in handles {
            // Skip echo handles
            guard !echoHandleIds.contains(handle.id) else { continue }

            let count = handleRefCount[handle.id] ?? 0
            // Only flag handles that appear exactly once (not zero — zero means unreferenced, not lonely)
            guard count == 1 else { continue }

            insights.append(Insight(
                insightType: .lonelyHandle,
                title: "@\(handle.displayName) only appears once",
                body: "Consider linking it elsewhere",
                sourceNoteId: nil
            ))

            if insights.count >= 3 { return insights }
        }

        return insights
    }

    // MARK: - Nonsense Content

    private func detectNonsenseContent(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        var insights: [Insight] = []

        for note in notes {
            let sections = sectionsByNote[note.id] ?? []

            // Gather all text content from the note
            let allText = sections
                .filter { $0.contentType == .text || $0.contentType == .checklist || $0.contentType == .quote }
                .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")

            let stripped = allText.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty notes (staleContent handles those) and notes with media sections only
            let hasMediaOnly = sections.allSatisfy { $0.contentType == .image || $0.contentType == .audio }
            if hasMediaOnly && !sections.isEmpty { continue }

            // Skip notes with no text sections at all
            guard !stripped.isEmpty else { continue }

            // Run heuristics
            let score = nonsenseScore(for: stripped)

            if score >= 3 {
                let pageTitle = note.displayTitle(sections: sections)
                let preview = String(stripped.prefix(80))

                insights.append(Insight(
                    insightType: .nonsenseContent,
                    title: "\(pageTitle) looks like nonsense",
                    body: "\"\(preview)\"",
                    sourceNoteId: note.id
                ))

                if insights.count >= 3 { return insights }
            }
        }

        return insights
    }

    /// Returns a score 0–5 indicating how likely the content is nonsense.
    /// 3+ = flag it.
    private func nonsenseScore(for text: String) -> Int {
        var score = 0

        // 1. Very short content (< 8 meaningful chars)
        let alphanumOnly = text.filter { $0.isLetter || $0.isNumber }
        if alphanumOnly.count < 8 && text.count < 15 {
            score += 1
        }

        // 2. Low word-quality ratio: tokens that look like real words
        //    (3+ chars, contains a vowel)
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "A", "E", "I", "O", "U"]
        let tokens = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if !tokens.isEmpty {
            let wordLike = tokens.filter { token in
                token.count >= 3 && token.contains(where: { vowels.contains($0) })
            }
            let ratio = Double(wordLike.count) / Double(tokens.count)
            if ratio < 0.3 {
                score += 2
            } else if ratio < 0.5 {
                score += 1
            }
        }

        // 3. Keyboard mash patterns
        let lower = text.lowercased()
        let mashPatterns = ["asdf", "qwer", "zxcv", "hjkl", "jkl;", "fghj", "sdfg", "dfgh", "bnm,"]
        if mashPatterns.contains(where: { lower.contains($0) }) {
            score += 2
        }

        // 4. Highly repetitive characters (same char 4+ times in a row)
        let repetitivePattern = try? NSRegularExpression(pattern: "(.)\\1{3,}")
        let matches = repetitivePattern?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
        if matches > 0 {
            score += 1
        }

        // 5. Very high non-letter ratio (lots of symbols/numbers, few letters)
        if !text.isEmpty {
            let letterCount = text.filter { $0.isLetter }.count
            let letterRatio = Double(letterCount) / Double(text.count)
            if letterRatio < 0.4 && text.count > 3 {
                score += 1
            }
        }

        return score
    }
}
