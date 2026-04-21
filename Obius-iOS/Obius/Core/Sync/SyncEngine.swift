import Foundation
import Combine
import GRDB
import Supabase
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
    /// Consecutive sync failure count — reset on success, caps auto-retry
    private var consecutiveFailures = 0
    private let maxAutoRetries = 2

    // Realtime subscription
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?
    private var debouncedSyncTask: Task<Void, Never>?
    private var lastPushTime: Date = .distantPast
    // Periodic pull fallback (in case realtime events are missed)
    private var periodicPullTask: Task<Void, Never>?

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

        // One-time: enqueue all local notes/sections that have never been synced
        await enqueueUnsyncedEntities()

        // Update pending changes count
        await updatePendingCount()
    }

    /// Enqueue sync operations for any local entities that were created before
    /// sync was working. Runs once — subsequent launches skip already-queued items.
    private func enqueueUnsyncedEntities() async {
        guard let deviceId = deviceId else { return }

        do {
            // Clean up any leftover ghost modules
            try? await database.write { db in
                try db.execute(sql: "DELETE FROM modules WHERE name = 'Synced Project'")
            }

            // Debug: show database state
            let dbStats = try? await database.read { db -> (Int, Int, Int, Int) in
                let totalNotes = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes WHERE deletedAt IS NULL") ?? 0
                let totalSections = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sections WHERE deletedAt IS NULL") ?? 0
                let existingOps = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncOperations") ?? 0
                let cloudNotes = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes WHERE syncStatus = 'synced' AND deletedAt IS NULL") ?? 0
                return (totalNotes, totalSections, existingOps, cloudNotes)
            }
            if let (notes, sections, ops, synced) = dbStats {
                print("[Sync] Database state: \(notes) notes (\(synced) marked synced), \(sections) sections, \(ops) existing syncOperations")
            }

            // Nuclear reset: delete all old syncOperations and re-enqueue everything.
            let resetKey = "hasResetSyncOps_v24"
            if !UserDefaults.standard.bool(forKey: resetKey) {
                // Delete sync operations in its own transaction
                try? await database.write { db in
                    let deleteCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncOperations") ?? 0
                    if deleteCount > 0 {
                        try db.execute(sql: "DELETE FROM syncOperations")
                        print("[Sync] Deleted \(deleteCount) old syncOperations — will re-enqueue all entities")
                    }
                }
                // Reset sync timestamp separately (column may not exist in older DBs)
                try? await database.write { db in
                    // Add column if missing, then clear it
                    try? db.execute(sql: "ALTER TABLE syncMetadata ADD COLUMN lastSyncTimestamp TEXT")
                    try db.execute(sql: "UPDATE syncMetadata SET lastSyncTimestamp = NULL")
                }
                // Clear inflated serverVersion values — they were incorrectly set from localVersion
                // instead of the server's actual version. The pull will set them correctly.
                try? await database.write { db in
                    try db.execute(sql: "UPDATE notes SET serverVersion = NULL WHERE serverVersion > 0")
                    try db.execute(sql: "UPDATE sections SET serverVersion = NULL WHERE serverVersion > 0")
                    try db.execute(sql: "UPDATE handles SET serverVersion = NULL WHERE serverVersion > 0")
                    try db.execute(sql: "UPDATE echoes SET serverVersion = NULL WHERE serverVersion > 0")
                    print("[Sync] Cleared inflated serverVersion values — pull will set correct versions")
                }
                lastSyncTimestamp = nil
                UserDefaults.standard.set(true, forKey: resetKey)
            }

            try await database.write { db in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                // Find ALL notes that don't have a pending or completed syncOperation
                // Join with modules to include project name/icon for cross-device sync
                // Skip notes created in the last 60 seconds (user may still be editing)
                let sixtySecondsAgo = Int64(Date().timeIntervalSince1970 * 1000) - 60_000
                let unsyncedNotes = try Row.fetchAll(db, sql: """
                    SELECT n.id, n.title, n.body, n.bodyRichText, n.interstitialContent, n.interstitialRichContent,
                           n.isPinned, n.intent, n.createdAt, n.updatedAt, n.moduleId, n.groupName,
                           m.name AS moduleName, m.icon AS moduleIcon
                    FROM notes n
                    LEFT JOIN modules m ON m.id = n.moduleId
                    WHERE n.deletedAt IS NULL
                    AND n.createdAt < ?
                    AND n.syncStatus != 'synced'
                    AND NOT EXISTS (
                        SELECT 1 FROM syncOperations so
                        WHERE so.entityId = n.id
                    )
                """, arguments: [sixtySecondsAgo])

                for note in unsyncedNotes {
                    let noteId = note["id"] as? String ?? ""
                    let noteTitle = note["title"] as? String ?? "(untitled)"
                    let noteBody = note["body"] as? String ?? ""
                    print("[Sync] Enqueuing unsynced note: \(noteId.prefix(8)) title='\(noteTitle)' body=\(noteBody.count) chars")
                    let timestamp = note["updatedAt"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)

                    let isPinned: Bool = {
                        if let b = note["isPinned"] as? Bool { return b }
                        if let i = note["isPinned"] as? Int64 { return i != 0 }
                        if let i = note["isPinned"] as? Int { return i != 0 }
                        return false
                    }()

                    var payload: [String: Any] = [
                        "title": note["title"] as? String ?? NSNull(),
                        "body": note["body"] as? String ?? "",
                        "is_pinned": isPinned,
                        "color_intent": (note["intent"] as? String) ?? "idea",
                        "module_id": note["moduleId"] as? String ?? NSNull(),
                        "interstitial_content": note["interstitialContent"] as? String ?? "{}",
                        "interstitial_rich_content": note["interstitialRichContent"] as? String ?? "{}",
                        "created_at": formatter.string(from: Date(timeIntervalSince1970: Double(note["createdAt"] as? Int64 ?? 0) / 1000)),
                        "updated_at": formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000)),
                    ]
                    if let bodyRichText = note["bodyRichText"] as? String {
                        payload["body_rich_text"] = bodyRichText
                    }
                    if let groupName = note["groupName"] as? String {
                        payload["group_name"] = groupName
                    }
                    if let moduleName = note["moduleName"] as? String {
                        payload["module_name"] = moduleName
                    }
                    if let moduleIcon = note["moduleIcon"] as? String {
                        payload["module_icon"] = moduleIcon
                    }

                    let payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

                    try db.execute(sql: """
                        INSERT OR IGNORE INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                        VALUES (?, 'note', ?, 'create', ?, ?, 0)
                    """, arguments: [UUID().uuidString, noteId, payloadString, timestamp])
                }

                // Find ALL sections that don't have a pending or completed syncOperation
                let unsyncedSections = try Row.fetchAll(db, sql: """
                    SELECT s.id, s.noteId, s.content, s.contentType, s.parentSectionId,
                           s.orderKey, s.indentLevel, s.isCollapsed, s.intent, s.handleId,
                           s.createdAt, s.updatedAt
                    FROM sections s
                    WHERE s.deletedAt IS NULL
                    AND s.syncStatus != 'synced'
                    AND NOT EXISTS (
                        SELECT 1 FROM syncOperations so
                        WHERE so.entityId = s.id
                    )
                """)

                for section in unsyncedSections {
                    let sectionId = section["id"] as? String ?? ""
                    let timestamp = section["updatedAt"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)

                    let isCollapsed: Bool = {
                        if let b = section["isCollapsed"] as? Bool { return b }
                        if let i = section["isCollapsed"] as? Int64 { return i != 0 }
                        if let i = section["isCollapsed"] as? Int { return i != 0 }
                        return false
                    }()

                    let payload: [String: Any] = [
                        "note_id": section["noteId"] as? String ?? "",
                        "content": section["content"] as? String ?? "",
                        "content_type": section["contentType"] as? String ?? "text",
                        "parent_section_id": section["parentSectionId"] as? String ?? NSNull(),
                        "order_key": section["orderKey"] as? String ?? "a",
                        "indent_level": Int(truncating: section["indentLevel"] as? NSNumber ?? 0),
                        "is_collapsed": isCollapsed,
                        "color_intent": section["intent"] as? String ?? NSNull(),
                        "handle_id": section["handleId"] as? String ?? NSNull(),
                        "created_at": formatter.string(from: Date(timeIntervalSince1970: Double(section["createdAt"] as? Int64 ?? 0) / 1000)),
                        "updated_at": formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000)),
                    ]

                    let payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

                    try db.execute(sql: """
                        INSERT OR IGNORE INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                        VALUES (?, 'section', ?, 'create', ?, ?, 0)
                    """, arguments: [UUID().uuidString, sectionId, payloadString, timestamp])
                }

                // Find ALL handles that don't have a pending or completed syncOperation
                let unsyncedHandles = try Row.fetchAll(db, sql: """
                    SELECT h.id, h.name, h.displayName, h.content, h.intent,
                           h.createdAt, h.updatedAt
                    FROM handles h
                    WHERE h.deletedAt IS NULL
                    AND h.syncStatus != 'synced'
                    AND NOT EXISTS (
                        SELECT 1 FROM syncOperations so
                        WHERE so.entityId = h.id
                    )
                """)

                for handle in unsyncedHandles {
                    let handleId = handle["id"] as? String ?? ""
                    let timestamp = handle["updatedAt"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)

                    let payload: [String: Any] = [
                        "name": handle["name"] as? String ?? "",
                        "display_name": handle["displayName"] as? String ?? "",
                        "content": handle["content"] as? String ?? "",
                        "intent": handle["intent"] as? String ?? "idea",
                        "created_at": formatter.string(from: Date(timeIntervalSince1970: Double(handle["createdAt"] as? Int64 ?? 0) / 1000)),
                        "updated_at": formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000)),
                    ]

                    let payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

                    try db.execute(sql: """
                        INSERT OR IGNORE INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                        VALUES (?, 'handle', ?, 'create', ?, ?, 0)
                    """, arguments: [UUID().uuidString, handleId, payloadString, timestamp])
                }

                // Find ALL echoes that don't have a pending or completed syncOperation
                let unsyncedEchoes = try Row.fetchAll(db, sql: """
                    SELECT e.id, e.handleId, e.isRecurring, e.intervalsJSON,
                           e.fireDate, e.isActive, e.nextFireDate, e.isAlerted,
                           e.lastAcknowledgedAt, e.createdAt, e.updatedAt
                    FROM echoes e
                    WHERE e.syncStatus != 'synced'
                    AND NOT EXISTS (
                        SELECT 1 FROM syncOperations so
                        WHERE so.entityId = e.id
                    )
                """)

                for echo in unsyncedEchoes {
                    let echoId = echo["id"] as? String ?? ""
                    let timestamp = echo["updatedAt"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)

                    let isRecurring: Bool = {
                        if let b = echo["isRecurring"] as? Bool { return b }
                        if let i = echo["isRecurring"] as? Int64 { return i != 0 }
                        if let i = echo["isRecurring"] as? Int { return i != 0 }
                        return false
                    }()

                    let isActive: Bool = {
                        if let b = echo["isActive"] as? Bool { return b }
                        if let i = echo["isActive"] as? Int64 { return i != 0 }
                        if let i = echo["isActive"] as? Int { return i != 0 }
                        return true
                    }()

                    let isAlerted: Bool = {
                        if let b = echo["isAlerted"] as? Bool { return b }
                        if let i = echo["isAlerted"] as? Int64 { return i != 0 }
                        if let i = echo["isAlerted"] as? Int { return i != 0 }
                        return false
                    }()

                    var payload: [String: Any] = [
                        "handle_id": echo["handleId"] as? String ?? "",
                        "is_recurring": isRecurring,
                        "fire_date": echo["fireDate"] as? Int64 ?? 0,
                        "is_active": isActive,
                        "is_alerted": isAlerted,
                        "created_at": formatter.string(from: Date(timeIntervalSince1970: Double(echo["createdAt"] as? Int64 ?? 0) / 1000)),
                        "updated_at": formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000)),
                    ]

                    if let intervalsJSON = echo["intervalsJSON"] as? String {
                        payload["intervals_json"] = intervalsJSON
                    }
                    if let nextFireDate = echo["nextFireDate"] as? Int64 {
                        payload["next_fire_date"] = nextFireDate
                    }
                    if let lastAck = echo["lastAcknowledgedAt"] as? Int64 {
                        payload["last_acknowledged_at"] = lastAck
                    }

                    let payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

                    try db.execute(sql: """
                        INSERT OR IGNORE INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                        VALUES (?, 'echo', ?, 'create', ?, ?, 0)
                    """, arguments: [UUID().uuidString, echoId, payloadString, timestamp])
                }

                // Find ALL calendar memos that don't have a pending or completed syncOperation
                let unsyncedMemos = try Row.fetchAll(db, sql: """
                    SELECT m.id, m.dateKey, m.content, m.createdAt, m.updatedAt
                    FROM calendarMemos m
                    WHERE m.syncStatus != 'synced'
                    AND NOT EXISTS (
                        SELECT 1 FROM syncOperations so
                        WHERE so.entityId = m.id
                    )
                """)

                for memo in unsyncedMemos {
                    let memoId = memo["id"] as? String ?? ""
                    let timestamp = memo["updatedAt"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)

                    let payload: [String: Any] = [
                        "date_key": memo["dateKey"] as? String ?? "",
                        "content": memo["content"] as? String ?? "",
                        "created_at": formatter.string(from: Date(timeIntervalSince1970: Double(memo["createdAt"] as? Int64 ?? 0) / 1000)),
                        "updated_at": formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000)),
                    ]

                    let payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

                    try db.execute(sql: """
                        INSERT OR IGNORE INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                        VALUES (?, 'calendar_memo', ?, 'create', ?, ?, 0)
                    """, arguments: [UUID().uuidString, memoId, payloadString, timestamp])
                }

                let noteCount = unsyncedNotes.count
                let sectionCount = unsyncedSections.count
                let handleCount = unsyncedHandles.count
                let echoCount = unsyncedEchoes.count
                let memoCount = unsyncedMemos.count
                if noteCount > 0 || sectionCount > 0 || handleCount > 0 || echoCount > 0 || memoCount > 0 {
                    print("[Sync] Enqueued \(noteCount) notes, \(sectionCount) sections, \(handleCount) handles, \(echoCount) echoes, and \(memoCount) calendar memos for initial sync")
                }
            }
        } catch {
            print("[Sync] Error enqueuing unsynced entities: \(error)")
        }
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
            // 0. Verify we have a valid session before syncing
            if let session = supabase.currentSession {
                print("[Sync] Current session expires: \(Date(timeIntervalSince1970: session.expiresAt))")
            } else {
                print("[Sync] No current session — aborting sync")
                await MainActor.run { syncState = .error("Not authenticated") }
                return
            }

            // 1. Push local changes first so the server sees our edits
            //    before we pull (prevents pull from overwriting unsaved local work)
            do {
                try await pushChanges()
            } catch {
                print("[Sync] Push failed (will still attempt pull): \(error)")
            }

            // 2. Pull remote changes
            try await pullChanges()

            // 3. Post-sync: fix orphaned notes and clean up empty modules
            await cleanupOrphanedModules()

            // 4. Update sync state
            consecutiveFailures = 0
            await MainActor.run {
                syncState = .idle
                lastSyncDate = Date()
            }

            await updatePendingCount()

        } catch {
            consecutiveFailures += 1
            let classified = EdgeFunctionError.classify(error)
            print("[Sync] Error (\(consecutiveFailures)/\(maxAutoRetries)): \(classified.localizedDescription ?? error.localizedDescription)")

            switch classified {
            case .unauthorized:
                // Session expired — notify user to re-auth, don't retry
                print("[Sync] Session expired — user must re-authenticate")
                await MainActor.run { syncState = .error("Session expired. Please sign in again.") }

            case .rateLimited:
                // Back off — schedule retry after delay (capped)
                if consecutiveFailures <= maxAutoRetries {
                    print("[Sync] Rate limited — will retry in 30 seconds")
                    await MainActor.run { syncState = .error("Rate limited. Retrying shortly.") }
                    Task {
                        try? await Task.sleep(nanoseconds: 30_000_000_000)
                        await sync()
                    }
                } else {
                    print("[Sync] Rate limited — max retries reached")
                    await MainActor.run { syncState = .error("Rate limited. Try again later.") }
                }

            case .serverError(let code):
                // Server issue — retry with cap
                if consecutiveFailures <= maxAutoRetries {
                    print("[Sync] Server error \(code) — will retry in 5 seconds")
                    await MainActor.run { syncState = .error("Server error. Retrying...") }
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        await sync()
                    }
                } else {
                    print("[Sync] Server error \(code) — max retries reached")
                    await MainActor.run { syncState = .error("Server error (\(code)). Try again later.") }
                }

            case .timeout:
                // Timeout — retry with cap
                if consecutiveFailures <= maxAutoRetries {
                    print("[Sync] Timeout — will retry in 5 seconds")
                    await MainActor.run { syncState = .error("Request timed out. Retrying...") }
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        await sync()
                    }
                } else {
                    print("[Sync] Timeout — max retries reached")
                    await MainActor.run { syncState = .error("Request timed out. Try again later.") }
                }

            case .networkFailure:
                print("[Sync] Network unavailable")
                await MainActor.run { syncState = .offline }

            case .forbidden:
                // Tier/permission issue — don't retry
                print("[Sync] Forbidden — feature may require upgrade")
                await MainActor.run { syncState = .error("Cloud sync requires a paid plan.") }

            case .httpError(let code, let body):
                print("[Sync] HTTP \(code): \(body)")
                await MainActor.run { syncState = .error(classified.localizedDescription ?? "Sync failed") }
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
        let allowed = await MainActor.run { TierManager.shared.limits.semanticSearch }
        guard allowed else {
            await MainActor.run {
                TierManager.shared.paywallFeature = .semanticSearch
                TierManager.shared.showPaywall = true
            }
            throw SyncError.offline
        }
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
        print("[Sync] Pulling changes since \(formatter.string(from: timestamp))")

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
            // Temporarily disable FK checks so sections can arrive before/without their parent notes
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            defer { try? db.execute(sql: "PRAGMA foreign_keys = ON") }

            // Clean up any leftover "Synced Project" ghost modules
            try db.execute(sql: "DELETE FROM modules WHERE name = 'Synced Project'")

            // One-time cleanup: remove lowercase UUID duplicates created by case mismatch bug.
            // PostgreSQL returns lowercase UUIDs but local UUIDs are uppercase, causing duplicates.
            let dupeCleanupKey = "hasCleanedLowercaseDupes_v1"
            if !UserDefaults.standard.bool(forKey: dupeCleanupKey) {
                // Delete notes whose id is all-lowercase AND an uppercase version exists
                let lowercaseNotes = try String.fetchAll(db, sql: """
                    SELECT id FROM notes WHERE id != UPPER(id)
                    AND EXISTS (SELECT 1 FROM notes n2 WHERE n2.id = UPPER(notes.id))
                """)
                for dupeId in lowercaseNotes {
                    // Delete sections belonging to the lowercase duplicate
                    try db.execute(sql: "DELETE FROM sections WHERE noteId = ?", arguments: [dupeId])
                    try db.execute(sql: "DELETE FROM notes WHERE id = ?", arguments: [dupeId])
                }
                // Also clean up orphaned lowercase sections
                let lowercaseSections = try String.fetchAll(db, sql: """
                    SELECT id FROM sections WHERE id != UPPER(id)
                    AND EXISTS (SELECT 1 FROM sections s2 WHERE s2.id = UPPER(sections.id))
                """)
                for dupeId in lowercaseSections {
                    try db.execute(sql: "DELETE FROM sections WHERE id = ?", arguments: [dupeId])
                }
                // Clean up lowercase handles
                let lowercaseHandles = try String.fetchAll(db, sql: """
                    SELECT id FROM handles WHERE id != UPPER(id)
                    AND EXISTS (SELECT 1 FROM handles h2 WHERE h2.id = UPPER(handles.id))
                """)
                for dupeId in lowercaseHandles {
                    try db.execute(sql: "DELETE FROM handles WHERE id = ?", arguments: [dupeId])
                }
                if !lowercaseNotes.isEmpty || !lowercaseSections.isEmpty || !lowercaseHandles.isEmpty {
                    print("[Sync] Cleaned up \(lowercaseNotes.count) duplicate notes, \(lowercaseSections.count) sections, \(lowercaseHandles.isEmpty ? 0 : lowercaseHandles.count) handles from UUID case mismatch")
                }
                // Also clean up syncOperations referencing lowercase IDs
                try db.execute(sql: "DELETE FROM syncOperations WHERE entityId != UPPER(entityId)")
                UserDefaults.standard.set(true, forKey: dupeCleanupKey)
            }

            // Apply note updates/creates — create missing modules from synced metadata
            print("[Sync] Pull received \(response.notes.count) notes, \(response.sections.count) sections, \((response.handles ?? []).count) handles, \((response.echoes ?? []).count) echoes")
            for remoteNote in response.notes {
                let localNote = remoteNote.toLocal()

                // Check if note already exists locally
                if let existing = try Note.fetchOne(db, key: localNote.id) {
                    // Never overwrite notes with pending local changes — push handles conflicts
                    if existing.syncStatus == .pending {
                        print("[Sync] Skipped note \(localNote.id.prefix(8)) — has pending local changes")
                        continue
                    }
                    // UPDATE path — only update if server version is newer
                    if (existing.serverVersion ?? 0) < localNote.localVersion {
                        // Preserve local-only fields not included in server data
                        var mergedNote = localNote
                        mergedNote.moduleId = localNote.moduleId ?? existing.moduleId  // Accept remote module assignment if provided
                        mergedNote.tags = existing.tags
                        mergedNote.aiTags = existing.aiTags
                        mergedNote.viewCount = existing.viewCount
                        try mergedNote.update(db)

                        // Update local module name/icon if server has a renamed module
                        if let moduleId = mergedNote.moduleId, !moduleId.isEmpty,
                           let remoteName = remoteNote.moduleName, !remoteName.isEmpty {
                            let localModuleName = try String.fetchOne(db, sql: """
                                SELECT name FROM modules WHERE id = ? AND deletedAt IS NULL
                            """, arguments: [moduleId])
                            if let localName = localModuleName, localName != remoteName {
                                let remoteIcon = remoteNote.moduleIcon ?? "folder"
                                try db.execute(sql: """
                                    UPDATE modules SET name = ?, icon = ?, updatedAt = ? WHERE id = ?
                                """, arguments: [remoteName, remoteIcon, Int64(Date().timeIntervalSince1970 * 1000), moduleId])
                                print("[Sync] Updated module name '\(localName)' → '\(remoteName)' (\(moduleId.prefix(8)))")
                            }
                        }

                        print("[Sync] Updated note \(localNote.id.prefix(8)) (v\(existing.serverVersion ?? 0) → v\(localNote.localVersion)) body=\(localNote.body.prefix(50))")
                    } else {
                        print("[Sync] Skipped note \(localNote.id.prefix(8)) (local v\(existing.serverVersion ?? 0) >= remote v\(localNote.localVersion)) body=\(localNote.body.prefix(50))")
                    }
                } else {
                    // INSERT path — new note from another device
                    // Ensure the module exists locally (remap or create as needed)
                    var noteToInsert = localNote
                    if let moduleId = localNote.moduleId, !moduleId.isEmpty {
                        let moduleExists = (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM modules WHERE id = ?", arguments: [moduleId]) ?? 0) > 0
                        if !moduleExists {
                            let moduleName = remoteNote.moduleName ?? "Synced"
                            let moduleIcon = remoteNote.moduleIcon ?? "cloud"
                            let now = Int64(Date().timeIntervalSince1970 * 1000)

                            // Check if a module with the same name already exists
                            if let existingId = try String.fetchOne(db, sql: """
                                SELECT id FROM modules WHERE name = ? AND deletedAt IS NULL
                            """, arguments: [moduleName]) {
                                // Remap to existing module with same name
                                noteToInsert.moduleId = existingId
                                print("[Sync] Remapped new note \(localNote.id.prefix(8)) to existing module '\(moduleName)' (\(existingId.prefix(8)))")
                            } else {
                                // Create the module with the server's ID
                                try db.execute(sql: """
                                    INSERT OR IGNORE INTO modules (id, name, icon, isDefault, storageType, orderIndex, createdAt, updatedAt)
                                    VALUES (?, ?, ?, 0, 'cloud', 0, ?, ?)
                                """, arguments: [moduleId, moduleName, moduleIcon, now, now])
                                print("[Sync] Created module '\(moduleName)' (\(moduleId.prefix(8))) for new note")
                            }
                        }
                    }

                    // Update existing module name/icon if the server has a newer name
                    // (handles cross-device module rename propagation)
                    if let moduleId = noteToInsert.moduleId, !moduleId.isEmpty,
                       let remoteName = remoteNote.moduleName, !remoteName.isEmpty {
                        let localModuleName = try String.fetchOne(db, sql: """
                            SELECT name FROM modules WHERE id = ? AND deletedAt IS NULL
                        """, arguments: [moduleId])
                        if let localName = localModuleName, localName != remoteName {
                            let remoteIcon = remoteNote.moduleIcon ?? "folder"
                            try db.execute(sql: """
                                UPDATE modules SET name = ?, icon = ?, updatedAt = ? WHERE id = ?
                            """, arguments: [remoteName, remoteIcon, Int64(Date().timeIntervalSince1970 * 1000), moduleId])
                            print("[Sync] Updated module name '\(localName)' → '\(remoteName)' (\(moduleId.prefix(8)))")
                        }
                    }
                    try noteToInsert.insert(db)
                    try DatabaseManager.recomputeEngagementScore(noteId: noteToInsert.id, in: db)
                    print("[Sync] Inserted new note \(localNote.id.prefix(8)) into module \(noteToInsert.moduleId?.prefix(8) ?? "nil")")
                }
            }

            // Apply handle updates/creates (Handle Loop support)
            if let remoteHandles = response.handles {
                for remoteHandle in remoteHandles {
                    let localHandle = remoteHandle.toLocal()

                    do {
                        if let existing = try Handle.fetchOne(db, key: localHandle.id) {
                            if existing.syncStatus == .pending {
                                print("[Sync] Skipped handle \(localHandle.id.prefix(8)) — has pending local changes")
                                continue
                            }
                            if (existing.serverVersion ?? 0) < localHandle.localVersion {
                                try localHandle.update(db)
                            }
                        } else {
                            try localHandle.insert(db)
                        }
                    } catch {
                        // Handle UNIQUE constraint on name: a local handle with the same name
                        // but different ID already exists. Update the existing one's ID to match.
                        if error.localizedDescription.contains("UNIQUE constraint failed: handles.name") {
                            if let existingByName = try? Handle
                                .filter(Column("name") == localHandle.name)
                                .fetchOne(db) {
                                // Update sections that reference the old handle ID
                                try? db.execute(sql: """
                                    UPDATE sections SET handleId = ? WHERE handleId = ?
                                """, arguments: [localHandle.id, existingByName.id])
                                // Delete the old handle and insert the server version
                                try? Handle.deleteOne(db, key: existingByName.id)
                                try? localHandle.insert(db)
                                print("[Sync] Merged duplicate handle '\(localHandle.name)' (\(existingByName.id.prefix(8)) → \(localHandle.id.prefix(8)))")
                            }
                        } else {
                            print("[Sync] Skipping handle \(localHandle.id.prefix(8)): \(error.localizedDescription)")
                        }
                    }
                }
            }

            // Apply echo updates/creates (Echo cloud sync)
            if let remoteEchoes = response.echoes {
                print("[Sync] Processing \(remoteEchoes.count) echoes from server")
                for remoteEcho in remoteEchoes {
                    let localEcho = remoteEcho.toLocal()

                    do {
                        if let existing = try Echo.fetchOne(db, key: localEcho.id) {
                            if existing.syncStatus == .pending {
                                print("[Sync] Skipped echo \(localEcho.id.prefix(8)) — has pending local changes")
                                continue
                            }
                            if (existing.serverVersion ?? 0) < localEcho.localVersion {
                                try localEcho.update(db)
                                print("[Sync] Updated echo \(localEcho.id.prefix(8)) (v\(existing.serverVersion ?? 0) → v\(localEcho.localVersion))")
                            } else {
                                print("[Sync] Echo \(localEcho.id.prefix(8)) already at v\(existing.serverVersion ?? 0), skipping")
                            }
                        } else {
                            try localEcho.insert(db)
                            print("[Sync] Inserted new echo \(localEcho.id.prefix(8)) handleId=\(localEcho.handleId.prefix(8)) isActive=\(localEcho.isActive)")
                        }
                    } catch {
                        print("[Sync] FAILED to apply echo \(localEcho.id.prefix(8)): \(error)")
                    }
                }
            } else {
                print("[Sync] No echoes in pull response (field was nil)")
            }

            // Apply calendar memo updates/creates
            if let remoteMemos = response.calendarMemos {
                for remoteMemo in remoteMemos {
                    let localMemo = remoteMemo.toLocal()
                    do {
                        if let existing = try CalendarMemo.fetchOne(db, key: localMemo.id) {
                            if existing.syncStatus == .pending { continue }
                            if (existing.serverVersion ?? 0) < localMemo.localVersion {
                                try localMemo.update(db)
                            }
                        } else {
                            // Check for existing memo with same dateKey (different ID)
                            if let byDate = try CalendarMemo
                                .filter(CalendarMemo.Columns.dateKey == localMemo.dateKey)
                                .fetchOne(db), byDate.syncStatus != .pending {
                                try byDate.delete(db)
                            }
                            try localMemo.insert(db)
                        }
                    } catch {
                        print("[Sync] Skipping calendar memo \(localMemo.id.prefix(8)): \(error.localizedDescription)")
                    }
                }
            }

            // Apply section updates/creates (skip individual failures)
            for remoteSection in response.sections {
                let localSection = remoteSection.toLocal()

                do {
                    if let existing = try Section.fetchOne(db, key: localSection.id) {
                        // Never overwrite sections with pending local changes
                        if existing.syncStatus == .pending {
                            print("[Sync] Skipped section \(localSection.id.prefix(8)) — has pending local changes")
                            continue
                        }
                        if (existing.serverVersion ?? 0) < localSection.localVersion {
                            try localSection.update(db)
                        }
                    } else {
                        try localSection.insert(db)
                    }
                } catch {
                    print("[Sync] Skipping section \(localSection.id): \(error.localizedDescription)")
                }
            }

            // Purge stale sync operations for entities just updated from the server.
            // Without this, enqueueUnsyncedEntities may have queued "create" ops with OLD data
            // that would overwrite the server's newer version during the push phase.
            // IMPORTANT: Only purge ops for entities that DON'T have pending local changes.
            let pulledNoteIds = response.notes.map { $0.id.uppercased() }
            let pulledSectionIds = response.sections.map { $0.id.uppercased() }
            let pulledHandleIds = (response.handles ?? []).map { $0.id.uppercased() }
            let pulledEchoIds = (response.echoes ?? []).map { $0.id.uppercased() }
            let pulledCalendarMemoIds = (response.calendarMemos ?? []).map { $0.id.uppercased() }
            let allPulledIds = pulledNoteIds + pulledSectionIds + pulledHandleIds + pulledEchoIds + pulledCalendarMemoIds
            if !allPulledIds.isEmpty {
                // Collect IDs of entities that still have pending local changes — don't purge their ops
                var pendingIds = Set<String>()
                for id in pulledNoteIds {
                    if let status = try String.fetchOne(db, sql: "SELECT syncStatus FROM notes WHERE id = ?", arguments: [id]),
                       status == "pending" { pendingIds.insert(id) }
                }
                for id in pulledSectionIds {
                    if let status = try String.fetchOne(db, sql: "SELECT syncStatus FROM sections WHERE id = ?", arguments: [id]),
                       status == "pending" { pendingIds.insert(id) }
                }
                for id in pulledHandleIds {
                    if let status = try String.fetchOne(db, sql: "SELECT syncStatus FROM handles WHERE id = ?", arguments: [id]),
                       status == "pending" { pendingIds.insert(id) }
                }
                for id in pulledEchoIds {
                    if let status = try String.fetchOne(db, sql: "SELECT syncStatus FROM echoes WHERE id = ?", arguments: [id]),
                       status == "pending" { pendingIds.insert(id) }
                }
                for id in pulledCalendarMemoIds {
                    if let status = try String.fetchOne(db, sql: "SELECT syncStatus FROM calendarMemos WHERE id = ?", arguments: [id]),
                       status == "pending" { pendingIds.insert(id) }
                }
                let safeToPurge = allPulledIds.filter { !pendingIds.contains($0) }
                if !safeToPurge.isEmpty {
                    let placeholders = safeToPurge.map { _ in "?" }.joined(separator: ",")
                    let deletedOps = try Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM syncOperations WHERE synced = 0 AND entityId IN (\(placeholders))
                    """, arguments: StatementArguments(safeToPurge)) ?? 0
                    if deletedOps > 0 {
                        try db.execute(sql: """
                            DELETE FROM syncOperations WHERE synced = 0 AND entityId IN (\(placeholders))
                        """, arguments: StatementArguments(safeToPurge))
                        print("[Sync] Purged \(deletedOps) stale sync operations for entities updated from server")
                    }
                }
                if !pendingIds.isEmpty {
                    print("[Sync] Preserved \(pendingIds.count) sync operations for entities with pending local changes")
                }
            }

            // Apply deletions (uppercase IDs to match local UUID format)
            for noteId in response.deletedNoteIds {
                let normalizedId = noteId.uppercased()
                try db.execute(sql: """
                    UPDATE notes SET deletedAt = ?, syncStatus = 'synced'
                    WHERE id = ? AND deletedAt IS NULL
                """, arguments: [Int64(Date().timeIntervalSince1970 * 1000), normalizedId])
            }

            for sectionId in response.deletedSectionIds {
                let normalizedId = sectionId.uppercased()
                try db.execute(sql: """
                    UPDATE sections SET deletedAt = ?, syncStatus = 'synced'
                    WHERE id = ? AND deletedAt IS NULL
                """, arguments: [Int64(Date().timeIntervalSince1970 * 1000), normalizedId])
            }

            // Apply handle deletions (Handle Loop support)
            if let deletedHandleIds = response.deletedHandleIds {
                for handleId in deletedHandleIds {
                    let normalizedId = handleId.uppercased()
                    try db.execute(sql: """
                        UPDATE handles SET deletedAt = ?, syncStatus = 'synced'
                        WHERE id = ? AND deletedAt IS NULL
                    """, arguments: [Int64(Date().timeIntervalSince1970 * 1000), normalizedId])

                    // Also unlink any sections from deleted handles
                    try db.execute(sql: """
                        UPDATE sections SET handleId = NULL
                        WHERE handleId = ?
                    """, arguments: [normalizedId])
                }
            }

            // Apply echo deletions (Echo cloud sync)
            if let deletedEchoIds = response.deletedEchoIds {
                for echoId in deletedEchoIds {
                    let normalizedId = echoId.uppercased()
                    try db.execute(sql: "DELETE FROM echoes WHERE id = ?", arguments: [normalizedId])
                }
            }

            if let deletedMemoIds = response.deletedCalendarMemoIds {
                for memoId in deletedMemoIds {
                    let normalizedId = memoId.uppercased()
                    try db.execute(sql: "DELETE FROM calendarMemos WHERE id = ?", arguments: [normalizedId])
                }
            }

            // Clean up empty modules — when notes get reassigned on another device,
            // the old module becomes empty and should be removed.
            // Only clean modules older than 5 minutes to avoid deleting newly created empty ones.
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let fiveMinAgo = now - 300_000

            // Module cleanup is handled by cleanupOrphanedModules() after sync completes
        }
    }

    // MARK: - Push Changes

    private func pushChanges() async throws {
        guard let deviceId = deviceId else {
            throw SyncError.notInitialized
        }

        // Get pending operations — notes first, then sections, so FK constraints are satisfied
        let operations = try await database.read { db in
            try SyncOperationRecord.fetchAll(db, sql: """
                SELECT * FROM syncOperations
                WHERE synced = 0
                ORDER BY CASE entityType WHEN 'note' THEN 0 WHEN 'handle' THEN 1 WHEN 'echo' THEN 2 WHEN 'calendar_memo' THEN 3 ELSE 4 END, timestamp
                LIMIT 10
            """)
        }

        guard !operations.isEmpty else {
            print("[Sync] No pending operations to push")
            return
        }
        print("[Sync] Found \(operations.count) pending operations to push (types: \(operations.map { $0.entityType }))")

        // Look up actual server versions for entities being pushed
        let entityVersions = try await database.read { db -> [String: Int] in
            var versions: [String: Int] = [:]
            for op in operations {
                let table: String = {
                    switch op.entityType {
                    case "note": return "notes"
                    case "handle": return "handles"
                    case "echo": return "echoes"
                    case "calendar_memo": return "calendarMemos"
                    default: return "sections"
                    }
                }()
                if let version = try Int.fetchOne(db, sql: "SELECT COALESCE(serverVersion, 1) FROM \(table) WHERE id = ?", arguments: [op.entityId]) {
                    versions[op.entityId] = version
                }
            }
            return versions
        }

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
                clientVersion: entityVersions[op.entityId] ?? 1
            )
        }

        let request = SyncPushRequest(deviceId: deviceId, operations: operationDTOs)
        // Pre-flight: verify encoding succeeds (SDK silently drops body on encode failure)
        do {
            let encoded = try JSONEncoder().encode(request)
            print("[Sync] Pushing \(operationDTOs.count) operations (\(encoded.count) bytes)...")
        } catch {
            print("[Sync] ENCODING FAILURE — push body cannot be serialized: \(error)")
            // Find and log which operation is problematic
            for (i, dto) in operationDTOs.enumerated() {
                do {
                    _ = try JSONEncoder().encode(dto)
                } catch {
                    print("[Sync]   Operation \(i) (\(dto.entityType)/\(dto.entityId)) fails: \(error)")
                }
            }
            return
        }
        let response: SyncPushResponse = try await supabase.invokeFunction("sync-push", body: request)
        let acceptedTypes = Dictionary(grouping: response.accepted, by: { $0.entityType }).mapValues(\.count)
        print("[Sync] Push result: \(response.accepted.count) accepted \(acceptedTypes), \(response.conflicts.count) conflicts")
        if !response.accepted.isEmpty {
            lastPushTime = Date()
        }

        // Mark accepted operations as synced and set serverVersion from the server's response.
        // The server now returns the actual new_version for each accepted op, so we can
        // set serverVersion correctly without waiting for the next pull.
        try await database.write { db in
            for accepted in response.accepted {
                try db.execute(sql: """
                    UPDATE syncOperations SET synced = 1 WHERE operationId = ?
                """, arguments: [accepted.operationId])

                let table: String
                switch accepted.entityType {
                case "note": table = "notes"
                case "section": table = "sections"
                case "handle": table = "handles"
                case "echo": table = "echoes"
                case "calendar_memo": table = "calendarMemos"
                default: table = "sections"
                }
                try db.execute(sql: """
                    UPDATE \(table) SET syncStatus = 'synced', serverVersion = ? WHERE id = ?
                """, arguments: [accepted.newVersion, accepted.entityId.uppercased()])
            }
        }

        // Handle conflicts — mark their operations as synced so they don't retry forever
        if !response.conflicts.isEmpty {
            try await database.write { db in
                for conflict in response.conflicts {
                    // Mark the sync operation as done (conflict resolved by server)
                    try db.execute(sql: """
                        UPDATE syncOperations SET synced = 1
                        WHERE entityId = ? AND synced = 0
                    """, arguments: [conflict.entityId])
                }
            }
            for conflict in response.conflicts {
                try await handleConflict(conflict)
            }
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
        let entityId = conflict.entityId.uppercased()

        if conflict.resolution == "client_wins" {
            // Server accepted our version — just mark synced and update serverVersion
            try await database.write { db in
                let table: String
                switch conflict.entityType {
                case "note": table = "notes"
                case "section": table = "sections"
                case "handle": table = "handles"
                case "echo": table = "echoes"
                default: table = "sections"
                }
                try db.execute(sql: """
                    UPDATE \(table) SET syncStatus = 'synced', serverVersion = ? WHERE id = ?
                """, arguments: [conflict.serverVersion, entityId])
            }
            print("[Sync] Conflict resolved (client wins) for \(conflict.entityType) \(entityId.prefix(8))")
            return
        }

        if conflict.resolution == "server_wins", let merged = conflict.mergedEntity {
            // Server's version is authoritative — apply it locally
            try await database.write { db in
                guard let dict = merged.value as? [String: Any] else {
                    print("[Sync] Could not decode merged entity for \(entityId.prefix(8))")
                    return
                }
                // Re-encode the dictionary and decode as the appropriate Remote model
                let jsonData = try JSONSerialization.data(withJSONObject: dict)
                let decoder = JSONDecoder()

                switch conflict.entityType {
                case "note":
                    let remote = try decoder.decode(RemoteNote.self, from: jsonData)
                    var local = remote.toLocal()
                    // Preserve local-only fields
                    if let existing = try Note.fetchOne(db, key: entityId) {
                        local.moduleId = existing.moduleId
                        local.tags = existing.tags
                        local.aiTags = existing.aiTags
                        local.viewCount = existing.viewCount
                    }
                    local.syncStatus = .synced
                    try local.update(db)
                    print("[Sync] Conflict resolved (server wins) for note \(entityId.prefix(8))")

                case "section":
                    let remote = try decoder.decode(RemoteSection.self, from: jsonData)
                    var local = remote.toLocal()
                    local.syncStatus = .synced
                    try local.update(db)
                    print("[Sync] Conflict resolved (server wins) for section \(entityId.prefix(8))")

                case "handle":
                    let remote = try decoder.decode(RemoteHandle.self, from: jsonData)
                    var local = remote.toLocal()
                    local.syncStatus = .synced
                    try local.update(db)
                    print("[Sync] Conflict resolved (server wins) for handle \(entityId.prefix(8))")

                case "echo":
                    let remote = try decoder.decode(RemoteEcho.self, from: jsonData)
                    var local = remote.toLocal()
                    local.syncStatus = .synced
                    try local.update(db)
                    print("[Sync] Conflict resolved (server wins) for echo \(entityId.prefix(8))")

                default:
                    print("[Sync] Unknown entity type in conflict: \(conflict.entityType)")
                }
            }
            return
        }

        // Fallback: mark as conflict for manual resolution
        try await database.write { db in
            let table: String
            switch conflict.entityType {
            case "note": table = "notes"
            case "section": table = "sections"
            case "handle": table = "handles"
            case "echo": table = "echoes"
            default: table = "sections"
            }
            try db.execute(sql: """
                UPDATE \(table) SET syncStatus = 'conflict' WHERE id = ?
            """, arguments: [entityId])
            print("[Sync] Marked \(conflict.entityType) \(entityId.prefix(8)) as conflict (resolution: \(conflict.resolution))")
        }
    }

    // MARK: - Module Cleanup

    /// Create missing modules for orphaned notes instead of reassigning them.
    /// This preserves the server's moduleId so both devices converge.
    private func cleanupOrphanedModules() async {
        do { try await database.write { db in
            let now = Int64(Date().timeIntervalSince1970 * 1000)

            // 1. Find orphaned moduleIds (non-deleted notes point to modules that don't exist locally)
            let orphanedModuleIds = try String.fetchAll(db, sql: """
                SELECT DISTINCT moduleId FROM notes
                WHERE deletedAt IS NULL AND moduleId IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM modules WHERE id = notes.moduleId AND deletedAt IS NULL)
            """)

            // 2. Create missing modules for genuinely orphaned notes
            for moduleId in orphanedModuleIds {
                let inserted = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM modules WHERE id = ?", arguments: [moduleId]) ?? 0
                if inserted == 0 {
                    try db.execute(sql: """
                        INSERT INTO modules (id, name, icon, isDefault, storageType, orderIndex, createdAt, updatedAt)
                        VALUES (?, 'Synced', 'folder', 0, 'cloud', 0, ?, ?)
                    """, arguments: [moduleId, now, now])
                    print("[Sync] Created missing module for orphaned notes (moduleId: \(moduleId.prefix(8))...)")
                }
            }

            // 3. Delete empty non-default modules (no non-deleted notes)
            // This handles: project deleted on another device → notes deleted via sync → module is now empty
            let emptyModuleIds = try String.fetchAll(db, sql: """
                SELECT m.id FROM modules m
                WHERE m.deletedAt IS NULL AND m.isDefault = 0
                AND NOT EXISTS (
                    SELECT 1 FROM notes WHERE moduleId = m.id AND deletedAt IS NULL
                )
            """)
            for emptyId in emptyModuleIds {
                try db.execute(sql: "UPDATE modules SET deletedAt = ? WHERE id = ?", arguments: [now, emptyId])
            }
            if !emptyModuleIds.isEmpty {
                print("[Sync] Cleaned up \(emptyModuleIds.count) empty modules")
            }

            // 4. Ensure at least one module exists
            let remaining = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM modules WHERE deletedAt IS NULL") ?? 0
            if remaining == 0 {
                try db.execute(sql: """
                    INSERT INTO modules (id, name, icon, isDefault, storageType, orderIndex, createdAt, updatedAt)
                    VALUES (?, 'Artifacts', 'folder', 0, 'cloud', 0, ?, ?)
                """, arguments: [UUID().uuidString, now, now])
                print("[Sync] Created fallback 'Artifacts' module")
            }
        }
        } catch {
            print("[Sync] ERROR cleaning up orphaned modules: \(error)")
        }
    }

    // MARK: - Realtime Subscription

    /// Subscribe to Supabase Realtime for live sync when app is in foreground
    func subscribeRealtime() async {
        guard realtimeChannel == nil,
              deviceId != nil,
              supabase.isAuthenticated else { return }

        let channel = supabase.client.realtimeV2.channel("sync_changes")

        let noteChanges = channel.postgresChange(
            AnyAction.self, schema: "public", table: "notes"
        )
        let sectionChanges = channel.postgresChange(
            AnyAction.self, schema: "public", table: "sections"
        )
        let handleChanges = channel.postgresChange(
            AnyAction.self, schema: "public", table: "handles"
        )
        let echoChanges = channel.postgresChange(
            AnyAction.self, schema: "public", table: "echoes"
        )
        let calendarMemoChanges = channel.postgresChange(
            AnyAction.self, schema: "public", table: "calendar_memos"
        )

        realtimeTask = Task {
            async let noteLoop: Void = {
                for await _ in noteChanges {
                    await self.scheduleRealtimeSync()
                }
            }()
            async let sectionLoop: Void = {
                for await _ in sectionChanges {
                    await self.scheduleRealtimeSync()
                }
            }()
            async let handleLoop: Void = {
                for await _ in handleChanges {
                    await self.scheduleRealtimeSync()
                }
            }()
            async let echoLoop: Void = {
                for await _ in echoChanges {
                    await self.scheduleRealtimeSync()
                }
            }()
            async let calendarMemoLoop: Void = {
                for await _ in calendarMemoChanges {
                    await self.scheduleRealtimeSync()
                }
            }()
            _ = await (noteLoop, sectionLoop, handleLoop, echoLoop, calendarMemoLoop)
        }

        await channel.subscribe()
        self.realtimeChannel = channel
        print("[Sync] Realtime subscribed")

        // Start periodic pull as fallback for missed realtime events
        startPeriodicPull()
    }

    private func startPeriodicPull() {
        periodicPullTask?.cancel()
        periodicPullTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                guard !Task.isCancelled, !isSyncing else { continue }
                await sync()
            }
        }
    }

    /// Unsubscribe from Realtime when app enters background
    func unsubscribeRealtime() async {
        debouncedSyncTask?.cancel()
        debouncedSyncTask = nil
        realtimeTask?.cancel()
        realtimeTask = nil
        periodicPullTask?.cancel()
        periodicPullTask = nil
        if let channel = realtimeChannel {
            await supabase.client.realtimeV2.removeChannel(channel)
            self.realtimeChannel = nil
            print("[Sync] Realtime unsubscribed")
        }
    }

    /// Debounced sync trigger — waits for quiet before syncing
    /// Skips if we just pushed (self-echo) or if already syncing
    private func scheduleRealtimeSync() {
        // Ignore Realtime events within 2 seconds of our own push (self-echo)
        if Date().timeIntervalSince(lastPushTime) < 2.0 { return }
        // Don't queue if already syncing
        guard !isSyncing else { return }
        debouncedSyncTask?.cancel()
        debouncedSyncTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second debounce
            guard !Task.isCancelled, !isSyncing else { return }
            print("[Sync] Realtime trigger — syncing")
            await sync()
        }
    }

    /// Debounced push trigger — called when new sync operations are created locally
    private var debouncedPushTask: Task<Void, Never>?

    func schedulePush() {
        debouncedPushTask?.cancel()
        debouncedPushTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second debounce
            guard !Task.isCancelled else { return }
            // sync() handles isSyncing internally via pendingSync flag
            await sync()
        }
    }

    // MARK: - Helpers

    private func getOrCreateDeviceId() async -> String {
        // Try to get from database
        do {
            if let existing = try await database.read({ db in
                try String.fetchOne(db, sql: "SELECT deviceId FROM syncMetadata WHERE id = 'singleton'")
            }) {
                // Register device with Supabase if authenticated
                if supabase.isAuthenticated {
                    await registerDevice(existing)
                }
                return existing
            }
        } catch {
            print("[Sync] ERROR reading device ID: \(error)")
        }

        // Create new device ID
        let newId = UUID().uuidString

        do {
            try await database.write { db in
                try db.execute(sql: """
                    INSERT OR REPLACE INTO syncMetadata (id, deviceId, lastSyncTimestamp, schemaVersion)
                    VALUES ('singleton', ?, 0, 1)
                """, arguments: [newId])
            }
        } catch {
            print("[Sync] ERROR saving device ID: \(error)")
        }

        if supabase.isAuthenticated {
            await registerDevice(newId)
        }

        return newId
    }

    private func registerDevice(_ deviceId: String) async {
        guard let userId = supabase.currentUser?.id else { return }

        #if os(iOS)
        let deviceName = UIDevice.current.name
        let platform = "ios"
        #else
        let deviceName = Host.current().localizedName ?? "Mac"
        let platform = "macos"
        #endif

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

        do {
            try await supabase.client.from("devices")
                .upsert([
                    "id": deviceId,
                    "user_id": userId.uuidString,
                    "device_name": deviceName,
                    "platform": platform,
                    "app_version": appVersion
                ])
                .execute()
        } catch {
            print("Failed to register device: \(error)")
        }
    }

    private func getLastSyncTimestamp() async -> Date? {
        do {
            return try await database.read { db in
                if let timestamp = try Int64.fetchOne(db, sql: "SELECT lastSyncTimestamp FROM syncMetadata WHERE id = 'singleton'"),
                   timestamp > 0 {
                    return Date(timeIntervalSince1970: Double(timestamp) / 1000)
                }
                return nil
            }
        } catch {
            print("[Sync] ERROR reading last sync timestamp: \(error)")
            return nil
        }
    }

    private func saveLastSyncTimestamp(_ date: Date) async {
        do {
            try await database.write { db in
                try db.execute(sql: """
                    UPDATE syncMetadata SET lastSyncTimestamp = ? WHERE id = 'singleton'
                """, arguments: [Int64(date.timeIntervalSince1970 * 1000)])
            }
        } catch {
            print("[Sync] ERROR saving last sync timestamp: \(error)")
        }
    }

    @MainActor
    private func updatePendingCount() async {
        do {
            let count = try await database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncOperations WHERE synced = 0") ?? 0
            }
            pendingChangesCount = count
        } catch {
            print("[Sync] ERROR reading pending count: \(error)")
        }
    }

    private func parsePayload(_ jsonString: String) -> [String: AnyCodable] {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: AnyCodable] = [:]
        for (key, value) in dict {
            let codable = AnyCodable(value)
            // Verify this value can actually encode (the SDK uses try? which silently drops the body)
            if (try? JSONEncoder().encode(codable)) != nil {
                result[key] = codable
            } else {
                print("[Sync] WARNING: payload key '\(key)' (type: \(type(of: value))) cannot encode, converting to string")
                result[key] = AnyCodable(String(describing: value))
            }
        }
        return result
    }
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case notInitialized
    case offline
    case aiError(String)
    case serverError(String)
    case edgeFunctionError(EdgeFunctionError)

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
        case .edgeFunctionError(let e):
            return e.localizedDescription
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
