import Foundation
import GRDB

/// Lightweight index entry for smart context assembly.
/// Maps notes, sections, and handles with pre-computed token counts
/// and content hashes for efficient retrieval and change detection.
struct NoteIndex: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "note_index"

    enum EntityType: String, Codable {
        case noteBody = "note_body"
        case section = "section"
        case handle = "handle"
    }

    var id: String
    var entityType: EntityType
    var noteId: String?
    var contentHash: String
    var tokenCount: Int
    var intent: String?
    var handleId: String?
    var lastIndexedAt: Int64

    enum Columns: String, ColumnExpression {
        case id, entityType, noteId, contentHash, tokenCount, intent, handleId, lastIndexedAt
    }
}
