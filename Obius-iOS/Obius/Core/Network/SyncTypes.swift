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
    let echoes: [RemoteEcho]?  // Echo cloud sync
    let calendarMemos: [RemoteCalendarMemo]?
    let deletedNoteIds: [String]
    let deletedSectionIds: [String]
    let deletedHandleIds: [String]?  // Handle Loop support
    let deletedEchoIds: [String]?  // Echo cloud sync
    let deletedCalendarMemoIds: [String]?
    let serverTimestamp: String
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case notes, sections, handles, echoes
        case calendarMemos = "calendar_memos"
        case deletedNoteIds = "deleted_note_ids"
        case deletedSectionIds = "deleted_section_ids"
        case deletedHandleIds = "deleted_handle_ids"
        case deletedEchoIds = "deleted_echo_ids"
        case deletedCalendarMemoIds = "deleted_calendar_memo_ids"
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

struct AcceptedOp: Decodable {
    let operationId: String
    let entityId: String
    let entityType: String
    let newVersion: Int

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case entityId = "entity_id"
        case entityType = "entity_type"
        case newVersion = "new_version"
    }
}

struct SyncPushResponse: Decodable {
    let accepted: [AcceptedOp]
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
    let body: String?
    let bodyRichText: String?
    let interstitialContent: String?
    let interstitialRichContent: String?
    let isPinned: FlexBool
    let colorIntent: String
    let groupName: String?
    let moduleId: String?
    let moduleName: String?
    let moduleIcon: String?
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
        case body
        case bodyRichText = "body_rich_text"
        case interstitialContent = "interstitial_content"
        case interstitialRichContent = "interstitial_rich_content"
        case isPinned = "is_pinned"
        case colorIntent = "color_intent"
        case groupName = "group_name"
        case moduleId = "module_id"
        case moduleName = "module_name"
        case moduleIcon = "module_icon"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case version
    }

    func toLocal() -> Note {
        // Parse interstitial JSON strings into dictionaries
        let interstitial: [String: String] = {
            guard let str = interstitialContent, let data = str.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
            return dict
        }()
        let interstitialRich: [String: String] = {
            guard let str = interstitialRichContent, let data = str.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
            return dict
        }()

        return Note(
            id: id.uppercased(),  // Normalize: PostgreSQL uuid type lowercases, but local UUIDs are uppercase
            title: title,
            aiTitle: aiTitle,
            body: body ?? "",
            bodyRichText: bodyRichText,
            interstitialContent: interstitial,
            interstitialRichContent: interstitialRich,
            createdAt: parseTimestamp(createdAt),
            updatedAt: parseTimestamp(updatedAt),
            deletedAt: deletedAt.flatMap { parseTimestamp($0) },
            isPinned: isPinned.value,
            groupName: groupName,
            intent: IntentType.fromLegacy(colorIntent),
            moduleId: moduleId?.uppercased(),  // Normalize module ID case too
            localVersion: version,
            serverVersion: version,
            syncStatus: .synced,
            lastSyncedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }
}

/// Decodes booleans that may come as Bool, String ("true"/"false"), or Int (0/1)
struct FlexBool: Decodable {
    let value: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            value = b
        } else if let s = try? container.decode(String.self) {
            value = s == "true" || s == "1"
        } else if let i = try? container.decode(Int.self) {
            value = i != 0
        } else {
            value = false
        }
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
    let isCollapsed: FlexBool
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
            id: id.uppercased(),  // Normalize: PostgreSQL uuid type lowercases
            noteId: noteId.uppercased(),  // Must match note's uppercased ID
            content: content,
            contentType: ContentType(rawValue: contentType) ?? .text,
            title: nil,  // Title is local-only, not synced from server
            parentSectionId: parentSectionId?.uppercased(),
            orderKey: orderKey,
            indentLevel: indentLevel,
            isCollapsed: isCollapsed.value,
            isLocked: false,  // Locked state is local-only, not synced from server
            intent: IntentType.fromLegacy(colorIntent),
            handleId: handleId?.uppercased(),  // Handle Loop support
            createdAt: parseTimestamp(createdAt),
            updatedAt: parseTimestamp(updatedAt),
            deletedAt: deletedAt.flatMap { parseTimestamp($0) },
            localVersion: version,
            serverVersion: version,
            syncStatus: .synced
        )
    }
}

// MARK: - Remote Echo (Cloud Sync)

struct RemoteEcho: Decodable {
    let id: String
    let userId: String
    let handleId: String
    let isRecurring: FlexBool
    let intervalsJson: String?
    let fireDate: Int64
    let isActive: FlexBool
    let nextFireDate: Int64?
    let isAlerted: FlexBool
    let lastAcknowledgedAt: Int64?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case handleId = "handle_id"
        case isRecurring = "is_recurring"
        case intervalsJson = "intervals_json"
        case fireDate = "fire_date"
        case isActive = "is_active"
        case nextFireDate = "next_fire_date"
        case isAlerted = "is_alerted"
        case lastAcknowledgedAt = "last_acknowledged_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case version
    }

    func toLocal() -> Echo {
        Echo(
            id: id.uppercased(),
            handleId: handleId.uppercased(),
            isRecurring: isRecurring.value,
            intervalsJSON: intervalsJson,
            fireDate: fireDate,
            isActive: isActive.value,
            nextFireDate: nextFireDate,
            isAlerted: isAlerted.value,
            lastAcknowledgedAt: lastAcknowledgedAt,
            createdAt: parseTimestamp(createdAt),
            updatedAt: parseTimestamp(updatedAt),
            localVersion: version,
            serverVersion: version,
            syncStatus: .synced
        )
    }
}

// MARK: - Remote Calendar Memo

struct RemoteCalendarMemo: Decodable {
    let id: String
    let userId: String
    let dateKey: String
    let content: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let version: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case dateKey = "date_key"
        case content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case version
    }

    func toLocal() -> CalendarMemo {
        CalendarMemo(
            id: id.uppercased(),
            dateKey: dateKey,
            content: content,
            createdAt: parseTimestamp(createdAt),
            updatedAt: parseTimestamp(updatedAt),
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
            id: id.uppercased(),  // Normalize: PostgreSQL uuid type lowercases
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

        // Handle NSNull first
        if value is NSNull {
            try container.encodeNil()
            return
        }

        // Handle NSNumber explicitly — JSONSerialization returns NSNumber for booleans,
        // integers, and doubles. Swift's `as Bool`/`as Int` pattern matching is unreliable
        // for NSNumber, so use CFBooleanGetTypeID() to distinguish booleans from numbers.
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                try container.encode(number.boolValue)
            } else {
                // Check if it's a floating point type
                let objCType = String(cString: number.objCType)
                if objCType == "d" || objCType == "f" {
                    try container.encode(number.doubleValue)
                } else {
                    try container.encode(number.intValue)
                }
            }
            return
        }

        // Handle native Swift types
        switch value {
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            // Fallback: convert to string instead of throwing, so the SDK's
            // try? never produces a nil body
            try container.encode(String(describing: value))
        }
    }
}
