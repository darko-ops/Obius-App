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
        sourceNoteId: String? = nil,
        sourceSectionId: String? = nil,
        relatedNoteId: String? = nil
    ) async throws -> Insight {
        let insight = Insight(
            insightType: type,
            title: title,
            body: body,
            sourceNoteId: sourceNoteId,
            sourceSectionId: sourceSectionId,
            relatedNoteId: relatedNoteId
        )
        try await database.write { db in
            try insight.insert(db)
        }
        return insight
    }

    /// Bulk-insert insights (used by InsightEngine after a scan)
    func createInsights(_ insights: [Insight]) async throws {
        try await database.write { db in
            for insight in insights {
                try insight.insert(db)
            }
        }
    }

    // MARK: - Read

    func getInsight(id: String) async throws -> Insight? {
        try await database.read { db in
            try Insight.fetchOne(db, key: id)
        }
    }

    func getAllSurfaced() async throws -> [Insight] {
        try await database.read { db in
            try Insight
                .filter(Insight.Columns.status == InsightStatus.surfaced.rawValue)
                .order(Insight.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func getAllTracked() async throws -> [Insight] {
        try await database.read { db in
            try Insight
                .filter(Insight.Columns.status == InsightStatus.tracked.rawValue)
                .order(Insight.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Update

    func trackInsight(_ insightId: String) async throws {
        try await database.write { db in
            guard var insight = try Insight.fetchOne(db, key: insightId) else { return }
            insight.track()
            try insight.update(db)
        }
    }

    func dismissInsight(_ insightId: String) async throws {
        try await database.write { db in
            guard var insight = try Insight.fetchOne(db, key: insightId) else { return }
            insight.dismiss()
            try insight.update(db)
        }
    }

    func untrackInsight(_ insightId: String) async throws {
        try await database.write { db in
            guard var insight = try Insight.fetchOne(db, key: insightId) else { return }
            insight.status = .dismissed
            insight.touch()
            try insight.update(db)
        }
    }

    // MARK: - Delete

    /// Remove all dismissed insights older than the given age (cleanup)
    func purgeDismissed(olderThan days: Int = 30) async throws {
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(days * 86_400_000)
        try await database.write { db in
            try Insight
                .filter(Insight.Columns.status == InsightStatus.dismissed.rawValue)
                .filter(Insight.Columns.updatedAt < cutoff)
                .deleteAll(db)
        }
    }

    /// Check if an insight already exists for a given source (prevents duplicates)
    func insightExists(type: InsightType, sourceNoteId: String?, sourceSectionId: String?) async throws -> Bool {
        try await database.read { db in
            var request = Insight
                .filter(Insight.Columns.insightType == type.rawValue)
                .filter(Insight.Columns.status != InsightStatus.dismissed.rawValue)

            if let noteId = sourceNoteId {
                request = request.filter(Insight.Columns.sourceNoteId == noteId)
            }
            if let sectionId = sourceSectionId {
                request = request.filter(Insight.Columns.sourceSectionId == sectionId)
            }

            return try request.fetchCount(db) > 0
        }
    }
}
