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

    // Realtime subscription
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?
    private var debouncedSyncTask: Task<Void, Never>?
    private var lastPushTime: Date = .distantPast

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
            let resetKey = "hasResetSyncOps_v17"
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

                let noteCount = unsyncedNotes.count
                let sectionCount = unsyncedSections.count
                if noteCount > 0 || sectionCount > 0 {
                    print("[Sync] Enqueued \(noteCount) notes and \(sectionCount) sections for initial sync")
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

            // 1. Pull remote changes (don't let pull failures block push)
            do {
                try await pullChanges()
            } catch {
                print("[Sync] Pull failed (will still attempt push): \(error)")
            }

            // 2. Push local changes
            try await pushChanges()

            // 3. Post-sync: fix orphaned notes and clean up empty modules
            await cleanupOrphanedModules()

            // 4. Update sync state
            await MainActor.run {
                syncState = .idle
                lastSyncDate = Date()
            }

            await updatePendingCount()

        } catch {
            // Decode the response body for HTTP errors
            if case let FunctionsError.httpError(code, data) = error {
                let body = String(data: data, encoding: .utf8) ?? "(undecodable)"
                print("[Sync] HTTP \(code) error body: \(body)")
            } else {
                print("[Sync] Error: \(error)")
            }
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
            for remoteNote in response.notes {
                let localNote = remoteNote.toLocal()

                // Check if note already exists locally
                if let existing = try Note.fetchOne(db, key: localNote.id) {
                    // UPDATE path — only update if server version is newer
                    if (existing.serverVersion ?? 0) < localNote.localVersion {
                        // Preserve local-only fields not included in server data
                        var mergedNote = localNote
                        mergedNote.moduleId = existing.moduleId  // Keep local module assignment
                        mergedNote.tags = existing.tags
                        mergedNote.aiTags = existing.aiTags
                        mergedNote.viewCount = existing.viewCount
                        try mergedNote.update(db)
                        print("[Sync] Updated note \(localNote.id.prefix(8)) (v\(existing.serverVersion ?? 0) → v\(localNote.localVersion))")
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
                    try noteToInsert.insert(db)
                    print("[Sync] Inserted new note \(localNote.id.prefix(8)) into module \(noteToInsert.moduleId?.prefix(8) ?? "nil")")
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

            // Apply section updates/creates (skip individual failures)
            for remoteSection in response.sections {
                let localSection = remoteSection.toLocal()

                do {
                    if let existing = try Section.fetchOne(db, key: localSection.id) {
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
            let pulledNoteIds = response.notes.map { $0.id.uppercased() }
            let pulledSectionIds = response.sections.map { $0.id.uppercased() }
            let pulledHandleIds = (response.handles ?? []).map { $0.id.uppercased() }
            let allPulledIds = pulledNoteIds + pulledSectionIds + pulledHandleIds
            if !allPulledIds.isEmpty {
                let placeholders = allPulledIds.map { _ in "?" }.joined(separator: ",")
                let deletedOps = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM syncOperations WHERE synced = 0 AND entityId IN (\(placeholders))
                """, arguments: StatementArguments(allPulledIds)) ?? 0
                if deletedOps > 0 {
                    try db.execute(sql: """
                        DELETE FROM syncOperations WHERE synced = 0 AND entityId IN (\(placeholders))
                    """, arguments: StatementArguments(allPulledIds))
                    print("[Sync] Purged \(deletedOps) stale sync operations for entities updated from server")
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
                ORDER BY CASE entityType WHEN 'note' THEN 0 WHEN 'handle' THEN 1 ELSE 2 END, timestamp
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
                let table = op.entityType == "note" ? "notes" : (op.entityType == "handle" ? "handles" : "sections")
                if let version = try Int.fetchOne(db, sql: "SELECT COALESCE(serverVersion, localVersion, 1) FROM \(table) WHERE id = ?", arguments: [op.entityId]) {
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
        print("[Sync] Push result: \(response.accepted.count) accepted, \(response.conflicts.count) conflicts")
        if !response.accepted.isEmpty {
            lastPushTime = Date()
        }

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
                    let pushedVersion = entityVersions[op.entityId] ?? 1
                    try db.execute(sql: """
                        UPDATE \(table) SET syncStatus = 'synced', serverVersion = ? WHERE id = ?
                    """, arguments: [pushedVersion, op.entityId])
                }
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

    // MARK: - Module Cleanup

    /// Create missing modules for orphaned notes instead of reassigning them.
    /// This preserves the server's moduleId so both devices converge.
    private func cleanupOrphanedModules() async {
        try? await database.write { db in
            let now = Int64(Date().timeIntervalSince1970 * 1000)

            // 1. Find orphaned moduleIds (notes point to modules that don't exist locally)
            let orphanedModuleIds = try String.fetchAll(db, sql: """
                SELECT DISTINCT moduleId FROM notes
                WHERE deletedAt IS NULL AND moduleId IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM modules WHERE id = notes.moduleId AND deletedAt IS NULL)
            """)

            // 2. Create missing modules instead of reassigning notes
            for moduleId in orphanedModuleIds {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO modules (id, name, icon, isDefault, storageType, orderIndex, createdAt, updatedAt)
                    VALUES (?, 'Synced', 'folder', 0, 'cloud', 0, ?, ?)
                """, arguments: [moduleId, now, now])
                print("[Sync] Created missing module for orphaned notes (moduleId: \(moduleId.prefix(8))...)")
            }

            // 3. Ensure at least one module exists
            let remaining = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM modules WHERE deletedAt IS NULL") ?? 0
            if remaining == 0 {
                try db.execute(sql: """
                    INSERT INTO modules (id, name, icon, isDefault, storageType, orderIndex, createdAt, updatedAt)
                    VALUES (?, 'Artifacts', 'folder', 0, 'local', 0, ?, ?)
                """, arguments: [UUID().uuidString, now, now])
                print("[Sync] Created fallback 'Artifacts' module")
            }
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
            _ = await (noteLoop, sectionLoop)
        }

        await channel.subscribe()
        self.realtimeChannel = channel
        print("[Sync] Realtime subscribed")
    }

    /// Unsubscribe from Realtime when app enters background
    func unsubscribeRealtime() async {
        debouncedSyncTask?.cancel()
        debouncedSyncTask = nil
        realtimeTask?.cancel()
        realtimeTask = nil
        if let channel = realtimeChannel {
            await supabase.client.realtimeV2.removeChannel(channel)
            self.realtimeChannel = nil
            print("[Sync] Realtime unsubscribed")
        }
    }

    /// Debounced sync trigger — waits for quiet before syncing
    /// Skips if we just pushed (self-echo) or if already syncing
    private func scheduleRealtimeSync() {
        // Ignore Realtime events within 5 seconds of our own push (self-echo)
        if Date().timeIntervalSince(lastPushTime) < 5.0 { return }
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
        // Don't schedule if already syncing — it'll pick up pending ops
        guard !isSyncing else { return }
        debouncedPushTask?.cancel()
        debouncedPushTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second debounce
            guard !Task.isCancelled else { return }
            guard !isSyncing else { return } // double-check before firing
            await sync()
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
