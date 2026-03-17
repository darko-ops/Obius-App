import Foundation
import GRDB
import UserNotifications

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
    /// When `moduleId` is provided, only notes in that module are scanned
    /// so caps and limits apply per-module rather than globally.
    func scan(moduleId: String? = nil) async {
        let allNotes = noteRepository.notes.filter { !$0.isDeleted }
        let notes: [Note]
        if let moduleId {
            notes = allNotes.filter { $0.moduleId == moduleId }
        } else {
            notes = allNotes
        }
        print("[InsightEngine] scan(module: \(moduleId ?? "all")) started — \(notes.count) notes")

        // Skip scan entirely if notes haven't loaded yet — avoids wiping
        // existing insights via garbage collection on an empty list.
        guard !notes.isEmpty else {
            print("[InsightEngine] scan() aborted — no notes loaded yet")
            return
        }

        // Garbage-collect using ALL notes (not module-filtered) to avoid
        // deleting insights for notes in other modules.
        let allValidNoteIds = Set(allNotes.map(\.id))
        try? await insightRepository.removeOrphanedInsights(validNoteIds: allValidNoteIds)

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
        newInsights.append(contentsOf: detectLists(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectSafetyIssues(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectUpcomingEchoes(sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectLinks(notes: notes, sectionsByNote: sectionsByNote))
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

                // Schedule local notifications for new insights
                for insight in deduped {
                    scheduleInsightNotification(insight)
                }
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

    /// Detects dormant loops and nonsense content.
    private func detectCleanup(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        var insights: [Insight] = []

        // -- Dormant loops --
        insights.append(contentsOf: detectDormantLoops(notes: notes, sectionsByNote: sectionsByNote))

        // -- Nonsense content --
        insights.append(contentsOf: detectNonsense(notes: notes, sectionsByNote: sectionsByNote))

        return insights
    }

    private func detectDormantLoops(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
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
            let noteId = handleFirstNoteId[handle.id]
            let pageTitle: String
            if let noteId, let note = notes.first(where: { $0.id == noteId }) {
                pageTitle = note.displayTitle(sections: sectionsByNote[noteId] ?? [])
            } else {
                pageTitle = "a page"
            }
            insights.append(Insight(
                insightType: .cleanup,
                title: "@\(handle.displayName) dormant for \(daysSince) days",
                body: "Organize '\(pageTitle)' into a block to keep it accessible",
                sourceNoteId: noteId,
                sourceSectionId: "dormant_loop"
            ))

            if insights.count >= 5 { return insights }
        }

        return insights
    }

    private func detectNonsense(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
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

            let sections = sectionsByNote[note.id] ?? []
            let pageTitle = note.displayTitle(sections: sections)

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

    // MARK: - List Detector

    /// Detects list-like content: bullet points, numbered items, dashes, or checklists.
    private func detectLists(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        // Patterns that indicate a list item
        let bulletPrefixes = ["- ", "• ", "· ", "* ", "→ ", "‣ "]
        let numberedPattern = try! NSRegularExpression(pattern: #"^\d{1,3}[\.\)]\s"#)
        let letterPattern = try! NSRegularExpression(pattern: #"^[a-zA-Z][\.\)]\s"#)

        var insights: [Insight] = []

        for note in notes {
            let sections = sectionsByNote[note.id] ?? []
            let pageTitle = note.displayTitle(sections: sections)

            /// Scans text for consecutive list runs and appends an insight per list.
            func scanForLists(_ text: String, sectionId: String? = nil) {
                let lines = text.components(separatedBy: .newlines)
                var currentList: [String] = []

                func flushList() {
                    guard currentList.count >= 3 else {
                        currentList.removeAll()
                        return
                    }
                    let firstItem = currentList[0]
                        .trimmingCharacters(in: .whitespaces)
                        .prefix(60)
                    let body = currentList.map { "• \($0)" }.joined(separator: "\n")
                    insights.append(Insight(
                        insightType: .list,
                        title: "\(currentList.count)-item list in '\(pageTitle)' — \(firstItem)…",
                        body: body,
                        sourceNoteId: note.id,
                        sourceSectionId: sectionId ?? "list"
                    ))
                    currentList.removeAll()
                }

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else {
                        flushList()
                        continue
                    }

                    let isBullet = bulletPrefixes.contains(where: { trimmed.hasPrefix($0) })
                    let range = NSRange(trimmed.startIndex..., in: trimmed)
                    let isNumbered = numberedPattern.firstMatch(in: trimmed, range: range) != nil
                    let isLettered = letterPattern.firstMatch(in: trimmed, range: range) != nil
                    let isChecklist = trimmed.hasPrefix("[ ]") || trimmed.hasPrefix("[x]") || trimmed.hasPrefix("[X]")

                    if isBullet || isNumbered || isLettered || isChecklist {
                        currentList.append(String(trimmed.prefix(120)))
                    } else {
                        flushList()
                    }
                }
                flushList()
            }

            // Check note body
            let bodyText = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bodyText.isEmpty {
                scanForLists(bodyText)
            }

            // Check sections (skip checklists — they're already structured)
            for section in sections {
                guard section.contentType == .text else { continue }
                let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { continue }
                scanForLists(content, sectionId: section.id)
            }

            // Check interstitial content
            for (_, text) in note.interstitialContent {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                scanForLists(trimmed)
            }
        }

        return insights
    }

    // MARK: - Link Detector

    /// Detects shared concepts across pages using repeated keyphrases that are
    /// specific to a small number of notes (TF-IDF style). Suggests connecting
    /// related pages with loops.
    private func detectLinks(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        guard notes.count >= 2 else { return [] }

        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "is", "it", "as", "be", "was", "are",
            "this", "that", "have", "has", "had", "not", "they", "we", "you",
            "he", "she", "its", "my", "your", "our", "their", "all", "can",
            "will", "just", "do", "so", "if", "no", "up", "out", "about",
            "into", "more", "some", "than", "them", "been", "would", "could",
            "should", "also", "very", "much", "how", "what", "when", "where",
            "which", "who", "why", "i", "me", "him", "her", "us", "am",
            "did", "does", "don", "there", "here", "then", "now", "get",
            "got", "like", "make", "made", "going", "went", "thing", "things",
            "way", "think", "know", "see", "look", "come", "take", "good",
            "new", "one", "two", "first", "last", "well", "back", "even",
            "still", "over", "after", "before", "only", "other", "being",
            "too", "need", "want", "use", "used", "using", "work", "let",
            "try", "keep", "untitled", "note", "notes", "page", "really",
            "actually", "maybe", "kind", "sort", "lot", "bit", "pretty",
            "three", "four", "five", "same", "many", "most", "such", "each",
            "every", "both", "another", "around", "through", "between",
            "down", "right", "left", "long", "great", "little", "just",
            "start", "started", "create", "created", "added", "adding",
            "check", "checked", "update", "updated", "change", "changed",
            "already", "done", "working", "might", "something", "anything",
            "everything", "nothing", "seem", "seems", "went", "since"
        ]

        // Step 1: Extract meaningful words per note
        var noteWords: [String: [String]] = [:]
        for note in notes {
            let sections = sectionsByNote[note.id] ?? []
            var allText = ""
            if let title = note.title { allText += title + " " }
            if let aiTitle = note.aiTitle { allText += aiTitle + " " }
            allText += note.body + " "
            for section in sections where section.contentType == .text {
                allText += section.content + " "
            }

            let words = allText.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 4 && !stopWords.contains($0) }

            if words.count >= 5 { // Notes need substance
                noteWords[note.id] = words
            }
        }

        // Step 2: Build keyphrase frequency per note (bigrams that repeat 2+ times in the note)
        // A concept is a bigram that the author returns to — not just mentioned once
        var noteKeyphrases: [String: [String: Int]] = [:] // noteId -> phrase -> count

        for (noteId, words) in noteWords {
            var phraseCounts: [String: Int] = [:]
            for i in 0..<(words.count - 1) {
                let phrase = "\(words[i]) \(words[i + 1])"
                phraseCounts[phrase, default: 0] += 1
            }
            // Only keep phrases mentioned 2+ times = the author is focusing on this concept
            let repeated = phraseCounts.filter { $0.value >= 2 }
            if !repeated.isEmpty {
                noteKeyphrases[noteId] = repeated
            }
        }

        // Step 3: Compute document frequency — how many notes contain each phrase
        var phraseDocFreq: [String: Int] = [:]
        for (_, phrases) in noteKeyphrases {
            for phrase in phrases.keys {
                phraseDocFreq[phrase, default: 0] += 1
            }
        }

        // Step 4: Filter to "specific" concepts — appear in 2-4 notes (not universal, not unique)
        // If a phrase appears in too many notes it's generic; if only 1 it can't link anything
        let maxDocs = min(notes.count / 2 + 1, 5) // Scale with project size
        let specificPhrases = Set(phraseDocFreq.filter { $0.value >= 2 && $0.value <= maxDocs }.keys)

        // Build per-note concept sets (only specific phrases)
        var noteConcepts: [String: Set<String>] = [:]
        for (noteId, phrases) in noteKeyphrases {
            let specific = Set(phrases.keys).intersection(specificPhrases)
            if !specific.isEmpty {
                noteConcepts[noteId] = specific
            }
        }

        // Step 5: Check which notes already share a loop
        var loopedPairs: Set<String> = []
        var handleNotes: [String: Set<String>] = [:]
        for (noteId, sections) in sectionsByNote {
            for section in sections {
                if let handleId = section.handleId {
                    handleNotes[handleId, default: []].insert(noteId)
                }
            }
        }
        for (_, noteIds) in handleNotes where noteIds.count >= 2 {
            let sorted = noteIds.sorted()
            for i in 0..<sorted.count {
                for j in (i + 1)..<sorted.count {
                    loopedPairs.insert("\(sorted[i])|\(sorted[j])")
                }
            }
        }

        // Step 6: Find pairs with shared specific concepts
        var insights: [Insight] = []
        var seenPairs: Set<String> = []
        let noteArray = notes.filter { noteConcepts[$0.id] != nil }

        for i in 0..<noteArray.count {
            for j in (i + 1)..<noteArray.count {
                let noteA = noteArray[i]
                let noteB = noteArray[j]

                let pairKey = [noteA.id, noteB.id].sorted().joined(separator: "|")
                guard !seenPairs.contains(pairKey) else { continue }
                seenPairs.insert(pairKey)

                if loopedPairs.contains(pairKey) { continue }

                let conceptsA = noteConcepts[noteA.id]!
                let conceptsB = noteConcepts[noteB.id]!
                let shared = conceptsA.intersection(conceptsB)

                // Require 2+ shared specific concepts
                guard shared.count >= 2 else { continue }

                let sectionsA = sectionsByNote[noteA.id] ?? []
                let sectionsB = sectionsByNote[noteB.id] ?? []
                let titleA = noteA.displayTitle(sections: sectionsA)
                let titleB = noteB.displayTitle(sections: sectionsB)

                let topConcepts = shared
                    .sorted { $0.count > $1.count }
                    .prefix(3)
                    .joined(separator: ", ")

                insights.append(Insight(
                    insightType: .link,
                    title: "Link '\(titleA)' and '\(titleB)'",
                    body: "Shared concepts: \(topConcepts) — connect them with a loop",
                    sourceNoteId: noteA.id,
                    sourceSectionId: "link",
                    relatedNoteId: noteB.id
                ))

                if insights.count >= 3 { break }
            }
            if insights.count >= 3 { break }
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
        let oneHourAgo = now.addingTimeInterval(-60 * 60)
        let twentyFourHoursFromNow = now.addingTimeInterval(24 * 60 * 60)
        var insights: [Insight] = []

        for echo in EchoManager.shared.activeEchoes {
            guard let fireDate = echo.nextFireDateAsDate else { continue }

            // Include echoes firing now (up to 1h overdue) or upcoming within 24h
            let isFiring = fireDate <= now && fireDate > oneHourAgo
            let isUpcoming = fireDate > now && fireDate <= twentyFourHoursFromNow
            guard isFiring || isUpcoming else { continue }

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
            let timeDesc: String
            if isFiring {
                timeDesc = "Firing now"
            } else {
                let interval = fireDate.timeIntervalSince(now)
                let hours = Int(interval / 3600)
                let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
                if hours > 0 {
                    timeDesc = "Fires in \(hours)h \(minutes)m"
                } else {
                    timeDesc = "Fires in \(minutes)m"
                }
            }

            insights.append(Insight(
                insightType: .upcomingEcho,
                title: isFiring
                    ? "Echo: @\(handleName)"
                    : "Echo: @\(handleName) fires soon",
                body: timeDesc,
                sourceNoteId: noteId,
                sourceSectionId: sectionId
            ))

            if insights.count >= 5 { return insights }
        }

        return insights
    }

    // MARK: - Notifications

    /// Schedules a local notification with type-specific content for a new insight.
    private func scheduleInsightNotification(_ insight: Insight) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch insight.insightType {
        case .cleanup:
            let subtype = insight.sourceSectionId ?? ""
            if subtype == "dormant_loop" {
                content.title = "Dormant loop: \(insight.title.components(separatedBy: " dormant").first ?? insight.title)"
                content.body = insight.body
            } else {
                content.title = "Possible nonsense"
                content.body = "'\(insight.title.replacingOccurrences(of: "' may be nonsense", with: ""))' may need cleanup"
            }
        case .list:
            content.title = insight.title
            content.body = insight.body.components(separatedBy: "\n").first ?? ""
        case .link:
            content.title = "Pages may be related"
            content.body = insight.body
        case .safety:
            content.title = "Sensitive data detected"
            content.body = insight.body
        case .upcomingEcho:
            content.title = insight.title
            content.body = insight.body
        default:
            return
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: insight.id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[InsightEngine] Notification scheduling failed: \(error)")
            }
        }
    }
}
