import Foundation
import GRDB
import Combine

@MainActor
final class InsightRepository: ObservableObject {
    private let database: DatabaseManager
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var surfacedInsights: [Insight] = []
    @Published private(set) var trackedInsights: [Insight] = []

    init(database: DatabaseManager) {
        self.database = database
        observeSurfaced()
        observeTracked()
    }

    private func observeSurfaced() {
        database.observeInsights(status: .surfaced)
            .receive(on: DispatchQueue.main)
            .catch { error -> Just<[Insight]> in
                print("Error observing surfaced insights: \(error)")
                return Just([])
            }
            .sink { [weak self] insights in
                self?.surfacedInsights = insights
            }
            .store(in: &cancellables)
    }

    private func observeTracked() {
        database.observeInsights(status: .tracked)
            .receive(on: DispatchQueue.main)
            .catch { error -> Just<[Insight]> in
                print("Error observing tracked insights: \(error)")
                return Just([])
            }
            .sink { [weak self] insights in
                self?.trackedInsights = insights
            }
            .store(in: &cancellables)
    }

    // MARK: - Create

    func createInsight(
        type: InsightType,
        title: String,
        body: String,
        status: InsightStatus = .surfaced,
        sourceNoteId: String? = nil,
        sourceSectionId: String? = nil,
        relatedNoteId: String? = nil
    ) async throws {
        let insight = Insight(
            insightType: type,
            title: title,
            body: body,
            status: status,
            sourceNoteId: sourceNoteId,
            sourceSectionId: sourceSectionId,
            relatedNoteId: relatedNoteId
        )

        try await database.write { db in
            try insight.insert(db)
        }
    }

    func createInsights(_ insights: [Insight]) async throws {
        guard !insights.isEmpty else { return }
        try await database.write { db in
            for insight in insights {
                try insight.insert(db)
            }
        }
    }

    // MARK: - Update

    func trackInsight(_ id: String) async throws {
        try await database.write { db in
            guard var insight = try Insight.fetchOne(db, key: id) else { return }
            insight.track()
            try insight.update(db)
        }
    }

    func dismissInsight(_ id: String) async throws {
        try await database.write { db in
            guard var insight = try Insight.fetchOne(db, key: id) else { return }
            insight.dismiss()
            try insight.update(db)
        }
    }

    func untrackInsight(_ id: String) async throws {
        try await database.write { db in
            guard var insight = try Insight.fetchOne(db, key: id) else { return }
            insight.status = .surfaced
            insight.touch()
            try insight.update(db)
        }
    }

    // MARK: - Query

    func insightExists(type: InsightType, sourceNoteId: String?, sourceSectionId: String?) async throws -> Bool {
        try await database.read { db in
            var query = Insight
                .filter(Insight.Columns.insightType == type.rawValue)

            if let noteId = sourceNoteId {
                query = query.filter(Insight.Columns.sourceNoteId == noteId)
            }
            if let sectionId = sourceSectionId {
                query = query.filter(Insight.Columns.sourceSectionId == sectionId)
            }

            return try query.fetchCount(db) > 0
        }
    }

    // MARK: - Batch Dedup

    /// Returns dedup keys for all existing insights (any status) in one query.
    func existingInsightKeys() async throws -> Set<String> {
        try await database.read { db in
            let insights = try Insight.fetchAll(db)
            return Set(insights.map(\.dedupKey))
        }
    }

    // MARK: - Garbage Collection

    /// Removes or dismisses insights whose references no longer exist.
    func removeOrphanedInsights(validNoteIds: Set<String>) async throws {
        let activeEchoHandleIds = Set(EchoManager.shared.activeEchoes.map(\.handleId))

        try await database.write { db in
            let now = Int64(Date().timeIntervalSince1970 * 1000)

            let active = try Insight
                .filter(Insight.Columns.status != InsightStatus.dismissed.rawValue)
                .fetchAll(db)

            for var insight in active {
                // Upcoming echo insights: purge surfaced ones (detector recreates valid ones each scan).
                // For tracked ones, dismiss if the echo's handle no longer has an active echo.
                if insight.insightType == .upcomingEcho {
                    if insight.status == .surfaced {
                        try Insight.deleteOne(db, key: insight.id)
                    } else if let sectionId = insight.sourceSectionId {
                        // Look up the handle for this section to check if its echo still exists
                        let handleStillActive = try Section.fetchOne(db, key: sectionId)
                            .flatMap { $0.handleId }
                            .map { activeEchoHandleIds.contains($0) } ?? false
                        if !handleStillActive {
                            insight.status = .dismissed
                            insight.updatedAt = now
                            try insight.update(db)
                        }
                    }
                    continue
                }

                guard insight.sourceNoteId != nil else { continue }
                let sourceOrphaned = insight.sourceNoteId.map { !validNoteIds.contains($0) } ?? false

                // Clean relatedNoteId references
                var relatedCleaned = false
                if let related = insight.relatedNoteId {
                    let ids = related.split(separator: ",").map(String.init)
                    let cleaned = ids.filter { validNoteIds.contains($0) }
                    let newValue = cleaned.isEmpty ? nil : cleaned.joined(separator: ",")
                    if newValue != related {
                        insight.relatedNoteId = newValue
                        relatedCleaned = true
                    }
                }

                if sourceOrphaned {
                    if insight.status == .surfaced {
                        try Insight.deleteOne(db, key: insight.id)
                    } else {
                        insight.status = .dismissed
                        insight.updatedAt = now
                        try insight.update(db)
                    }
                } else if relatedCleaned {
                    insight.updatedAt = now
                    try insight.update(db)
                }
            }
        }
    }

    // MARK: - Echo Cleanup

    /// Dismiss all upcomingEcho insights (used when an echo is deleted).
    func dismissEchoInsights() async throws {
        try await database.write { db in
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            try db.execute(sql: """
                UPDATE insights
                SET status = 'dismissed', updatedAt = ?
                WHERE insightType = 'upcomingEcho' AND status != 'dismissed'
            """, arguments: [now])
        }
    }

    // MARK: - Cleanup

    func purgeDismissed(olderThan days: Int = 30) async throws {
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(days) * 86_400_000
        try await database.write { db in
            try Insight
                .filter(Insight.Columns.status == InsightStatus.dismissed.rawValue)
                .filter(Insight.Columns.updatedAt < cutoff)
                .deleteAll(db)
        }
    }
}
