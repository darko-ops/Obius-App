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
        newInsights.append(contentsOf: detectUpcomingEchoes(sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectConceptClusters(notes: notes, sectionsByNote: sectionsByNote))

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
            let sections = sectionsByNote[note.id] ?? []
            let pageTitle = note.displayTitle(sections: sections)

            // Scan note body
            let bodyText = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bodyText.isEmpty && taskPhrases.contains(where: { bodyText.lowercased().contains($0) }) {
                insights.append(Insight(
                    insightType: .suggestedTask,
                    title: "Possible task in '\(pageTitle)'",
                    body: String(bodyText.prefix(120)),
                    sourceNoteId: note.id
                ))
                if insights.count >= 5 { return insights }
            }

            // Scan sections
            for section in sections {
                guard section.intent != .task else { continue }
                guard section.contentType == .text || section.contentType == .checklist || section.contentType == .quote else { continue }

                let content = section.content.lowercased()
                if taskPhrases.contains(where: { content.contains($0) }) {
                    insights.append(Insight(
                        insightType: .suggestedTask,
                        title: "Possible task in '\(pageTitle)'",
                        body: String(section.content.prefix(120)),
                        sourceNoteId: note.id,
                        sourceSectionId: section.id
                    ))
                    if insights.count >= 5 { return insights }
                }
            }

            // Scan interstitial content
            for (_, text) in note.interstitialContent {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if taskPhrases.contains(where: { trimmed.lowercased().contains($0) }) {
                    insights.append(Insight(
                        insightType: .suggestedTask,
                        title: "Possible task in '\(pageTitle)'",
                        body: String(trimmed.prefix(120)),
                        sourceNoteId: note.id
                    ))
                    if insights.count >= 5 { return insights }
                }
            }
        }

        return insights
    }

    // MARK: - Open Questions

    private func detectOpenQuestions(notes: [Note], sectionsByNote: [String: [Section]]) async -> [Insight] {
        // Single question words that start a question sentence
        let questionStarters: Set<String> = [
            "who", "what", "when", "where", "why", "how",
            "which", "whose", "whom"
        ]

        // Multi-word question phrases
        let questionPhrases = [
            "should i", "should we", "could i", "could we",
            "can i", "can we", "would i", "would we",
            "do i", "do we", "do you", "does it", "does this",
            "is there", "is it", "is this", "are there", "are we",
            "will it", "will this", "was it", "was this",
            "have i", "have we", "has it", "has this",
            "am i", "aren't we", "isn't it", "isn't this",
            "wouldn't it", "couldn't we", "shouldn't we"
        ]

        var insights: [Insight] = []

        for note in notes {
            let sections = sectionsByNote[note.id] ?? []
            let pageTitle = note.displayTitle(sections: sections)

            // Helper to check a text block for questions
            func checkForQuestion(_ text: String, sectionId: String? = nil) {
                guard insights.count < 5 else { return }
                // Check each line/sentence for questions
                let lines = text.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    let lower = trimmed.lowercased()
                    let endsWithQuestion = trimmed.hasSuffix("?")

                    // Check if the first word is a question starter (only if 2+ words)
                    let words = lower.split(separator: " ")
                    let firstWord = words.first.map(String.init) ?? ""
                    let startsWithQuestionWord = words.count >= 2 && questionStarters.contains(firstWord)
                    let startsWithQuestionPhrase = questionPhrases.contains { lower.hasPrefix($0) }

                    if endsWithQuestion || startsWithQuestionWord || startsWithQuestionPhrase {
                        insights.append(Insight(
                            insightType: .openQuestion,
                            title: "Question in '\(pageTitle)'",
                            body: String(trimmed.prefix(120)),
                            sourceNoteId: note.id,
                            sourceSectionId: sectionId
                        ))
                        return // One per text block
                    }
                }
            }

            // Scan note body
            let bodyText = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bodyText.isEmpty {
                checkForQuestion(bodyText)
            }

            // Scan sections
            for section in sections {
                guard insights.count < 5 else { return insights }
                guard section.intent != .question else { continue }
                guard section.contentType == .text || section.contentType == .quote else { continue }
                let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { continue }
                checkForQuestion(content, sectionId: section.id)
            }

            // Scan interstitial content
            for (_, text) in note.interstitialContent {
                guard insights.count < 5 else { return insights }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                checkForQuestion(trimmed)
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
                title: "'\(pageTitle)' is stale",
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
                title: "'\(pageTitle)' has \(sections.count) nodes",
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
            var allText = note.body
            for section in sections where section.contentType == .text || section.contentType == .checklist || section.contentType == .quote || section.contentType == .code {
                allText += " " + section.content
            }
            for (_, text) in note.interstitialContent {
                allText += " " + text
            }

            let trimmed = allText.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip empty or very short notes — not enough to judge
            guard trimmed.count >= 10 else { continue }
            // Skip notes with media sections (images/audio are meaningful without text)
            let hasMedia = sections.contains { $0.contentType == .image || $0.contentType == .audio }
            if hasMedia { continue }

            if looksLikeNonsense(trimmed) {
                let pageTitle = note.displayTitle(sections: sections)
                let preview = String(trimmed.prefix(80))

                insights.append(Insight(
                    insightType: .nonsenseContent,
                    title: "'\(pageTitle)' may be noise",
                    body: "\"\(preview)\"",
                    sourceNoteId: note.id
                ))

                if insights.count >= 3 { return insights }
            }
        }

        return insights
    }

    // MARK: - Upcoming Echoes

    private func detectUpcomingEchoes(sectionsByNote: [String: [Section]]) -> [Insight] {
        let now = Date()
        let twentyFourHoursFromNow = now.addingTimeInterval(24 * 60 * 60)
        var insights: [Insight] = []

        for echo in EchoManager.shared.activeEchoes {
            guard let fireDate = echo.nextFireDateAsDate,
                  fireDate > now,
                  fireDate <= twentyFourHoursFromNow else { continue }

            let handleName = HandleManager.shared.getHandle(id: echo.handleId)?.displayName ?? "Unknown"

            // Find the note containing a section with this handleId
            var noteId: String?
            for (nId, sections) in sectionsByNote {
                if sections.contains(where: { $0.handleId == echo.handleId }) {
                    noteId = nId
                    break
                }
            }

            // Build relative time description
            let interval = fireDate.timeIntervalSince(now)
            let hours = Int(interval / 3600)
            let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            let timeDesc: String
            if hours > 0 {
                timeDesc = "Fires in \(hours)h \(minutes)m"
            } else {
                timeDesc = "Fires in \(minutes)m"
            }

            insights.append(Insight(
                insightType: .upcomingEcho,
                title: "Echo: @\(handleName) fires soon",
                body: timeDesc,
                sourceNoteId: noteId
            ))

            if insights.count >= 5 { return insights }
        }

        return insights
    }

    // MARK: - Concept Clusters

    private func detectConceptClusters(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        // Group notes by each tag (case-insensitive)
        var tagToNotes: [String: [Note]] = [:]
        for note in notes {
            for tag in note.tags {
                let key = tag.lowercased()
                tagToNotes[key, default: []].append(note)
            }
        }

        var insights: [Insight] = []

        // Sort by cluster size descending so we surface the biggest clusters first
        let sorted = tagToNotes.sorted { $0.value.count > $1.value.count }

        for (tag, clusterNotes) in sorted {
            guard clusterNotes.count >= 3 else { continue }

            // Skip clusters where all notes already share the same groupName
            let groupNames = Set(clusterNotes.compactMap { $0.groupName })
            if groupNames.count == 1 && clusterNotes.allSatisfy({ $0.groupName != nil }) {
                continue
            }

            // Build body: note titles with node counts
            let bodyParts = clusterNotes.prefix(5).map { note -> String in
                let nodes = sectionsByNote[note.id] ?? []
                let title = note.displayTitle(sections: nodes)
                return "\(title) (\(nodes.count))"
            }
            let body = bodyParts.joined(separator: ", ")

            insights.append(Insight(
                insightType: .conceptCluster,
                title: "\(clusterNotes.count) notes share #\(tag)",
                body: body,
                sourceSectionId: tag
            ))

            if insights.count >= 5 { return insights }
        }

        return insights
    }

    /// Heuristic check for nonsense/gibberish text.
    private func looksLikeNonsense(_ text: String) -> Bool {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        // Single repeated character strings like "aaaa" or "asdf"
        if words.count <= 2 {
            let cleaned = text.lowercased().filter { $0.isLetter }
            if cleaned.count >= 5 {
                let unique = Set(cleaned)
                // Very few unique characters relative to length = repetitive gibberish
                if unique.count <= 3 { return true }
            }
        }

        // Check for keyboard mash: high ratio of consonant clusters
        let letters = text.lowercased().filter { $0.isLetter }
        guard letters.count >= 8 else { return false }

        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        let vowelCount = letters.filter { vowels.contains($0) }.count
        let vowelRatio = Double(vowelCount) / Double(letters.count)

        // Normal English has ~38-40% vowels. Below 15% is likely gibberish.
        if vowelRatio < 0.15 { return true }

        // Check for excessive repeated characters (e.g. "hhhhhh", "kkkkk")
        var maxRepeat = 1
        var currentRepeat = 1
        let chars = Array(letters)
        for i in 1..<chars.count {
            if chars[i] == chars[i - 1] {
                currentRepeat += 1
                maxRepeat = max(maxRepeat, currentRepeat)
            } else {
                currentRepeat = 1
            }
        }
        if maxRepeat >= 5 { return true }

        // Check for no real words: if text has 3+ "words" but average word length is extreme
        if words.count >= 3 {
            let avgLen = Double(words.map { $0.count }.reduce(0, +)) / Double(words.count)
            // Very long "words" with no spaces = likely keyboard mash
            if avgLen > 20 { return true }
        }

        return false
    }
}
