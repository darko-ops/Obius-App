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

        // Skip scan entirely if notes haven't loaded yet — avoids wiping
        // existing insights via garbage collection on an empty list.
        guard !notes.isEmpty else { return }

        let validNoteIds = Set(notes.map(\.id))

        // Garbage-collect surfaced insights whose source note was deleted
        try? await insightRepository.removeOrphanedInsights(validNoteIds: validNoteIds)

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
        newInsights.append(contentsOf: detectSuggestedTasks(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectOpenQuestions(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectStaleContent(notes: notes))
        newInsights.append(contentsOf: detectGrowingNotes(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectLonelyHandles(sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectNonsenseContent(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectUpcomingEchoes(sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectConceptClusters(notes: notes, sectionsByNote: sectionsByNote))

        // Batch dedup against all existing insights (surfaced, tracked, dismissed)
        let existingKeys = (try? await insightRepository.existingInsightKeys()) ?? []
        let deduped = newInsights.filter { !existingKeys.contains($0.dedupKey) }

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

    private func detectSuggestedTasks(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        // Explicit markers — match anywhere in text (high confidence)
        let explicitMarkers = [
            "todo:", "todo ", "to-do", "fixme", "action item",
            "[ ]", "action:", "deadline"
        ]

        // Phrases that match at line start or after a sentence boundary
        let lineStartPhrases = [
            "need to", "have to", "follow up", "don't forget",
            "remind me", "make sure", "by tomorrow"
        ]

        // Phrases that only match after subject pronouns (I/we/you)
        let subjectPhrases = ["should ", "must ", "gotta ", "ought to "]
        let subjects = ["i ", "we ", "you "]

        var insights: [Insight] = []

        for note in notes {
            // Skip notes already tagged as task intent
            guard note.intent != .task else { continue }

            let sections = sectionsByNote[note.id] ?? []
            let pageTitle = note.displayTitle(sections: sections)

            var matchCount = 0
            var firstMatch: (text: String, sectionId: String?)?

            func checkText(_ text: String, sectionId: String? = nil) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let lower = trimmed.lowercased()

                // Check explicit markers
                if explicitMarkers.contains(where: { lower.contains($0) }) {
                    matchCount += 1
                    if firstMatch == nil {
                        firstMatch = (String(trimmed.prefix(120)), sectionId)
                    }
                    return
                }

                // Check line-by-line for contextual phrases
                for line in lower.components(separatedBy: .newlines) {
                    let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !l.isEmpty else { continue }

                    // Line-start phrases
                    let lineStartMatch = lineStartPhrases.contains(where: { l.hasPrefix($0) })

                    // After sentence boundary (". need to", "! follow up")
                    let boundaryMatch = lineStartPhrases.contains(where: {
                        l.contains(". \($0)") || l.contains("! \($0)")
                    })

                    // Subject + phrase ("i should", "we must")
                    let subjectMatch = subjectPhrases.contains(where: { phrase in
                        subjects.contains(where: { l.hasPrefix($0 + phrase) }) ||
                        subjects.contains(where: { subject in
                            l.contains(". \(subject)\(phrase)") ||
                            l.contains("! \(subject)\(phrase)")
                        })
                    })

                    if lineStartMatch || boundaryMatch || subjectMatch {
                        matchCount += 1
                        if firstMatch == nil {
                            // Recover original-case line for preview
                            let origLines = trimmed.components(separatedBy: .newlines)
                            let origLine = origLines.first(where: {
                                $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == l
                            }) ?? trimmed
                            firstMatch = (
                                String(origLine.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
                                sectionId
                            )
                        }
                        return // One match per text block
                    }
                }
            }

            // Scan note body
            checkText(note.body)

            // Scan sections
            for section in sections {
                guard section.intent != .task else { continue }
                guard section.contentType == .text || section.contentType == .checklist || section.contentType == .quote else { continue }
                checkText(section.content, sectionId: section.id)
            }

            // Scan interstitial content
            for (_, text) in note.interstitialContent {
                checkText(text)
            }

            // Consolidate: 1 insight per note
            guard let first = firstMatch else { continue }

            insights.append(Insight(
                insightType: .suggestedTask,
                title: matchCount == 1
                    ? "Possible task in '\(pageTitle)'"
                    : "\(matchCount) possible tasks in '\(pageTitle)'",
                body: matchCount == 1
                    ? first.text
                    : "\(first.text)\n+\(matchCount - 1) more",
                sourceNoteId: note.id,
                sourceSectionId: first.sectionId
            ))
        }

        return insights
    }

    // MARK: - Open Questions

    private func detectOpenQuestions(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        let questionStarters: Set<String> = [
            "who", "what", "when", "where", "why", "how",
            "which", "whose", "whom"
        ]

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
            let noteTitleLower = (note.title ?? "").lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var matchCount = 0
            var firstMatch: (text: String, sectionId: String?)?

            func checkForQuestion(_ text: String, sectionId: String? = nil) {
                let lines = text.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    let lower = trimmed.lowercased()

                    // Skip lines that duplicate the note title (the note IS the question)
                    if !noteTitleLower.isEmpty && lower == noteTitleLower { continue }

                    let endsWithQuestion = trimmed.hasSuffix("?")
                    let words = lower.split(separator: " ")

                    // Question ending with "?" — require 4+ words to skip fragments like "Why?" "Really?"
                    if endsWithQuestion && words.count >= 4 {
                        matchCount += 1
                        if firstMatch == nil {
                            firstMatch = (String(trimmed.prefix(120)), sectionId)
                        }
                        return // One match per text block
                    }

                    // Question starters — require 3+ words
                    if words.count >= 3,
                       let first = words.first,
                       questionStarters.contains(String(first)) {
                        matchCount += 1
                        if firstMatch == nil {
                            firstMatch = (String(trimmed.prefix(120)), sectionId)
                        }
                        return
                    }

                    // Multi-word question phrases at line start
                    if questionPhrases.contains(where: { lower.hasPrefix($0) }) {
                        matchCount += 1
                        if firstMatch == nil {
                            firstMatch = (String(trimmed.prefix(120)), sectionId)
                        }
                        return
                    }
                }
            }

            // Scan note body
            let bodyText = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bodyText.isEmpty {
                checkForQuestion(bodyText)
            }

            // Scan sections — skip .question intent and .quote contentType (attributed quotes aren't open questions)
            for section in sections {
                guard section.intent != .question else { continue }
                guard section.contentType == .text else { continue }
                let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { continue }
                checkForQuestion(content, sectionId: section.id)
            }

            // Scan interstitial content
            for (_, text) in note.interstitialContent {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                checkForQuestion(trimmed)
            }

            // Consolidate: 1 insight per note
            guard let first = firstMatch else { continue }

            insights.append(Insight(
                insightType: .openQuestion,
                title: matchCount == 1
                    ? "Question in '\(pageTitle)'"
                    : "\(matchCount) questions in '\(pageTitle)'",
                body: matchCount == 1
                    ? first.text
                    : "\(first.text)\n+\(matchCount - 1) more",
                sourceNoteId: note.id,
                sourceSectionId: first.sectionId
            ))
        }

        return insights
    }

    // MARK: - Stale Content

    private func detectStaleContent(notes: [Note]) -> [Insight] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let fourteenDaysMs: Int64 = 14 * 86_400_000
        var insights: [Insight] = []

        // Sort by staleness descending — surface the dustiest notes first
        let candidates = notes
            .filter { note in
                // Skip pinned notes — user intentionally keeps them visible
                guard !note.isPinned else { return false }
                guard note.updatedAt < now - fourteenDaysMs else { return false }

                let hasTitle = note.title != nil
                    && !note.title!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasBody = note.body.trimmingCharacters(in: .whitespacesAndNewlines).count > 20

                return hasTitle || hasBody
            }
            .sorted { $0.updatedAt < $1.updatedAt }

        for note in candidates {
            let daysSince = Int((now - note.updatedAt) / 86_400_000)
            let pageTitle = note.displayTitle

            let staleness: String
            if daysSince >= 90 {
                staleness = "Last edited \(daysSince / 30) months ago"
            } else if daysSince >= 30 {
                staleness = "Last edited about a month ago"
            } else {
                staleness = "Last edited \(daysSince) days ago"
            }

            insights.append(Insight(
                insightType: .staleContent,
                title: "'\(pageTitle)' is gathering dust",
                body: staleness,
                sourceNoteId: note.id
            ))

            if insights.count >= 5 { return insights }
        }

        return insights
    }

    // MARK: - Growing Notes

    private func detectGrowingNotes(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        let sevenDaysAgo = Int64(Date().timeIntervalSince1970 * 1000) - (7 * 86_400_000)
        var insights: [Insight] = []

        for note in notes {
            guard let sections = sectionsByNote[note.id] else { continue }
            guard sections.count >= 10 else { continue }

            let pageTitle = note.displayTitle(sections: sections)
            let recentCount = sections.filter { $0.createdAt > sevenDaysAgo }.count

            let body: String
            if recentCount >= 5 {
                body = "\(recentCount) nodes added this week — consider splitting"
            } else {
                body = "Consider splitting or organizing this note"
            }

            insights.append(Insight(
                insightType: .growingNote,
                title: "'\(pageTitle)' has \(sections.count) nodes",
                body: body,
                sourceNoteId: note.id
            ))

            if insights.count >= 3 { return insights }
        }

        return insights
    }

    // MARK: - Lonely Handles

    private func detectLonelyHandles(sectionsByNote: [String: [Section]]) -> [Insight] {
        let handles = handleRepository.handles
        var insights: [Insight] = []

        // Skip handles that have echoes — echoes are designed to be single-reference
        let echoHandleIds = Set(EchoManager.shared.activeEchoes.map { $0.handleId })

        // Count how many sections reference each handle, and track where it first appears
        var handleRefCount: [String: Int] = [:]
        var handleFirstLocation: [String: (noteId: String, sectionId: String)] = [:]
        for (noteId, sections) in sectionsByNote {
            for section in sections {
                if let handleId = section.handleId {
                    handleRefCount[handleId, default: 0] += 1
                    if handleFirstLocation[handleId] == nil {
                        handleFirstLocation[handleId] = (noteId, section.id)
                    }
                }
            }
        }

        for handle in handles {
            // Skip echo handles
            guard !echoHandleIds.contains(handle.id) else { continue }

            let count = handleRefCount[handle.id] ?? 0
            // Only flag handles that appear exactly once (not zero — zero means unreferenced, not lonely)
            guard count == 1 else { continue }

            let location = handleFirstLocation[handle.id]

            insights.append(Insight(
                insightType: .lonelyHandle,
                title: "@\(handle.displayName) only appears once",
                body: "Consider linking it elsewhere",
                sourceNoteId: location?.noteId,
                sourceSectionId: handle.id  // Store handle ID for stable dedup
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
            var sectionId: String?
            for (nId, sections) in sectionsByNote {
                if let match = sections.first(where: { $0.handleId == echo.handleId }) {
                    noteId = nId
                    sectionId = match.id
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
                sourceNoteId: noteId,
                sourceSectionId: sectionId
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
