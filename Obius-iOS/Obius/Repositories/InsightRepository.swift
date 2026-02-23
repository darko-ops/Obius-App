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
