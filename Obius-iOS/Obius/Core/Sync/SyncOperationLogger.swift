import Foundation
import GRDB

/// Logs operations for sync
final class SyncOperationLogger {
    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - Note Operations

    func logNoteCreate(_ note: Note) {
        logOperation(
            entityType: "note",
            entityId: note.id,
            operationType: "create",
            payload: noteToPayload(note)
        )
    }

    func logNoteUpdate(_ note: Note) {
        logOperation(
            entityType: "note",
            entityId: note.id,
            operationType: "update",
            payload: noteToPayload(note)
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

    // MARK: - Private

    private func logOperation(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: [String: Any]
    ) {
        Task {
            do {
                let payloadJson = try JSONSerialization.data(withJSONObject: payload)
                let payloadString = String(data: payloadJson, encoding: .utf8) ?? "{}"

                try await database.write { db in
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
            } catch {
                print("Failed to log sync operation: \(error)")
            }
        }
    }

    private func noteToPayload(_ note: Note) -> [String: Any] {
        var payload: [String: Any] = [
            "title": note.title as Any,
            "is_pinned": note.isPinned,
            "color_intent": note.intent.legacyValue,  // Use legacy value for server compatibility
            "created_at": formatTimestamp(note.createdAt),
            "updated_at": formatTimestamp(note.updatedAt)
        ]

        if let aiTitle = note.aiTitle {
            payload["ai_title"] = aiTitle
        }

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

        if let deletedAt = section.deletedAt {
            payload["deleted_at"] = formatTimestamp(deletedAt)
        }

        return payload
    }

    private func formatTimestamp(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
