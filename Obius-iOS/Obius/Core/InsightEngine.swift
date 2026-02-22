import Foundation
import GRDB

/// Scans user content and generates Insight cards for the Intelligence page.
/// All analysis is local — no network calls. Insights are derived from
/// content patterns, timestamps, and structural signals.
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

    /// Run all insight detectors and persist new insights.
    func scan() async {
        var newInsights: [Insight] = []

        let notes = noteRepository.notes.filter { $0.deletedAt == nil }
        guard !notes.isEmpty else { return }

        // Fetch all live sections once
        let allSections: [Section]
        do {
            allSections = try await database.read { db in
                try Section
                    .filter(Section.Columns.deletedAt == nil)
                    .order(Section.Columns.noteId, Section.Columns.orderKey)
                    .fetchAll(db)
            }
        } catch {
            print("InsightEngine: failed to fetch sections: \(error)")
            return
        }

        let sectionsByNote = Dictionary(grouping: allSections, by: { $0.noteId })

        // Run detectors
        newInsights.append(contentsOf: await detectSuggestedTasks(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: await detectOpenQuestions(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: detectStaleContent(notes: notes))
        newInsights.append(contentsOf: detectGrowingNotes(notes: notes, sectionsByNote: sectionsByNote))
        newInsights.append(contentsOf: await detectLonelyHandles())

        // Deduplicate against existing insights
        var filtered: [Insight] = []
        for insight in newInsights {
            let exists = try? await insightRepository.insightExists(
                type: insight.insightType,
                sourceNoteId: insight.sourceNoteId,
                sourceSectionId: insight.sourceSectionId
            )
            if exists != true {
                filtered.append(insight)
            }
        }

        guard !filtered.isEmpty else { return }
        try? await insightRepository.createInsights(filtered)

        // Cleanup old dismissed insights
        try? await insightRepository.purgeDismissed()
    }

    // MARK: - Suggested Tasks

    /// Detects sections whose content reads like action items.
    private func detectSuggestedTasks(notes: [Note], sectionsByNote: [String: [Section]]) async -> [Insight] {
        var insights: [Insight] = []

        let taskPatterns: [String] = [
            "need to ", "should ", "have to ", "must ", "todo", "to-do",
            "don't forget", "remember to ", "make sure ", "follow up",
            "deadline", "by tomorrow", "by monday", "by friday", "next week",
            "action item", "action:", "do this"
        ]

        for note in notes {
            guard let sections = sectionsByNote[note.id] else { continue }
            for section in sections {
                // Skip sections already marked as task intent (user already knows)
                if section.intent == .task { continue }

                let lower = section.content.lowercased()
                let matchedPattern = taskPatterns.first { lower.contains($0) }

                if let pattern = matchedPattern {
                    let preview = String(section.content.prefix(120))
                    insights.append(Insight(
                        insightType: .suggestedTask,
                        title: "Looks like a task",
                        body: "\"\(preview)\" contains \"\(pattern)\" — track it?",
                        sourceNoteId: note.id,
                        sourceSectionId: section.id
                    ))
                }

                // Cap insights per scan
                if insights.count >= 5 { return insights }
            }
        }

        return insights
    }

    // MARK: - Open Questions

    /// Detects sections that end with question marks or contain question-like phrases.
    private func detectOpenQuestions(notes: [Note], sectionsByNote: [String: [Section]]) async -> [Insight] {
        var insights: [Insight] = []

        let questionPhrases = [
            "how do ", "how does ", "how can ", "how should ",
            "what if ", "what is ", "what are ",
            "why does ", "why is ", "why do ",
            "where can ", "where is ",
            "should i ", "should we ", "can we ", "could we "
        ]

        for note in notes {
            guard let sections = sectionsByNote[note.id] else { continue }
            for section in sections {
                if section.intent == .question { continue }

                let trimmed = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = trimmed.lowercased()

                let isQuestion = trimmed.hasSuffix("?")
                    || questionPhrases.contains(where: { lower.hasPrefix($0) || lower.contains("\n\($0)") })

                if isQuestion {
                    let preview = String(trimmed.prefix(120))
                    insights.append(Insight(
                        insightType: .openQuestion,
                        title: "Open question",
                        body: "\"\(preview)\"",
                        sourceNoteId: note.id,
                        sourceSectionId: section.id
                    ))
                }

                if insights.count >= 5 { return insights }
            }
        }

        return insights
    }

    // MARK: - Stale Content

    /// Detects notes that haven't been edited in over 14 days.
    private func detectStaleContent(notes: [Note]) -> [Insight] {
        var insights: [Insight] = []
        let fourteenDaysAgo = Int64(Date().timeIntervalSince1970 * 1000) - 14 * 86_400_000

        for note in notes {
            guard note.updatedAt < fourteenDaysAgo else { continue }
            // Only flag notes with actual content
            guard note.body.trimmingCharacters(in: .whitespacesAndNewlines).count > 20
                    || (note.title ?? "").count > 0 else { continue }

            let title = note.displayTitle
            let daysSince = Int((Date().timeIntervalSince1970 * 1000 - Double(note.updatedAt)) / 86_400_000)

            insights.append(Insight(
                insightType: .staleContent,
                title: "Untouched for \(daysSince) days",
                body: "\"\(title)\" — still relevant, or ready to archive?",
                sourceNoteId: note.id
            ))

            if insights.count >= 3 { return insights }
        }

        return insights
    }

    // MARK: - Growing Notes

    /// Detects notes with a high section count (accumulating quickly).
    private func detectGrowingNotes(notes: [Note], sectionsByNote: [String: [Section]]) -> [Insight] {
        var insights: [Insight] = []

        for note in notes {
            let count = sectionsByNote[note.id]?.count ?? 0
            guard count >= 10 else { continue }

            let title = note.displayTitle

            insights.append(Insight(
                insightType: .growingNote,
                title: "\(count) sections and growing",
                body: "\"\(title)\" is getting large. Might be worth splitting or organizing.",
                sourceNoteId: note.id
            ))

            if insights.count >= 2 { return insights }
        }

        return insights
    }

    // MARK: - Lonely Handles

    /// Detects handles that are only referenced from a single section.
    private func detectLonelyHandles() async -> [Insight] {
        do {
            let handleUsage: [(Handle, Int)] = try await database.read { db in
                let handles = try Handle
                    .filter(Handle.Columns.deletedAt == nil)
                    .fetchAll(db)

                return try handles.map { handle in
                    let refCount = try Section
                        .filter(Section.Columns.handleId == handle.id)
                        .filter(Section.Columns.deletedAt == nil)
                        .fetchCount(db)
                    return (handle, refCount)
                }
            }

            return handleUsage
                .filter { $0.1 == 1 }
                .prefix(3)
                .map { handle, _ in
                    Insight(
                        insightType: .lonelyHandle,
                        title: "@\(handle.displayName) used once",
                        body: "This handle is only referenced in one place. Consider linking it elsewhere or inlining the content.",
                        sourceNoteId: nil,
                        sourceSectionId: nil
                    )
                }
        } catch {
            print("InsightEngine: failed to detect lonely handles: \(error)")
            return []
        }
    }
}
