import Foundation
import GRDB

struct Note: Codable, Identifiable, Hashable {
    var id: String
    var title: String?
    var aiTitle: String?
    var body: String  // Direct note content (before any sections)
    var interstitialContent: [String: String]  // Text between sections, keyed by "after_<sectionId>" or "end"
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?
    var isPinned: Bool
    var intent: IntentType  // Renamed from colorIntent

    // Sync fields
    var localVersion: Int
    var serverVersion: Int?
    var syncStatus: SyncStatus
    var lastSyncedAt: Int64?

    init(
        id: String = UUID().uuidString,
        title: String? = nil,
        aiTitle: String? = nil,
        body: String = "",
        interstitialContent: [String: String] = [:],
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        deletedAt: Int64? = nil,
        isPinned: Bool = false,
        intent: IntentType = .idea,
        localVersion: Int = 1,
        serverVersion: Int? = nil,
        syncStatus: SyncStatus = .pending,
        lastSyncedAt: Int64? = nil
    ) {
        self.id = id
        self.title = title
        self.aiTitle = aiTitle
        self.body = body
        self.interstitialContent = interstitialContent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isPinned = isPinned
        self.intent = intent
        self.localVersion = localVersion
        self.serverVersion = serverVersion
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
    }

    // Helper to get text after a specific section
    func textAfterSection(_ sectionId: String) -> String {
        interstitialContent["after_\(sectionId)"] ?? ""
    }

    // Helper to get text at the end (after all sections)
    var endText: String {
        interstitialContent["end"] ?? ""
    }
    
    var displayTitle: String {
        title ?? aiTitle ?? "Untitled"
    }
    
    var isDeleted: Bool {
        deletedAt != nil
    }
    
    var createdDate: Date {
        Date(timeIntervalSince1970: Double(createdAt) / 1000)
    }
    
    var updatedDate: Date {
        Date(timeIntervalSince1970: Double(updatedAt) / 1000)
    }
}

// MARK: - GRDB Conformance

extension Note: FetchableRecord, PersistableRecord {
    static let databaseTableName = "notes"
    
    enum Columns: String, ColumnExpression {
        case id, title, aiTitle, body, interstitialContent, createdAt, updatedAt, deletedAt
        case isPinned, intent, localVersion, serverVersion
        case syncStatus, lastSyncedAt
    }
    
    // Relationship to sections
    static let sections = hasMany(Section.self)
    
    var sections: QueryInterfaceRequest<Section> {
        request(for: Note.sections)
            .filter(Section.Columns.deletedAt == nil)
            .order(Section.Columns.orderKey)
    }
}

// MARK: - Mutations

extension Note {
    mutating func touch() {
        updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        localVersion += 1
        syncStatus = .pending
    }
    
    mutating func softDelete() {
        deletedAt = Int64(Date().timeIntervalSince1970 * 1000)
        touch()
    }
    
    mutating func setIntent(_ newIntent: IntentType) {
        intent = newIntent
        touch()
    }
}
