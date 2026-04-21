import Foundation
import GRDB

struct CalendarMemo: Codable, Identifiable, Hashable {
    var id: String
    var dateKey: String           // Format: "YYYY-M-D" (e.g. "2026-4-7")
    var content: String
    var createdAt: Int64
    var updatedAt: Int64
    var localVersion: Int
    var serverVersion: Int?
    var syncStatus: SyncStatus

    init(
        id: String = UUID().uuidString,
        dateKey: String,
        content: String = "",
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        localVersion: Int = 1,
        serverVersion: Int? = nil,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.dateKey = dateKey
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.localVersion = localVersion
        self.serverVersion = serverVersion
        self.syncStatus = syncStatus
    }

    mutating func touch() {
        updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        localVersion += 1
        syncStatus = .pending
    }
}

// MARK: - GRDB Conformance

extension CalendarMemo: FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendarMemos"

    enum Columns: String, ColumnExpression {
        case id, dateKey, content, createdAt, updatedAt
        case localVersion, serverVersion, syncStatus
    }
}
