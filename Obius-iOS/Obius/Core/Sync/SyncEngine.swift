import Foundation
import Combine
import GRDB
#if os(iOS)
import UIKit
#endif

/// Manages synchronization between local SQLite and Supabase
actor SyncEngine {
    private let database: DatabaseManager
    private let supabase: SupabaseManager
    private let networkMonitor: NetworkMonitor

    private var isSyncing = false
    private var pendingSync = false
    private var lastSyncTimestamp: Date?
    private var deviceId: String?

    // Published state (use MainActor for UI updates)
    @MainActor @Published private(set) var syncState: SyncState = .idle
    @MainActor @Published private(set) var lastSyncDate: Date?
    @MainActor @Published private(set) var pendingChangesCount: Int = 0

    enum SyncState: Equatable {
        case idle
        case syncing
        case error(String)
        case offline
    }

    init(database: DatabaseManager, supabase: SupabaseManager = .shared, networkMonitor: NetworkMonitor = .shared) {
        self.database = database
        self.supabase = supabase
        self.networkMonitor = networkMonitor
    }

    // MARK: - Public API

    /// Initialize sync engine (call on app launch)
    func initialize() async {
        // Get or create device ID
        deviceId = await getOrCreateDeviceId()

        // Load last sync timestamp
        lastSyncTimestamp = await getLastSyncTimestamp()

        // Update pending changes count
        await updatePendingCount()
    }

    /// Trigger a sync cycle
    func sync() async {
        guard !isSyncing else {
            pendingSync = true
            return
        }

        guard networkMonitor.isConnected else {
            await MainActor.run { syncState = .offline }
            return
        }

        guard supabase.isAuthenticated else {
            await MainActor.run { syncState = .error("Not authenticated") }
            return
        }

        isSyncing = true
        await MainActor.run { syncState = .syncing }

        defer {
            isSyncing = false
            if pendingSync {
                pendingSync = false
                Task { await sync() }
            }
        }

        do {
            // 1. Pull remote changes
            try await pullChanges()

            // 2. Push local changes
            try await pushChanges()

            // 3. Update sync state
            await MainActor.run {
                syncState = .idle
                lastSyncDate = Date()
            }

            await updatePendingCount()

        } catch {
            print("Sync error: \(error)")
            await MainActor.run {
                syncState = .error(error.localizedDescription)
            }
        }
    }

    /// Request AI-generated title and summary for a note
    func generateSummary(noteId: String) async throws -> (title: String, summary: String) {
        guard networkMonitor.isConnected else {
            throw SyncError.offline
        }

        let request = SummaryRequest(noteId: noteId)
        let response: SummaryResponse = try await supabase.invokeFunction("generate-summary", body: request)

        if !response.success, let error = response.error {
            throw SyncError.aiError(error)
        }

        // Update local note with AI title
        try await database.write { db in
            try db.execute(sql: """
                UPDATE notes SET aiTitle = ?, syncStatus = 'pending' WHERE id = ?
            """, arguments: [response.title, noteId])
        }

        return (response.title, response.summary)
    }

    /// Perform semantic search
    func semanticSearch(query: String, limit: Int = 20) async throws -> [SemanticSearchResult] {
        guard networkMonitor.isConnected else {
            throw SyncError.offline
        }

        let request = SemanticSearchRequest(query: query, limit: limit, threshold: 0.7)
        let response: SemanticSearchResponse = try await supabase.invokeFunction("semantic-search", body: request)

        return response.results
    }

    /// Generate embeddings for sections
    func generateEmbeddings(sectionIds: [String]) async throws {
        guard networkMonitor.isConnected else {
            throw SyncError.offline
        }

        let requests = sectionIds.map { EmbeddingRequest(sectionId: $0, content: nil) }
        let _: EmbeddingResponse = try await supabase.invokeFunction("generate-embedding", body: requests)
    }

    // MARK: - Pull Changes

    private func pullChanges() async throws {
        guard let deviceId = deviceId else {
            throw SyncError.notInitialized
        }

        let timestamp = lastSyncTimestamp ?? Date(timeIntervalSince1970: 0)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let request = SyncPullRequest(
            deviceId: deviceId,
            lastSyncTimestamp: formatter.string(from: timestamp),
            knownVersions: nil // Could optimize by sending known versions
        )

        let response: SyncPullResponse = try await supabase.invokeFunction("sync-pull", body: request)

        // Apply changes to local database
        try await applyPulledChanges(response)

        // Update last sync timestamp
        if let serverTimestamp = formatter.date(from: response.serverTimestamp) {
            lastSyncTimestamp = serverTimestamp
            await saveLastSyncTimestamp(serverTimestamp)
        }

        // If there are more changes, pull again
        if response.hasMore {
            try await pullChanges()
        }
    }

    private func applyPulledChanges(_ response: SyncPullResponse) async throws {
        try await database.write { db in
            // Apply note updates/creates
            for remoteNote in response.notes {
                let localNote = remoteNote.toLocal()

                // Check if exists locally
                if let existing = try Note.fetchOne(db, key: localNote.id) {
                    // Only update if server version is newer
                    if (existing.serverVersion ?? 0) < localNote.localVersion {
                        try localNote.update(db)
                    }
                } else {
                    try localNote.insert(db)
                }
            }

            // Apply handle updates/creates (Handle Loop support)
            if let remoteHandles = response.handles {
                for remoteHandle in remoteHandles {
                    let localHandle = remoteHandle.toLocal()

                    if let existing = try Handle.fetchOne(db, key: localHandle.id) {
                        if (existing.serverVersion ?? 0) < localHandle.localVersion {
                            try localHandle.update(db)
                        }
                    } else {
                        try localHandle.insert(db)
                    }
                }
            }

            // Apply section updates/creates
            for remoteSection in response.sections {
                let localSection = remoteSection.toLocal()

                if let existing = try Section.fetchOne(db, key: localSection.id) {
                    if (existing.serverVersion ?? 0) < localSection.localVersion {
                        try localSection.update(db)
                    }
                } else {
                    try localSection.insert(db)
                }
            }

            // Apply deletions
            for noteId in response.deletedNoteIds {
                try db.execute(sql: """
                    UPDATE notes SET deletedAt = ?, syncStatus = 'synced'
                    WHERE id = ? AND deletedAt IS NULL
                """, arguments: [Int64(Date().timeIntervalSince1970 * 1000), noteId])
            }

            for sectionId in response.deletedSectionIds {
                try db.execute(sql: """
                    UPDATE sections SET deletedAt = ?, syncStatus = 'synced'
                    WHERE id = ? AND deletedAt IS NULL
                """, arguments: [Int64(Date().timeIntervalSince1970 * 1000), sectionId])
            }

            // Apply handle deletions (Handle Loop support)
            if let deletedHandleIds = response.deletedHandleIds {
                for handleId in deletedHandleIds {
                    try db.execute(sql: """
                        UPDATE handles SET deletedAt = ?, syncStatus = 'synced'
                        WHERE id = ? AND deletedAt IS NULL
                    """, arguments: [Int64(Date().timeIntervalSince1970 * 1000), handleId])

                    // Also unlink any sections from deleted handles
                    try db.execute(sql: """
                        UPDATE sections SET handleId = NULL
                        WHERE handleId = ?
                    """, arguments: [handleId])
                }
            }
        }
    }

    // MARK: - Push Changes

    private func pushChanges() async throws {
        guard let deviceId = deviceId else {
            throw SyncError.notInitialized
        }

        // Get pending operations using raw SQL for compatibility
        let operations = try await database.read { db in
            try SyncOperationRecord.fetchAll(db, sql: """
                SELECT * FROM syncOperations 
                WHERE synced = 0 
                ORDER BY timestamp 
                LIMIT 100
            """)
        }

        guard !operations.isEmpty else { return }

        // Convert to DTOs
        let operationDTOs = operations.map { op -> SyncOperationDTO in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            return SyncOperationDTO(
                operationId: op.operationId,
                entityType: op.entityType,
                entityId: op.entityId,
                operation: op.operationType,
                payload: parsePayload(op.payload),
                clientTimestamp: formatter.string(from: Date(timeIntervalSince1970: Double(op.timestamp) / 1000)),
                clientVersion: 1 // TODO: Track actual version
            )
        }

        let request = SyncPushRequest(deviceId: deviceId, operations: operationDTOs)
        let response: SyncPushResponse = try await supabase.invokeFunction("sync-push", body: request)

        // Mark accepted operations as synced
        try await database.write { db in
            for operationId in response.accepted {
                try db.execute(sql: """
                    UPDATE syncOperations SET synced = 1 WHERE operationId = ?
                """, arguments: [operationId])
            }

            // Update entities that were synced
            for operationId in response.accepted {
                if let op = operations.first(where: { $0.operationId == operationId }) {
                    let table: String
                    switch op.entityType {
                    case "note": table = "notes"
                    case "section": table = "sections"
                    case "handle": table = "handles"  // Handle Loop support
                    default: table = "sections"
                    }
                    try db.execute(sql: """
                        UPDATE \(table) SET syncStatus = 'synced' WHERE id = ?
                    """, arguments: [op.entityId])
                }
            }
        }

        // Handle conflicts
        for conflict in response.conflicts {
            try await handleConflict(conflict)
        }

        // If there are more pending operations, push again
        let remainingCount = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncOperations WHERE synced = 0") ?? 0
        }

        if remainingCount > 0 {
            try await pushChanges()
        }
    }

    private func handleConflict(_ conflict: ConflictInfo) async throws {
        // For now, just mark as conflict for user resolution
        try await database.write { db in
            let table: String
            switch conflict.entityType {
            case "note": table = "notes"
            case "section": table = "sections"
            case "handle": table = "handles"  // Handle Loop support
            default: table = "sections"
            }
            try db.execute(sql: """
                UPDATE \(table) SET syncStatus = 'conflict' WHERE id = ?
            """, arguments: [conflict.entityId])
        }

        // If server wins and we have merged entity, apply it
        if conflict.resolution == "server_wins", let merged = conflict.mergedEntity {
            // TODO: Apply merged entity to local database
        }
    }

    // MARK: - Helpers

    private func getOrCreateDeviceId() async -> String {
        // Try to get from database
        if let existing = try? await database.read({ db in
            try String.fetchOne(db, sql: "SELECT deviceId FROM syncMetadata WHERE id = 'singleton'")
        }) {
            // Register device with Supabase if authenticated
            if supabase.isAuthenticated {
                await registerDevice(existing)
            }
            return existing
        }

        // Create new device ID
        let newId = UUID().uuidString

        try? await database.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO syncMetadata (id, deviceId, lastSyncTimestamp, schemaVersion)
                VALUES ('singleton', ?, 0, 1)
            """, arguments: [newId])
        }

        if supabase.isAuthenticated {
            await registerDevice(newId)
        }

        return newId
    }

    private func registerDevice(_ deviceId: String) async {
        guard let userId = supabase.currentUser?.id else { return }

        #if os(iOS)
        let deviceName = await UIDevice.current.name
        #else
        let deviceName = Host.current().localizedName ?? "Mac"
        #endif
        
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        
        do {
            try await supabase.client.from("devices")
                .upsert([
                    "id": deviceId,
                    "user_id": userId.uuidString,
                    "device_name": deviceName,
                    "platform": "ios",
                    "app_version": appVersion
                ])
                .execute()
        } catch {
            print("Failed to register device: \(error)")
        }
    }

    private func getLastSyncTimestamp() async -> Date? {
        try? await database.read { db in
            if let timestamp = try Int64.fetchOne(db, sql: "SELECT lastSyncTimestamp FROM syncMetadata WHERE id = 'singleton'"),
               timestamp > 0 {
                return Date(timeIntervalSince1970: Double(timestamp) / 1000)
            }
            return nil
        }
    }

    private func saveLastSyncTimestamp(_ date: Date) async {
        try? await database.write { db in
            try db.execute(sql: """
                UPDATE syncMetadata SET lastSyncTimestamp = ? WHERE id = 'singleton'
            """, arguments: [Int64(date.timeIntervalSince1970 * 1000)])
        }
    }

    @MainActor
    private func updatePendingCount() async {
        let count = (try? await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncOperations WHERE synced = 0") ?? 0
        }) ?? 0

        pendingChangesCount = count
    }

    private func parsePayload(_ jsonString: String) -> [String: AnyCodable] {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict.mapValues { AnyCodable($0) }
    }
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case notInitialized
    case offline
    case aiError(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Sync engine not initialized"
        case .offline:
            return "No internet connection"
        case .aiError(let message):
            return "AI error: \(message)"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

// MARK: - Sync Operation Record (for reading from DB)

struct SyncOperationRecord: Decodable, FetchableRecord, TableRecord {
    static let databaseTableName = "syncOperations"
    
    let id: Int64?
    let operationId: String
    let entityType: String
    let entityId: String
    let operationType: String
    let payload: String
    let timestamp: Int64
    let synced: Bool
    
    enum Columns: String, ColumnExpression {
        case id, operationId, entityType, entityId
        case operationType, payload, timestamp, synced
    }
}

// Extension to enable filtering
extension SyncOperationRecord {
    static func pendingOperations(db: Database) throws -> [SyncOperationRecord] {
        try SyncOperationRecord.fetchAll(db, sql: """
            SELECT * FROM syncOperations 
            WHERE synced = 0 
            ORDER BY timestamp
        """)
    }
}
