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
        print("[InsightEngine] scan() started — \(notes.count) notes")

        // Skip scan entirely if notes haven't loaded yet — avoids wiping
        // existing insights via garbage collection on an empty list.
        guard !notes.isEmpty else {
            print("[InsightEngine] scan() aborted — no notes loaded yet")
            return
        }

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
        newInsights.append(contentsOf: detectCleanup(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectReminders(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectSafetyIssues(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectUpcomingEchoes(sectionsByNote: sectionsByNote))
        // Phase 2 stubs:
        // newInsights.append(contentsOf: await detectDrift(...))
        // newInsights.append(contentsOf: await generateWeeklyReport(...))
        // newInsights.append(contentsOf: await assessProjectHealth(...))

        // Batch dedup against all existing insights (surfaced, tracked, dismissed)
        let existingKeys = (try? await insightRepository.existingInsightKeys()) ?? []
        let deduped = newInsights.filter { !existingKeys.contains($0.dedupKey) }

        // Bulk insert
        if !deduped.isEmpty {
            do {
                try await insightRepository.createInsights(deduped)
                print("[InsightEngine] Inserted \(deduped.count) new insight(s): \(deduped.map { "\($0.insightType.rawValue)|\($0.sourceSectionId ?? "")|\($0.title)" })")
            } catch {
                print("[InsightEngine] Bulk insert failed: \(error)")
            }
        } else {
            print("[InsightEngine] No new insights to insert (all \(newInsights.count) deduped)")
        }

        // Purge old dismissed insights
        try? await insightRepository.purgeDismissed()
    }

    // MARK: - Cleanup Detector

    /// Detects stale notes, dormant loops, lonely loops, and nonsense content.
    private func detectCleanup(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        var insights: [Insight] = []

        // -- Stale notes --
        insights.append(contentsOf: detectStaleNotes(notes: notes, sectionsByNote: sectionsByNote))

        // -- Dormant loops --
        insights.append(contentsOf: detectDormantLoops(sectionsByNote: sectionsByNote))

        // -- Lonely loops --
        insights.append(contentsOf: detectLonelyLoops(sectionsByNote: sectionsByNote))

        // -- Nonsense content --
        insights.append(contentsOf: detectNonsense(notes: notes))

        return insights
    }

    private func detectStaleNotes(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let fourteenDaysMs: Int64 = 14 * 86_400_000
        var insights: [Insight] = []

        let candidates = notes
            .filter { note in
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
            let sections = sectionsByNote[note.id] ?? []
            let pageTitle = note.displayTitle(sections: sections)

            let staleness: String
            if daysSince >= 90 {
                staleness = "Last edited \(daysSince / 30) months ago"
            } else if daysSince >= 30 {
                staleness = "Last edited about a month ago"
            } else {
                staleness = "Last edited \(daysSince) days ago"
            }

            insights.append(Insight(
                insightType: .cleanup,
                title: "'\(pageTitle)' is gathering dust",
                body: staleness,
                sourceNoteId: note.id,
                sourceSectionId: "stale"
            ))

            if insights.count >= 5 { return insights }
        }

        return insights
    }

    private func detectDormantLoops(sectionsByNote: [String: [Section]]) -> [Insight] {
        let handles = handleRepository.handles
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let fourteenDaysMs: Int64 = 14 * 86_400_000
        var insights: [Insight] = []

        var handleFirstNoteId: [String: String] = [:]
        var handleHasSections: Set<String> = []
        for (noteId, sections) in sectionsByNote {
            for section in sections {
                if let handleId = section.handleId {
                    handleHasSections.insert(handleId)
                    if handleFirstNoteId[handleId] == nil {
                        handleFirstNoteId[handleId] = noteId
                    }
                }
            }
        }

        for handle in handles {
            guard handleHasSections.contains(handle.id) else { continue }
            guard handle.updatedAt < now - fourteenDaysMs else { continue }

            let daysSince = Int((now - handle.updatedAt) / 86_400_000)
            insights.append(Insight(
                insightType: .cleanup,
                title: "@\(handle.displayName) hasn't been updated in \(daysSince) days",
                body: "Consider refreshing or archiving this loop",
                sourceNoteId: handleFirstNoteId[handle.id],
                sourceSectionId: "dormant_loop"
            ))

            if insights.count >= 5 { return insights }
        }

        return insights
    }

    private func detectLonelyLoops(sectionsByNote: [String: [Section]]) -> [Insight] {
        let handles = handleRepository.handles
        var insights: [Insight] = []

        let echoHandleIds = Set(EchoManager.shared.activeEchoes.map { $0.handleId })

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
            guard !echoHandleIds.contains(handle.id) else { continue }
            let count = handleRefCount[handle.id] ?? 0
            guard count == 1 else { continue }

            let location = handleFirstLocation[handle.id]

            insights.append(Insight(
                insightType: .cleanup,
                title: "@\(handle.displayName) only appears once",
                body: "Consider linking it elsewhere",
                sourceNoteId: location?.noteId,
                sourceSectionId: "lonely_loop"
            ))

            if insights.count >= 3 { return insights }
        }

        return insights
    }

    private func detectNonsense(notes: [Note]) -> [Insight] {
        var insights: [Insight] = []

        for note in notes {
            let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip notes with a real title but empty body — those are just titled stubs
            if let title = note.title,
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               body.isEmpty {
                continue
            }

            // Skip empty notes entirely
            guard !body.isEmpty else { continue }

            // Strip whitespace and special characters for meaningful char count
            let meaningful = body.unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0)
            }
            let meaningfulCount = meaningful.count

            // Flag if body < 10 meaningful chars
            let tooShort = meaningfulCount < 10

            // Flag if >80% non-alphabetic characters
            let alphabetic = body.unicodeScalars.filter {
                CharacterSet.letters.contains($0)
            }
            let tooMuchNoise = !body.isEmpty && Double(alphabetic.count) / Double(body.count) < 0.2

            guard tooShort || tooMuchNoise else { continue }

            let pageTitle = note.displayTitle

            insights.append(Insight(
                insightType: .cleanup,
                title: "'\(pageTitle)' may be nonsense",
                body: tooShort
                    ? "Only \(meaningfulCount) meaningful character(s)"
                    : "Mostly non-text content",
                sourceNoteId: note.id,
                sourceSectionId: "nonsense"
            ))

            if insights.count >= 3 { return insights }
        }

        return insights
    }

    // MARK: - Reminders Detector

    /// Detects tasks and open questions.
    private func detectReminders(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        var insights: [Insight] = []
        insights.append(contentsOf: detectSuggestedTasks(notes: notes, sectionsByNote: sectionsByNote))
        insights.append(contentsOf: detectOpenQuestions(notes: notes, sectionsByNote: sectionsByNote))
        return insights
    }

    private func detectSuggestedTasks(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        let explicitMarkers = [
            "todo:", "todo ", "to-do", "fixme", "action item",
            "[ ]", "action:", "deadline"
        ]

        let lineStartPhrases = [
            "need to", "have to", "follow up", "don't forget",
            "remind me", "make sure", "by tomorrow"
        ]

        let subjectPhrases = ["should ", "must ", "gotta ", "ought to "]
        let subjects = ["i ", "we ", "you "]

        var insights: [Insight] = []

        for note in notes {
            guard note.intent != .task else { continue }

            let sections = sectionsByNote[note.id] ?? []
            let pageTitle = note.displayTitle(sections: sections)

            var matchCount = 0
            var firstMatch: (text: String, sectionId: String?)?

            func checkText(_ text: String, sectionId: String? = nil) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let lower = trimmed.lowercased()

                if explicitMarkers.contains(where: { lower.contains($0) }) {
                    matchCount += 1
                    if firstMatch == nil {
                        firstMatch = (String(trimmed.prefix(120)), sectionId)
                    }
                    return
                }

                for line in lower.components(separatedBy: .newlines) {
                    let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !l.isEmpty else { continue }

                    let lineStartMatch = lineStartPhrases.contains(where: { l.hasPrefix($0) })
                    let boundaryMatch = lineStartPhrases.contains(where: {
                        l.contains(". \($0)") || l.contains("! \($0)")
                    })
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
                            let origLines = trimmed.components(separatedBy: .newlines)
                            let origLine = origLines.first(where: {
                                $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == l
                            }) ?? trimmed
                            firstMatch = (
                                String(origLine.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
                                sectionId
                            )
                        }
                        return
                    }
                }
            }

            checkText(note.body)
            for section in sections {
                guard section.intent != .task else { continue }
                guard section.contentType == .text || section.contentType == .checklist || section.contentType == .quote else { continue }
                checkText(section.content, sectionId: section.id)
            }
            for (_, text) in note.interstitialContent {
                checkText(text)
            }

            guard let first = firstMatch else { continue }

            insights.append(Insight(
                insightType: .reminder,
                title: matchCount == 1
                    ? "Possible task in '\(pageTitle)'"
                    : "\(matchCount) possible tasks in '\(pageTitle)'",
                body: matchCount == 1
                    ? first.text
                    : "\(first.text)\n+\(matchCount - 1) more",
                sourceNoteId: note.id,
                sourceSectionId: "task"
            ))
        }

        return insights
    }

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

                    if !noteTitleLower.isEmpty && lower == noteTitleLower { continue }

                    let endsWithQuestion = trimmed.hasSuffix("?")
                    let words = lower.split(separator: " ")

                    if endsWithQuestion && words.count >= 4 {
                        matchCount += 1
                        if firstMatch == nil {
                            firstMatch = (String(trimmed.prefix(120)), sectionId)
                        }
                        return
                    }

                    if words.count >= 3,
                       let first = words.first,
                       questionStarters.contains(String(first)) {
                        matchCount += 1
                        if firstMatch == nil {
                            firstMatch = (String(trimmed.prefix(120)), sectionId)
                        }
                        return
                    }

                    if questionPhrases.contains(where: { lower.hasPrefix($0) }) {
                        matchCount += 1
                        if firstMatch == nil {
                            firstMatch = (String(trimmed.prefix(120)), sectionId)
                        }
                        return
                    }
                }
            }

            let bodyText = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bodyText.isEmpty {
                checkForQuestion(bodyText)
            }

            for section in sections {
                guard section.intent != .question else { continue }
                guard section.contentType == .text else { continue }
                let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { continue }
                checkForQuestion(content, sectionId: section.id)
            }

            for (_, text) in note.interstitialContent {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                checkForQuestion(trimmed)
            }

            guard let first = firstMatch else { continue }

            insights.append(Insight(
                insightType: .reminder,
                title: matchCount == 1
                    ? "Question in '\(pageTitle)'"
                    : "\(matchCount) questions in '\(pageTitle)'",
                body: matchCount == 1
                    ? first.text
                    : "\(first.text)\n+\(matchCount - 1) more",
                sourceNoteId: note.id,
                sourceSectionId: "question"
            ))
        }

        return insights
    }

    // MARK: - Safety Detector

    /// Detects API keys, passwords, SSNs, and credit card numbers.
    private func detectSafetyIssues(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        let apiKeyPatterns = [
            try! NSRegularExpression(pattern: #"sk-[a-zA-Z0-9]{20,}"#, options: []),
            try! NSRegularExpression(pattern: #"pk_[a-zA-Z0-9]{20,}"#, options: []),
            try! NSRegularExpression(pattern: #"AKIA[0-9A-Z]{16}"#, options: []),
        ]
        let passwordPattern = try! NSRegularExpression(
            pattern: #"(?:password|pwd|secret|token)\s*[:=]\s*\S+"#,
            options: [.caseInsensitive]
        )
        let ssnPattern = try! NSRegularExpression(
            pattern: #"\b\d{3}-\d{2}-\d{4}\b"#,
            options: []
        )
        let creditCardPattern = try! NSRegularExpression(
            pattern: #"\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b"#,
            options: []
        )

        var insights: [Insight] = []
        var seenNoteSubtype: Set<String> = []

        for note in notes {
            let sections = sectionsByNote[note.id] ?? []
            let pageTitle = note.displayTitle(sections: sections)

            // Collect all text from note body + sections
            var allText = note.body
            for section in sections {
                allText += "\n" + section.content
            }

            let range = NSRange(allText.startIndex..<allText.endIndex, in: allText)

            // API keys
            let hasAPIKey = apiKeyPatterns.contains { pattern in
                pattern.firstMatch(in: allText, range: range) != nil
            }
            if hasAPIKey {
                let key = "\(note.id)|api_key"
                if seenNoteSubtype.insert(key).inserted {
                    insights.append(Insight(
                        insightType: .safety,
                        title: "Possible API key in '\(pageTitle)'",
                        body: "Found what looks like a secret key — consider removing it",
                        sourceNoteId: note.id,
                        sourceSectionId: "api_key"
                    ))
                }
            }

            // Passwords
            if passwordPattern.firstMatch(in: allText, range: range) != nil {
                let key = "\(note.id)|password"
                if seenNoteSubtype.insert(key).inserted {
                    insights.append(Insight(
                        insightType: .safety,
                        title: "Possible password in '\(pageTitle)'",
                        body: "Found text that looks like a stored credential",
                        sourceNoteId: note.id,
                        sourceSectionId: "password"
                    ))
                }
            }

            // SSN
            if ssnPattern.firstMatch(in: allText, range: range) != nil {
                let key = "\(note.id)|personal_data"
                if seenNoteSubtype.insert(key).inserted {
                    insights.append(Insight(
                        insightType: .safety,
                        title: "Possible SSN in '\(pageTitle)'",
                        body: "Found a pattern that looks like a Social Security Number",
                        sourceNoteId: note.id,
                        sourceSectionId: "personal_data"
                    ))
                }
            }

            // Credit card
            if creditCardPattern.firstMatch(in: allText, range: range) != nil {
                let key = "\(note.id)|personal_data"
                if seenNoteSubtype.insert(key).inserted {
                    insights.append(Insight(
                        insightType: .safety,
                        title: "Possible credit card number in '\(pageTitle)'",
                        body: "Found a pattern that looks like a credit card number",
                        sourceNoteId: note.id,
                        sourceSectionId: "personal_data"
                    ))
                }
            }

            if insights.count >= 10 { return insights }
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
}
