import Foundation
import GRDB
import Combine

@MainActor
final class EchoRepository: ObservableObject {
    private let database: DatabaseManager
    var syncLogger: SyncOperationLogger?

    @Published private(set) var activeEchoes: [Echo] = []
    private var cancellables = Set<AnyCancellable>()

    init(database: DatabaseManager) {
        self.database = database
        observeEchoes()
    }

    private func observeEchoes() {
        database.observeActiveEchoes()
            .receive(on: DispatchQueue.main)
            .catch { error -> Just<[Echo]> in
                print("Error observing echoes: \(error)")
                return Just([])
            }
            .sink { [weak self] echoes in
                self?.activeEchoes = echoes
            }
            .store(in: &cancellables)
    }

    // MARK: - Create

    func createEcho(
        handleId: String,
        isRecurring: Bool,
        intervals: [EchoInterval],
        fireDate: Int64
    ) async throws -> Echo {
        let intervalsJSON: String? = {
            guard isRecurring, !intervals.isEmpty else { return nil }
            guard let data = try? JSONEncoder().encode(intervals) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        let echo = try await database.write { db in
            var echo = Echo(
                handleId: handleId,
                isRecurring: isRecurring,
                intervalsJSON: intervalsJSON,
                fireDate: fireDate
            )
            echo.updateNextFireDate()
            try echo.insert(db)
            try Self.recomputeScoresForHandle(handleId, in: db)
            return echo
        }
        syncLogger?.logEchoCreate(echo)
        return echo
    }

    // MARK: - Read

    func getEcho(id: String) async throws -> Echo? {
        try await database.read { db in
            try Echo.fetchOne(db, key: id)
        }
    }

    func getEchoForHandle(handleId: String) async throws -> Echo? {
        try await database.read { db in
            try Echo
                .filter(Echo.Columns.handleId == handleId)
                .filter(Echo.Columns.isActive == true)
                .fetchOne(db)
        }
    }

    func getAllActiveEchoes() async throws -> [Echo] {
        try await database.read { db in
            try Echo
                .filter(Echo.Columns.isActive == true)
                .order(Echo.Columns.nextFireDate)
                .fetchAll(db)
        }
    }

    // MARK: - Update

    func deactivateEcho(id: String) async throws {
        let updatedEcho = try await database.write { db -> Echo? in
            guard var echo = try Echo.fetchOne(db, key: id) else { return nil }
            echo.deactivate()
            try echo.update(db)

            // Dismiss upcomingEcho insights for this echo's handle
            Self.dismissEchoInsights(handleId: echo.handleId, db: db)
            try Self.recomputeScoresForHandle(echo.handleId, in: db)
            return echo
        }
        if let echo = updatedEcho {
            syncLogger?.logEchoUpdate(echo)
        }
    }

    func updateNextFireDate(id: String) async throws {
        let updatedEcho = try await database.write { db -> Echo? in
            guard var echo = try Echo.fetchOne(db, key: id) else { return nil }
            echo.updateNextFireDate()
            try echo.update(db)
            return echo
        }
        if let echo = updatedEcho {
            syncLogger?.logEchoUpdate(echo)
        }
    }

    func updateEcho(
        id: String,
        isRecurring: Bool,
        intervals: [EchoInterval],
        fireDate: Int64
    ) async throws {
        let intervalsJSON: String? = {
            guard isRecurring, !intervals.isEmpty else { return nil }
            guard let data = try? JSONEncoder().encode(intervals) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        let updatedEcho = try await database.write { db -> Echo? in
            guard var echo = try Echo.fetchOne(db, key: id) else { return nil }
            echo.isRecurring = isRecurring
            echo.intervalsJSON = intervalsJSON
            echo.fireDate = fireDate
            echo.updateNextFireDate()
            try echo.update(db)
            return echo
        }
        if let echo = updatedEcho {
            syncLogger?.logEchoUpdate(echo)
        }
    }

    func acknowledgeEcho(id: String) async throws {
        let updatedEcho = try await database.write { db -> Echo? in
            guard var echo = try Echo.fetchOne(db, key: id) else { return nil }
            echo.acknowledge()
            try echo.update(db)
            return echo
        }
        if let echo = updatedEcho {
            syncLogger?.logEchoUpdate(echo)
        }
    }

    func alertEcho(id: String) async throws {
        let updatedEcho = try await database.write { db -> Echo? in
            guard var echo = try Echo.fetchOne(db, key: id) else { return nil }
            echo.alert()
            try echo.update(db)
            return echo
        }
        if let echo = updatedEcho {
            syncLogger?.logEchoUpdate(echo)
        }
    }

    // MARK: - Delete

    func deleteEcho(id: String) async throws {
        try await database.write { db in
            // Fetch the echo first to get its handleId for insight cleanup
            let echo = try Echo.fetchOne(db, key: id)
            try Echo.deleteOne(db, key: id)

            if let handleId = echo?.handleId {
                Self.dismissEchoInsights(handleId: handleId, db: db)
                try Self.recomputeScoresForHandle(handleId, in: db)
            }
        }
        syncLogger?.logEchoDelete(id)
    }

    func deleteEchoesForHandle(handleId: String) async throws {
        let echoIds = try await database.write { db -> [String] in
            let ids = try Echo
                .filter(Echo.Columns.handleId == handleId)
                .fetchAll(db)
                .map(\.id)
            try Echo
                .filter(Echo.Columns.handleId == handleId)
                .deleteAll(db)

            Self.dismissEchoInsights(handleId: handleId, db: db)
            try Self.recomputeScoresForHandle(handleId, in: db)
            return ids
        }
        for echoId in echoIds {
            syncLogger?.logEchoDelete(echoId)
        }
    }

    // MARK: - Engagement Score

    /// Recompute engagement scores for all notes linked to a handle via sections.
    private static func recomputeScoresForHandle(_ handleId: String, in db: Database) throws {
        let noteIds = try Row.fetchAll(db, sql: """
            SELECT DISTINCT noteId FROM sections WHERE handleId = ? AND deletedAt IS NULL
        """, arguments: [handleId]).compactMap { $0["noteId"] as String? }
        for noteId in noteIds {
            try DatabaseManager.recomputeEngagementScore(noteId: noteId, in: db)
        }
    }

    // MARK: - Insight Cleanup

    /// Dismiss upcomingEcho insights whose sourceSectionId matches a section on this handle.
    private static func dismissEchoInsights(handleId: String, db: Database) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        // Find sections belonging to this handle
        let sectionIds = (try? Section
            .filter(Section.Columns.handleId == handleId)
            .fetchAll(db)
            .map(\.id)) ?? []

        guard !sectionIds.isEmpty else { return }

        for sectionId in sectionIds {
            try? db.execute(sql: """
                UPDATE insights
                SET status = 'dismissed', updatedAt = ?
                WHERE insightType = 'upcomingEcho' AND sourceSectionId = ? AND status != 'dismissed'
            """, arguments: [now, sectionId])
        }
    }
}
