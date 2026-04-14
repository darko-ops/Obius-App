import Foundation
import GRDB
import UserNotifications

@MainActor
final class InsightEngine {
    private let noteRepository: NoteRepository
    private let sectionRepository: SectionRepository
    private let handleRepository: HandleRepository
    private let echoRepository: EchoRepository
    private let insightRepository: InsightRepository
    private let database: DatabaseManager

    init(
        noteRepository: NoteRepository,
        sectionRepository: SectionRepository,
        handleRepository: HandleRepository,
        echoRepository: EchoRepository,
        insightRepository: InsightRepository,
        database: DatabaseManager
    ) {
        self.noteRepository = noteRepository
        self.sectionRepository = sectionRepository
        self.handleRepository = handleRepository
        self.echoRepository = echoRepository
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

        // Fetch sections for ALL notes so inactive-loop detection is global
        // (loops are not project-scoped, so a loop referenced in any project
        // should not be flagged as inactive).
        var allSectionsByNote: [String: [Section]] = sectionsByNote
        if moduleId != nil {
            let otherNotes = allNotes.filter { $0.moduleId != moduleId }
            for note in otherNotes {
                if allSectionsByNote[note.id] == nil {
                    if let sections = try? await sectionRepository.getSections(noteId: note.id) {
                        allSectionsByNote[note.id] = sections
                    }
                }
            }
        }

        var newInsights: [Insight] = []

        // Run detectors — free tier only gets safety insights
        let hasFullInsights = TierManager.shared.limits.fullInsights
        if hasFullInsights {
            newInsights.append(contentsOf: detectCleanup(notes: notes, sectionsByNote: sectionsByNote, allSectionsByNote: allSectionsByNote))
            newInsights.append(contentsOf: detectLists(notes: notes, sectionsByNote: sectionsByNote))
        }
        newInsights.append(contentsOf: detectSafetyIssues(notes: notes, sectionsByNote: sectionsByNote))
        if hasFullInsights {
            newInsights.append(contentsOf: detectUpcomingEchoes(sectionsByNote: sectionsByNote))
            newInsights.append(contentsOf: detectLinks(notes: notes, sectionsByNote: sectionsByNote))
            newInsights.append(contentsOf: detectScheduleDates(notes: notes, sectionsByNote: sectionsByNote))
        }
        // Phase 2 stubs:
        // newInsights.append(contentsOf: await detectDrift(...))
        // newInsights.append(contentsOf: await generateWeeklyReport(...))
        // newInsights.append(contentsOf: await assessProjectHealth(...))

        // Invalidate insights that no longer match current content.
        // Compare existing active insights against fresh scan results —
        // any insight not reproduced by the detectors is stale.
        let freshKeys = Set(newInsights.map(\.dedupKey))
        try? await insightRepository.invalidateStaleInsights(freshKeys: freshKeys)

        // Batch dedup against all existing insights (surfaced, tracked, dismissed)
        let existingKeys = (try? await insightRepository.existingInsightKeys()) ?? []
        let deduped = newInsights.filter { !existingKeys.contains($0.dedupKey) }

        // Bulk insert
        if !deduped.isEmpty {
            do {
                try await insightRepository.createInsights(deduped)
                print("[InsightEngine] Inserted \(deduped.count) new insight(s): \(deduped.map { "\($0.insightType.rawValue)|\($0.sourceSectionId ?? "")|\($0.title)" })")

                // Only schedule notifications for safety insights
                for insight in deduped where insight.insightType == .safety {
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

    // MARK: - Content Helpers

    /// Collects all scannable text from a note: title, body, section titles,
    /// section content (all content types), and interstitial content.
    private static func allText(for note: Note, sections: [Section]) -> String {
        var parts: [String] = []
        if let title = note.title { parts.append(title) }
        if !note.body.isEmpty { parts.append(note.body) }
        for section in sections {
            if let sectionTitle = section.title, !sectionTitle.isEmpty {
                parts.append(sectionTitle)
            }
            // Skip image and audio sections — their content is SHA256 hashes, not user text
            if section.contentType == .image || section.contentType == .audio {
                continue
            }
            if !section.content.isEmpty {
                parts.append(section.content)
            }
        }
        for (_, text) in note.interstitialContent {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Cleanup Detector

    /// Detects dormant loops and nonsense content.
    private func detectCleanup(notes: [Note], sectionsByNote: [String: [Section]], allSectionsByNote: [String: [Section]]) -> [Insight] {
        var insights: [Insight] = []

        // -- Dormant loops --
        insights.append(contentsOf: detectDormantLoops(notes: notes, sectionsByNote: sectionsByNote))

        // -- Inactive loops (zero references) --
        insights.append(contentsOf: detectInactiveLoops(allSectionsByNote: allSectionsByNote))

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

    private func detectInactiveLoops(allSectionsByNote: [String: [Section]]) -> [Insight] {
        let handles = handleRepository.handles
        var insights: [Insight] = []

        // Collect all handleIds referenced by any section across ALL notes
        // (not just the current module) — loops are global, so a loop used
        // in any project should not be flagged as inactive.
        var activeHandleIds: Set<String> = []
        for (_, sections) in allSectionsByNote {
            for section in sections where section.deletedAt == nil {
                if let handleId = section.handleId {
                    activeHandleIds.insert(handleId)
                }
            }
        }

        // Loops with active echoes are also considered active
        for echo in echoRepository.activeEchoes {
            activeHandleIds.insert(echo.handleId)
        }

        for handle in handles {
            guard !activeHandleIds.contains(handle.id) else { continue }

            insights.append(Insight(
                insightType: .cleanup,
                title: "@\(handle.displayName) has no references",
                body: "This loop isn't used in any pages. Delete it to keep your project clean.",
                sourceNoteId: handle.id,
                sourceSectionId: "inactive_loop"
            ))

            if insights.count >= 5 { return insights }
        }

        return insights
    }

    /// Patterns that indicate personal/sensitive data — notes matching these
    /// should be flagged as safety issues, not nonsense.
    private static let sensitivePatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"\b\d{3}-\d{2}-\d{4}\b"#),                          // SSN
        try! NSRegularExpression(pattern: #"\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b"#),     // Credit card
        try! NSRegularExpression(pattern: #"(?:password|pwd|secret|token)\s*[:=]\s*\S+"#, options: [.caseInsensitive]), // Passwords
        try! NSRegularExpression(pattern: #"sk-[a-zA-Z0-9]{20,}"#),                             // API key
        try! NSRegularExpression(pattern: #"pk_[a-zA-Z0-9]{20,}"#),                             // API key
        try! NSRegularExpression(pattern: #"AKIA[0-9A-Z]{16}"#),                                // AWS key
        try! NSRegularExpression(pattern: #"\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}"#),              // Phone number (with or without separators)
    ]

    private static func containsSensitiveData(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return sensitivePatterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    private func detectNonsense(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        var insights: [Insight] = []

        for note in notes {
            let sections = sectionsByNote[note.id] ?? []
            let combined = Self.allText(for: note, sections: sections)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip notes with a real title but no other content — those are just titled stubs
            if let title = note.title,
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let withoutTitle = combined.dropFirst(title.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if withoutTitle.isEmpty { continue }
            }

            // Skip empty notes entirely
            guard !combined.isEmpty else { continue }

            // Skip notes that contain sensitive data — those belong to the safety detector
            if Self.containsSensitiveData(combined) { continue }

            // Strip whitespace and special characters for meaningful char count
            let meaningful = combined.unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0)
            }
            let meaningfulCount = meaningful.count

            // Flag if combined content < 10 meaningful chars
            let tooShort = meaningfulCount < 10

            // Flag if >80% non-alphabetic characters
            let alphabetic = combined.unicodeScalars.filter {
                CharacterSet.letters.contains($0)
            }
            let tooMuchNoise = Double(alphabetic.count) / Double(combined.count) < 0.2

            guard tooShort || tooMuchNoise else { continue }

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

    /// Detects list-like content: bullet points, numbered items, dashes, checklists,
    /// and plain-text lists (consecutive short lines of similar structure).
    private func detectLists(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        // Patterns that indicate a prefixed list item
        let bulletPrefixes = ["- ", "• ", "· ", "* ", "→ ", "‣ "]
        let numberedPattern = try! NSRegularExpression(pattern: #"^\d{1,3}[\.\)]\s"#)
        let letterPattern = try! NSRegularExpression(pattern: #"^[a-zA-Z][\.\)]\s"#)
        let prefixStrip = try! NSRegularExpression(pattern: #"^(?:[-•·*→‣]\s|\d{1,3}[.\)]\s|[a-zA-Z][.\)]\s|\[[ xX]\]\s?)"#)

        let listStopWords: Set<String> = [
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to",
            "for", "of", "with", "by", "from", "is", "it", "as", "be", "was",
            "are", "this", "that", "have", "has", "not", "they", "we", "you",
            "he", "she", "its", "my", "your", "our", "all", "can", "will",
            "just", "do", "so", "if", "no", "up", "out", "about", "more",
            "some", "than", "been", "would", "could", "should", "also", "very",
            "i", "me", "him", "her", "us", "am", "did", "does", "there",
            "here", "then", "now", "get", "got", "like", "make", "going",
            "thing", "things", "way", "one", "two", "first", "last", "new"
        ]

        var insights: [Insight] = []

        for note in notes {
            let sections = sectionsByNote[note.id] ?? []
            let pageTitle = note.displayTitle(sections: sections)

            /// Scans text for consecutive prefixed list runs (bullets, numbers, checklists)
            /// and appends an insight per list. Only detects explicitly prefixed items —
            /// plain short lines are NOT treated as list items to avoid false positives.
            func scanForLists(_ text: String, sectionId: String? = nil) {
                let lines = text.components(separatedBy: .newlines)
                var currentList: [String] = []
                // Track whether we've seen a non-list line before the first list item.
                // If the line immediately before a list run is short and unprefixed,
                // it's likely a title/header — don't include it.
                var previousNonListLine: String?

                func flushList() {
                    guard currentList.count >= 3 else {
                        currentList.removeAll()
                        return
                    }
                    let miniTitle = Self.listMiniTitle(
                        items: currentList,
                        prefixStrip: prefixStrip,
                        stopWords: listStopWords
                    )
                    let body = currentList.joined(separator: "\n")
                    insights.append(Insight(
                        insightType: .list,
                        title: "\(currentList.count) items in '\(pageTitle)' — \(miniTitle)",
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
                        previousNonListLine = nil
                        continue
                    }

                    let isBullet = bulletPrefixes.contains(where: { trimmed.hasPrefix($0) })
                    let range = NSRange(trimmed.startIndex..., in: trimmed)
                    let isNumbered = numberedPattern.firstMatch(in: trimmed, range: range) != nil
                    let isLettered = letterPattern.firstMatch(in: trimmed, range: range) != nil
                    let isChecklist = trimmed.hasPrefix("[ ]") || trimmed.hasPrefix("[x]") || trimmed.hasPrefix("[X]")

                    if isBullet || isNumbered || isLettered || isChecklist {
                        currentList.append(String(trimmed.prefix(120)))
                        previousNonListLine = nil
                    } else {
                        // Non-list line — flush any ongoing list
                        flushList()
                        previousNonListLine = trimmed
                    }
                }
                flushList()
            }

            // Check note body
            let bodyText = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bodyText.isEmpty {
                scanForLists(bodyText)
            }

            // Check section content only (not titles — they aren't list items)
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

    /// Derives a short descriptive label from the content of list items.
    /// Picks the top 1-2 most frequent meaningful words across all items.
    private static func listMiniTitle(
        items: [String],
        prefixStrip: NSRegularExpression,
        stopWords: Set<String>
    ) -> String {
        var wordCounts: [String: Int] = [:]

        for item in items {
            // Strip the list prefix (bullet, number, checkbox)
            let range = NSRange(item.startIndex..., in: item)
            let stripped = prefixStrip.stringByReplacingMatches(
                in: item, range: range, withTemplate: ""
            )

            let words = stripped.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !stopWords.contains($0) }

            // Count each word once per item (presence, not frequency within an item)
            for word in Set(words) {
                wordCounts[word, default: 0] += 1
            }
        }

        // Pick words that appear in 40%+ of items, sorted by frequency then length
        let threshold = max(2, items.count * 2 / 5)
        let topWords = wordCounts
            .filter { $0.value >= threshold }
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return a.key.count > b.key.count
            }
            .prefix(2)
            .map { $0.key.capitalized }

        if topWords.isEmpty {
            // Fallback: first item content, trimmed
            let fallback = items[0]
            let range = NSRange(fallback.startIndex..., in: fallback)
            let stripped = prefixStrip.stringByReplacingMatches(
                in: fallback, range: range, withTemplate: ""
            ).trimmingCharacters(in: .whitespaces)
            return String(stripped.prefix(40))
        }

        return topWords.joined(separator: " & ")
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
            var allText = Self.allText(for: note, sections: sections)
            if let aiTitle = note.aiTitle { allText += " " + aiTitle }

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

        // Step 5: Check which notes already share a loop or a block
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

        // Build block membership — notes in the same block are already grouped
        var sameBlockPairs: Set<String> = []
        let notesByBlock = Dictionary(grouping: notes.filter { $0.groupName != nil }, by: { $0.groupName! })
        for (_, blockNotes) in notesByBlock where blockNotes.count >= 2 {
            let sorted = blockNotes.map(\.id).sorted()
            for i in 0..<sorted.count {
                for j in (i + 1)..<sorted.count {
                    sameBlockPairs.insert("\(sorted[i])|\(sorted[j])")
                }
            }
        }

        // Step 6: Find note-level pairs with shared specific concepts (skip same-block)
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

                // Skip notes already connected by a loop or already in the same block
                if loopedPairs.contains(pairKey) { continue }
                if sameBlockPairs.contains(pairKey) { continue }

                let conceptsA = noteConcepts[noteA.id]!
                let conceptsB = noteConcepts[noteB.id]!
                let shared = conceptsA.intersection(conceptsB)

                // Require 2+ shared specific concepts
                guard shared.count >= 2 else { continue }

                let sectionsA = sectionsByNote[noteA.id] ?? []
                let sectionsB = sectionsByNote[noteB.id] ?? []
                let titleA = noteA.displayTitle(sections: sectionsA)
                let titleB = noteB.displayTitle(sections: sectionsB)

                let topConcepts = Array(shared
                    .sorted { $0.count > $1.count }
                    .prefix(3))

                let description = Self.linkDescription(
                    titleA: titleA,
                    titleB: titleB,
                    concepts: topConcepts
                )

                insights.append(Insight(
                    insightType: .link,
                    title: "Link '\(titleA)' and '\(titleB)'",
                    body: description,
                    sourceNoteId: noteA.id,
                    sourceSectionId: "link",
                    relatedNoteId: noteB.id
                ))

                if insights.count >= 3 { break }
            }
            if insights.count >= 3 { break }
        }

        // Step 7: Block-level link detection — compare blocks to each other and to ungrouped notes
        if insights.count < 5 {
            insights.append(contentsOf: detectBlockLinks(
                notes: notes,
                sectionsByNote: sectionsByNote,
                noteWords: noteWords,
                stopWords: stopWords,
                loopedPairs: loopedPairs,
                existingLinkCount: insights.count
            ))
        }

        return insights
    }

    /// Detects thematic connections between blocks, and between blocks and ungrouped notes.
    /// Aggregates all text within a block to reason about its collective theme.
    private func detectBlockLinks(
        notes: [Note],
        sectionsByNote: [String: [Section]],
        noteWords: [String: [String]],
        stopWords: Set<String>,
        loopedPairs: Set<String>,
        existingLinkCount: Int
    ) -> [Insight] {
        // Group notes by block name
        let notesByBlock = Dictionary(grouping: notes.filter { $0.groupName != nil }, by: { $0.groupName! })
        guard !notesByBlock.isEmpty else { return [] }

        // Build aggregated words per block
        var blockWords: [String: [String]] = [:]
        for (blockName, blockNotes) in notesByBlock {
            let combined = blockNotes.flatMap { noteWords[$0.id] ?? [] }
            if combined.count >= 10 {
                blockWords[blockName] = combined
            }
        }

        // Build keyphrases per block (same logic as per-note, but aggregated)
        var blockKeyphrases: [String: [String: Int]] = [:]
        for (blockName, words) in blockWords {
            var phraseCounts: [String: Int] = [:]
            for i in 0..<(words.count - 1) {
                let phrase = "\(words[i]) \(words[i + 1])"
                phraseCounts[phrase, default: 0] += 1
            }
            let repeated = phraseCounts.filter { $0.value >= 2 }
            if !repeated.isEmpty {
                blockKeyphrases[blockName] = repeated
            }
        }

        // Build keyphrases for ungrouped notes (each note is its own unit)
        var ungroupedKeyphrases: [String: [String: Int]] = [:] // noteId -> phrases
        for note in notes where note.groupName == nil {
            guard let words = noteWords[note.id] else { continue }
            var phraseCounts: [String: Int] = [:]
            for i in 0..<(words.count - 1) {
                let phrase = "\(words[i]) \(words[i + 1])"
                phraseCounts[phrase, default: 0] += 1
            }
            let repeated = phraseCounts.filter { $0.value >= 2 }
            if !repeated.isEmpty {
                ungroupedKeyphrases[note.id] = repeated
            }
        }

        // Compute document frequency across all blocks + ungrouped notes
        var phraseDocFreq: [String: Int] = [:]
        for (_, phrases) in blockKeyphrases {
            for phrase in phrases.keys { phraseDocFreq[phrase, default: 0] += 1 }
        }
        for (_, phrases) in ungroupedKeyphrases {
            for phrase in phrases.keys { phraseDocFreq[phrase, default: 0] += 1 }
        }

        let totalDocs = blockKeyphrases.count + ungroupedKeyphrases.count
        let maxDocs = min(totalDocs / 2 + 1, 5)
        let specificPhrases = Set(phraseDocFreq.filter { $0.value >= 2 && $0.value <= maxDocs }.keys)

        // Build concept sets for blocks
        var blockConcepts: [String: Set<String>] = [:]
        for (blockName, phrases) in blockKeyphrases {
            let specific = Set(phrases.keys).intersection(specificPhrases)
            if !specific.isEmpty { blockConcepts[blockName] = specific }
        }

        // Build concept sets for ungrouped notes
        var ungroupedConcepts: [String: Set<String>] = [:]
        for (noteId, phrases) in ungroupedKeyphrases {
            let specific = Set(phrases.keys).intersection(specificPhrases)
            if !specific.isEmpty { ungroupedConcepts[noteId] = specific }
        }

        var insights: [Insight] = []
        let cap = 5 - existingLinkCount

        // Block-to-block comparisons
        let blockNames = Array(blockConcepts.keys).sorted()
        for i in 0..<blockNames.count {
            for j in (i + 1)..<blockNames.count {
                guard insights.count < cap else { return insights }

                let blockA = blockNames[i]
                let blockB = blockNames[j]
                let shared = blockConcepts[blockA]!.intersection(blockConcepts[blockB]!)
                guard shared.count >= 2 else { continue }

                let topConcepts = Array(shared.sorted { $0.count > $1.count }.prefix(3))
                let description = Self.linkDescription(
                    titleA: blockA,
                    titleB: blockB,
                    concepts: topConcepts
                )

                // Use the first note in each block as source/related for navigation
                let sourceNoteId = notesByBlock[blockA]?.first?.id
                let relatedNoteId = notesByBlock[blockB]?.first?.id

                insights.append(Insight(
                    insightType: .link,
                    title: "Link block '\(blockA)' and block '\(blockB)'",
                    body: description,
                    sourceNoteId: sourceNoteId,
                    sourceSectionId: "block_link",
                    relatedNoteId: relatedNoteId
                ))
            }
        }

        // Block-to-ungrouped-note comparisons
        for blockName in blockNames {
            guard insights.count < cap else { return insights }
            guard let blockConceptSet = blockConcepts[blockName] else { continue }

            for note in notes where note.groupName == nil {
                guard insights.count < cap else { return insights }
                guard let noteConceptSet = ungroupedConcepts[note.id] else { continue }

                let shared = blockConceptSet.intersection(noteConceptSet)
                guard shared.count >= 2 else { continue }

                let sections = sectionsByNote[note.id] ?? []
                let noteTitle = note.displayTitle(sections: sections)

                let topConcepts = Array(shared.sorted { $0.count > $1.count }.prefix(3))
                let description = Self.linkDescription(
                    titleA: blockName,
                    titleB: noteTitle,
                    concepts: topConcepts
                )

                insights.append(Insight(
                    insightType: .link,
                    title: "'\(noteTitle)' relates to block '\(blockName)'",
                    body: description,
                    sourceNoteId: note.id,
                    sourceSectionId: "block_link",
                    relatedNoteId: notesByBlock[blockName]?.first?.id
                ))
            }
        }

        return insights
    }

    /// Builds a purposeful explanation of how two pages relate through shared concepts.
    /// Instead of listing raw word pairs, describes the thematic connection.
    private static func linkDescription(titleA: String, titleB: String, concepts: [String]) -> String {
        // Capitalize concepts for readability
        let themed = concepts.map { phrase in
            phrase.split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }

        switch themed.count {
        case 1:
            return "Both pages explore \(themed[0]) — a loop could unify these ideas"
        case 2:
            return "Both pages touch on \(themed[0]) and \(themed[1]) — linking them could surface deeper connections"
        default:
            let last = themed.last!
            let rest = themed.dropLast().joined(separator: ", ")
            return "Both pages discuss \(rest), and \(last) — connecting them may reveal a broader theme"
        }
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
        let phonePattern = try! NSRegularExpression(
            pattern: #"\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}"#,
            options: []
        )

        var insights: [Insight] = []
        var seenNoteSubtype: Set<String> = []

        for note in notes {
            let sections = sectionsByNote[note.id] ?? []
            let pageTitle = note.displayTitle(sections: sections)

            // Collect all text: title, body, section titles, section content, interstitial
            let allText = Self.allText(for: note, sections: sections)

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
                        body: "Found what looks like a secret key — consider removing it or locking this node with Face ID",
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
                        body: "Found text that looks like a stored credential — lock this node with Face ID to protect it",
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
                        body: "Found a pattern that looks like a Social Security Number — lock this node with Face ID to protect it",
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
                        body: "Found a pattern that looks like a credit card number — lock this node with Face ID to protect it",
                        sourceNoteId: note.id,
                        sourceSectionId: "personal_data"
                    ))
                }
            }

            // Phone number
            if phonePattern.firstMatch(in: allText, range: range) != nil {
                let key = "\(note.id)|personal_data"
                if seenNoteSubtype.insert(key).inserted {
                    insights.append(Insight(
                        insightType: .safety,
                        title: "Possible phone number in '\(pageTitle)'",
                        body: "Found a pattern that looks like a phone number — lock this node with Face ID to protect it",
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
            } else if subtype == "inactive_loop" {
                content.title = "Inactive loop"
                content.body = insight.title
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

    // MARK: - Schedule Detector

    /// Detects dates/times in note content and creates schedule insights
    /// so the user can quickly create an echo from a detected date.
    private func detectScheduleDates(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        var insights: [Insight] = []
        let now = Date()
        let detector: NSDataDetector
        do {
            detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        } catch {
            print("[InsightEngine] Failed to create date detector: \(error)")
            return []
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateStyle = .medium
        dateOnlyFormatter.timeStyle = .none

        for note in notes {
            let sections = sectionsByNote[note.id] ?? []
            let text = Self.allText(for: note, sections: sections)
            guard !text.isEmpty else { continue }

            let range = NSRange(text.startIndex..., in: text)
            let matches = detector.matches(in: text, options: [], range: range)
            var noteCount = 0

            for match in matches {
                // Cap at 3 schedule insights per note to avoid noise
                guard noteCount < 3 else { break }

                guard let matchDate = match.date else { continue }

                // Only surface dates that are in the future (at least 1 hour from now)
                guard matchDate > now.addingTimeInterval(3600) else { continue }

                // Don't surface dates more than 1 year out — likely false positives
                guard matchDate < now.addingTimeInterval(365 * 24 * 3600) else { continue }

                // Extract the matched text for context
                guard let matchRange = Range(match.range, in: text) else { continue }

                // Get surrounding context (up to 60 chars on each side)
                let contextStart = text.index(matchRange.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
                let contextEnd = text.index(matchRange.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
                let context = String(text[contextStart..<contextEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

                // Determine if the match includes a time component
                let hasTime = match.duration == 0 && Calendar.current.component(.hour, from: matchDate) != 0
                let formattedDate = hasTime ? dateFormatter.string(from: matchDate) : dateOnlyFormatter.string(from: matchDate)

                let fireMs = Int64(matchDate.timeIntervalSince1970 * 1000)
                let noteTitle = note.displayTitle

                insights.append(Insight(
                    insightType: .schedule,
                    title: "Date found in \(noteTitle)",
                    body: "\(formattedDate) — \"\(context)\"",
                    sourceNoteId: note.id,
                    sourceSectionId: "schedule",
                    relatedNoteId: String(fireMs)
                ))
                noteCount += 1
            }
        }

        print("[InsightEngine] detectScheduleDates found \(insights.count) date(s)")
        return insights
    }
}
