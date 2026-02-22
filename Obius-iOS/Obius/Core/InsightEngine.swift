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
            "who should", "which", "could we"
        ]

        var insights: [Insight] = []

        for note in notes {
            guard let sections = sectionsByNote[note.id] else { continue }

            for section in sections {
                // Skip sections already classified as questions
                guard section.intent != .question else { continue }
                guard section.contentType == .text || section.contentType == .quote else { continue }

                let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { continue }

                let lower = content.lowercased()
                let endsWithQuestion = content.hasSuffix("?")
                let startsWithQuestion = questionPrefixes.contains { lower.hasPrefix($0) }

                if endsWithQuestion || startsWithQuestion {
                    let preview = String(content.prefix(120))
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
}
