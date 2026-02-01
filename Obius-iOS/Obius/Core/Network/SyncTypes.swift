import Foundation

// MARK: - Sync Request/Response Types

struct SyncPullRequest: Encodable {
    let deviceId: String
    let lastSyncTimestamp: String
    let knownVersions: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case lastSyncTimestamp = "last_sync_timestamp"
        case knownVersions = "known_versions"
    }
}

struct SyncPullResponse: Decodable {
    let notes: [RemoteNote]
    let sections: [RemoteSection]
    let handles: [RemoteHandle]?  // Handle Loop support
    let deletedNoteIds: [String]
    let deletedSectionIds: [String]
    let deletedHandleIds: [String]?  // Handle Loop support
    let serverTimestamp: String
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case notes, sections, handles
        case deletedNoteIds = "deleted_note_ids"
        case deletedSectionIds = "deleted_section_ids"
        case deletedHandleIds = "deleted_handle_ids"
        case serverTimestamp = "server_timestamp"
        case hasMore = "has_more"
    }
}

struct SyncPushRequest: Encodable {
    let deviceId: String
    let operations: [SyncOperationDTO]

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case operations
    }
}

struct SyncOperationDTO: Encodable {
    let operationId: String
    let entityType: String
    let entityId: String
    let operation: String
    let payload: [String: AnyCodable]
    let clientTimestamp: String
    let clientVersion: Int

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case operation
        case payload
        case clientTimestamp = "client_timestamp"
        case clientVersion = "client_version"
    }
}

struct SyncPushResponse: Decodable {
    let accepted: [String]
    let conflicts: [ConflictInfo]
    let serverTimestamp: String

    enum CodingKeys: String, CodingKey {
        case accepted, conflicts
        case serverTimestamp = "server_timestamp"
    }
}

struct ConflictInfo: Decodable {
    let operationId: String
    let entityType: String
    let entityId: String
    let serverVersion: Int
    let clientVersion: Int
    let resolution: String
    let mergedEntity: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case serverVersion = "server_version"
        case clientVersion = "client_version"
        case resolution
        case mergedEntity = "merged_entity"
    }
}

// MARK: - Remote Models (from Supabase)

struct RemoteNote: Decodable {
    let id: String
    let userId: String
    let title: String?
    let aiTitle: String?
    let aiSummary: String?
    let isPinned: Bool
    let colorIntent: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case aiTitle = "ai_title"
        case aiSummary = "ai_summary"
        case isPinned = "is_pinned"
        case colorIntent = "color_intent"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case version
    }

    func toLocal() -> Note {
        Note(
            id: id,
            title: title,
            aiTitle: aiTitle,
            createdAt: parseTimestamp(createdAt),
            updatedAt: parseTimestamp(updatedAt),
            deletedAt: deletedAt.flatMap { parseTimestamp($0) },
            isPinned: isPinned,
            intent: IntentType.fromLegacy(colorIntent),
            localVersion: version,
            serverVersion: version,
            syncStatus: .synced,
            lastSyncedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }
}

struct RemoteSection: Decodable {
    let id: String
    let noteId: String
    let userId: String
    let content: String
    let contentType: String
    let parentSectionId: String?
    let orderKey: String
    let indentLevel: Int
    let isCollapsed: Bool
    let colorIntent: String?
    let handleId: String?  // Handle Loop support
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id
        case noteId = "note_id"
        case userId = "user_id"
        case content
        case contentType = "content_type"
        case parentSectionId = "parent_section_id"
        case orderKey = "order_key"
        case indentLevel = "indent_level"
        case isCollapsed = "is_collapsed"
        case colorIntent = "color_intent"
        case handleId = "handle_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case version
    }

    func toLocal() -> Section {
        Section(
            id: id,
            noteId: noteId,
            content: content,
            contentType: ContentType(rawValue: contentType) ?? .text,
            title: nil,  // Title is local-only, not synced from server
            parentSectionId: parentSectionId,
            orderKey: orderKey,
            indentLevel: indentLevel,
            isCollapsed: isCollapsed,
            isLocked: false,  // Locked state is local-only, not synced from server
            intent: IntentType.fromLegacy(colorIntent),
            handleId: handleId,  // Handle Loop support
            createdAt: parseTimestamp(createdAt),
            updatedAt: parseTimestamp(updatedAt),
            deletedAt: deletedAt.flatMap { parseTimestamp($0) },
            localVersion: version,
            serverVersion: version,
            syncStatus: .synced
        )
    }
}

// MARK: - Remote Handle (Handle Loop support)

struct RemoteHandle: Decodable {
    let id: String
    let userId: String
    let name: String
    let displayName: String
    let content: String
    let intent: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case displayName = "display_name"
        case content
        case intent
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case version
    }

    func toLocal() -> Handle {
        Handle(
            id: id,
            name: name,
            displayName: displayName,
            content: content,
            intent: IntentType.fromLegacy(intent),
            createdAt: parseTimestamp(createdAt),
            updatedAt: parseTimestamp(updatedAt),
            deletedAt: deletedAt.flatMap { parseTimestamp($0) },
            localVersion: version,
            serverVersion: version,
            syncStatus: .synced
        )
    }
}

// MARK: - AI Types

struct EmbeddingRequest: Encodable {
    let sectionId: String
    let content: String?

    enum CodingKeys: String, CodingKey {
        case sectionId = "section_id"
        case content
    }
}

struct EmbeddingResponse: Decodable {
    let results: [EmbeddingResult]
    let model: String?
}

struct EmbeddingResult: Decodable {
    let sectionId: String
    let success: Bool
    let error: String?

    enum CodingKeys: String, CodingKey {
        case sectionId = "section_id"
        case success, error
    }
}

struct SummaryRequest: Encodable {
    let noteId: String

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
    }
}

struct SummaryResponse: Decodable {
    let noteId: String
    let title: String
    let summary: String
    let success: Bool
    let error: String?

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case title, summary, success, error
    }
}

struct SemanticSearchRequest: Encodable {
    let query: String
    let limit: Int?
    let threshold: Double?
}

struct SemanticSearchResponse: Decodable {
    let results: [SemanticSearchResult]
}

struct SemanticSearchResult: Decodable, Identifiable {
    let sectionId: String
    let noteId: String
    let content: String
    let similarity: Double
    let noteTitle: String?

    var id: String { sectionId }

    enum CodingKeys: String, CodingKey {
        case sectionId = "section_id"
        case noteId = "note_id"
        case content, similarity
        case noteTitle = "note_title"
    }
}

// MARK: - Helpers

private func parseTimestamp(_ isoString: String) -> Int64 {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: isoString) {
        return Int64(date.timeIntervalSince1970 * 1000)
    }
    // Try without fractional seconds
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: isoString) {
        return Int64(date.timeIntervalSince1970 * 1000)
    }
    return Int64(Date().timeIntervalSince1970 * 1000)
}

// MARK: - AnyCodable for flexible encoding/decoding

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: [], debugDescription: "Unable to encode value")
            )
        }
    }
}
