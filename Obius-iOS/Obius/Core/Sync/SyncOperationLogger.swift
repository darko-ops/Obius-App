import Foundation
import GRDB

/// Logs operations for sync
final class SyncOperationLogger {
    private let database: DatabaseManager

    /// Called after an operation is logged — use to trigger a debounced sync push
    var onOperationLogged: (() -> Void)?

    init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - Note Operations

    func logNoteCreate(_ note: Note) {
        print("[SyncLogger] logNoteCreate called for \(note.id)")
        logOperation(
            entityType: "note",
            entityId: note.id,
            operationType: "create",
            payload: noteToPayload(note)
        )
    }

    func logNoteUpdate(_ note: Note) {
        print("[SyncLogger] logNoteUpdate called for \(note.id)")
        logOperation(
            entityType: "note",
            entityId: note.id,
            operationType: "update",
            payload: noteToPayload(note)
        )
    }

    /// Synchronous version — awaitable, ensures the operation is written before returning
    func logNoteUpdateSync(_ note: Note) async {
        await logOperationSync(
            entityType: "note",
            entityId: note.id,
            operationType: "update",
            payload: noteToPayload(note)
        )
    }

    func logNoteCreateSync(_ note: Note) async {
        await logOperationSync(
            entityType: "note",
            entityId: note.id,
            operationType: "create",
            payload: noteToPayload(note)
        )
    }

    func logSectionCreateSync(_ section: Section) async {
        await logOperationSync(
            entityType: "section",
            entityId: section.id,
            operationType: "create",
            payload: sectionToPayload(section)
        )
    }

    func logSectionUpdateSync(_ section: Section) async {
        await logOperationSync(
            entityType: "section",
            entityId: section.id,
            operationType: "update",
            payload: sectionToPayload(section)
        )
    }

    func logNoteDelete(_ noteId: String) {
        logOperation(
            entityType: "note",
            entityId: noteId,
            operationType: "delete",
            payload: [:]
        )
    }

    // MARK: - Section Operations

    func logSectionCreate(_ section: Section) {
        logOperation(
            entityType: "section",
            entityId: section.id,
            operationType: "create",
            payload: sectionToPayload(section)
        )
    }

    func logSectionUpdate(_ section: Section) {
        logOperation(
            entityType: "section",
            entityId: section.id,
            operationType: "update",
            payload: sectionToPayload(section)
        )
    }

    func logSectionDelete(_ sectionId: String) {
        logOperation(
            entityType: "section",
            entityId: sectionId,
            operationType: "delete",
            payload: [:]
        )
    }

    // MARK: - Handle Operations

    func logHandleCreate(_ handle: Handle) {
        logOperation(
            entityType: "handle",
            entityId: handle.id,
            operationType: "create",
            payload: handleToPayload(handle)
        )
    }

    func logHandleUpdate(_ handle: Handle) {
        logOperation(
            entityType: "handle",
            entityId: handle.id,
            operationType: "update",
            payload: handleToPayload(handle)
        )
    }

    func logHandleDelete(_ handleId: String) {
        logOperation(
            entityType: "handle",
            entityId: handleId,
            operationType: "delete",
            payload: [:]
        )
    }

    // MARK: - Echo Operations

    func logEchoCreate(_ echo: Echo) {
        logOperation(
            entityType: "echo",
            entityId: echo.id,
            operationType: "create",
            payload: echoToPayload(echo)
        )
    }

    func logEchoUpdate(_ echo: Echo) {
        logOperation(
            entityType: "echo",
            entityId: echo.id,
            operationType: "update",
            payload: echoToPayload(echo)
        )
    }

    func logEchoDelete(_ echoId: String) {
        logOperation(
            entityType: "echo",
            entityId: echoId,
            operationType: "delete",
            payload: [:]
        )
    }

    // MARK: - CalendarMemo Operations

    func logCalendarMemoCreate(_ memo: CalendarMemo) {
        logOperation(
            entityType: "calendar_memo",
            entityId: memo.id,
            operationType: "create",
            payload: calendarMemoToPayload(memo)
        )
    }

    func logCalendarMemoUpdate(_ memo: CalendarMemo) {
        logOperation(
            entityType: "calendar_memo",
            entityId: memo.id,
            operationType: "update",
            payload: calendarMemoToPayload(memo)
        )
    }

    func logCalendarMemoDelete(_ memoId: String) {
        logOperation(
            entityType: "calendar_memo",
            entityId: memoId,
            operationType: "delete",
            payload: [:]
        )
    }

    // MARK: - ShareLink Operations

    func logShareLinkCreate(_ shareLink: ShareLink) {
        logOperation(
            entityType: "shareLink",
            entityId: shareLink.id,
            operationType: "create",
            payload: shareLinkToPayload(shareLink)
        )
    }

    func logShareLinkUpdate(_ shareLink: ShareLink) {
        logOperation(
            entityType: "shareLink",
            entityId: shareLink.id,
            operationType: "update",
            payload: shareLinkToPayload(shareLink)
        )
    }

    func logShareLinkDelete(_ shareLinkId: String) {
        logOperation(
            entityType: "shareLink",
            entityId: shareLinkId,
            operationType: "delete",
            payload: [:]
        )
    }

    // MARK: - Private

    private func logOperation(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: [String: Any]
    ) {
        Task {
            await logOperationSync(entityType: entityType, entityId: entityId, operationType: operationType, payload: payload)
            onOperationLogged?()
        }
    }

    private func logOperationSync(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: [String: Any]
    ) async {
        do {
            let payloadJson = try JSONSerialization.data(withJSONObject: payload)
            let payloadString = String(data: payloadJson, encoding: .utf8) ?? "{}"

            try await database.write { db in
                // Delete any existing unsynced op for this entity to avoid duplicates
                try db.execute(sql: """
                    DELETE FROM syncOperations WHERE entityId = ? AND synced = 0
                """, arguments: [entityId])

                try db.execute(sql: """
                    INSERT INTO syncOperations (operationId, entityType, entityId, operationType, payload, timestamp, synced)
                    VALUES (?, ?, ?, ?, ?, ?, 0)
                """, arguments: [
                    UUID().uuidString,
                    entityType,
                    entityId,
                    operationType,
                    payloadString,
                    Int64(Date().timeIntervalSince1970 * 1000)
                ])
            }
            print("[SyncLogger] Wrote \(operationType) op for \(entityType)/\(entityId.prefix(8))")
        } catch {
            print("[SyncLogger] FAILED to log \(operationType) for \(entityType)/\(entityId.prefix(8)): \(error)")
        }
    }

    private func noteToPayload(_ note: Note) -> [String: Any] {
        var payload: [String: Any] = [
            "title": note.title as Any,
            "body": note.body,
            "is_pinned": note.isPinned,
            "color_intent": note.intent.legacyValue,  // Use legacy value for server compatibility
            "created_at": formatTimestamp(note.createdAt),
            "updated_at": formatTimestamp(note.updatedAt)
        ]

        if let groupName = note.groupName {
            payload["group_name"] = groupName
        }

        if let moduleId = note.moduleId {
            payload["module_id"] = moduleId
            // Look up module name/icon for cross-device sync
            if let moduleInfo = try? database.read({ db in
                try Row.fetchOne(db, sql: "SELECT name, icon FROM modules WHERE id = ?", arguments: [moduleId])
            }) {
                if let name = moduleInfo["name"] as? String { payload["module_name"] = name }
                if let icon = moduleInfo["icon"] as? String { payload["module_icon"] = icon }
            }
        }

        if let aiTitle = note.aiTitle {
            payload["ai_title"] = aiTitle
        }

        if let bodyRichText = note.bodyRichText {
            payload["body_rich_text"] = bodyRichText
        }

        // Send as JSON-encoded strings to match the server's TEXT column and the
        // enqueueUnsyncedEntities format. Sending a nested dict here makes the
        // round-trip through Postgres TEXT inconsistent — peers end up with no
        // interstitial content (text-after-section) even though the section synced.
        payload["interstitial_content"] = Self.jsonString(from: note.interstitialContent)
        payload["interstitial_rich_content"] = Self.jsonString(from: note.interstitialRichContent)

        if let deletedAt = note.deletedAt {
            payload["deleted_at"] = formatTimestamp(deletedAt)
        }

        return payload
    }

    private func sectionToPayload(_ section: Section) -> [String: Any] {
        var payload: [String: Any] = [
            "note_id": section.noteId,
            "content": section.content,
            "content_type": section.contentType.rawValue,
            "section_type": section.sectionType.rawValue,
            "order_key": section.orderKey,
            "indent_level": section.indentLevel,
            "is_collapsed": section.isCollapsed,
            "color_intent": section.intent.legacyValue,  // Use legacy value for server compatibility
            "created_at": formatTimestamp(section.createdAt),
            "updated_at": formatTimestamp(section.updatedAt)
        ]

        if let parentId = section.parentSectionId {
            payload["parent_section_id"] = parentId
        }

        if let handleId = section.handleId {
            payload["handle_id"] = handleId
        }

        if let deletedAt = section.deletedAt {
            payload["deleted_at"] = formatTimestamp(deletedAt)
        }

        return payload
    }

    private func shareLinkToPayload(_ shareLink: ShareLink) -> [String: Any] {
        var payload: [String: Any] = [
            "slug": shareLink.slug,
            "user_id": shareLink.userId,
            "share_type": shareLink.shareType.rawValue,
            "is_active": shareLink.isActive,
            "view_count": shareLink.viewCount,
            "created_at": formatTimestamp(shareLink.createdAt),
            "updated_at": formatTimestamp(shareLink.updatedAt)
        ]

        if let noteId = shareLink.noteId {
            payload["note_id"] = noteId
        }
        if let commitHash = shareLink.commitHash {
            payload["commit_hash"] = commitHash
        }
        if let commitName = shareLink.commitName {
            payload["commit_name"] = commitName
        }
        if let deletedAt = shareLink.deletedAt {
            payload["deleted_at"] = formatTimestamp(deletedAt)
        }

        return payload
    }

    private func handleToPayload(_ handle: Handle) -> [String: Any] {
        var payload: [String: Any] = [
            "name": handle.name,
            "display_name": handle.displayName,
            "content": handle.content,
            "intent": handle.intent.legacyValue,
            "created_at": formatTimestamp(handle.createdAt),
            "updated_at": formatTimestamp(handle.updatedAt)
        ]

        if let deletedAt = handle.deletedAt {
            payload["deleted_at"] = formatTimestamp(deletedAt)
        }

        return payload
    }

    private func echoToPayload(_ echo: Echo) -> [String: Any] {
        var payload: [String: Any] = [
            "handle_id": echo.handleId,
            "is_recurring": echo.isRecurring,
            "fire_date": echo.fireDate,
            "is_active": echo.isActive,
            "is_alerted": echo.isAlerted,
            "created_at": formatTimestamp(echo.createdAt),
            "updated_at": formatTimestamp(echo.updatedAt)
        ]

        if let intervalsJSON = echo.intervalsJSON {
            payload["intervals_json"] = intervalsJSON
        }

        if let nextFireDate = echo.nextFireDate {
            payload["next_fire_date"] = nextFireDate
        }

        if let lastAcknowledgedAt = echo.lastAcknowledgedAt {
            payload["last_acknowledged_at"] = lastAcknowledgedAt
        }

        return payload
    }

    private func calendarMemoToPayload(_ memo: CalendarMemo) -> [String: Any] {
        [
            "date_key": memo.dateKey,
            "content": memo.content,
            "created_at": formatTimestamp(memo.createdAt),
            "updated_at": formatTimestamp(memo.updatedAt)
        ]
    }

    private func formatTimestamp(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func jsonString(from dict: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
