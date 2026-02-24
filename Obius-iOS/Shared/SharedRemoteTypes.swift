import Foundation

// MARK: - Supabase Row Types (shared between main app and extension)

/// Row structure matching the `share_links` Supabase table
struct RemoteShareLinkRow: Codable {
    let id: String
    let slug: String
    let user_id: String
    let share_type: String
    let note_id: String?
    let commit_hash: String?
    let commit_name: String?
    let commit_short_id: String?
    let commit_content: String?
    let creator_name: String?
    let is_active: Bool
    let view_count: Int
    let created_at: String
    let updated_at: String
    let expires_at: String?
    let deleted_at: String?
    let version: Int
}

/// Row structure matching the `comments` Supabase table
struct RemoteCommentRow: Codable {
    let id: String
    let share_link_id: String
    let user_id: String
    let user_display_name: String?
    let parent_comment_id: String?
    let body: String
    let created_at: String
    let updated_at: String
    let deleted_at: String?
}

// MARK: - Shared Content Types

struct SharedNote: Decodable, Identifiable {
    let id: String
    let title: String?
    let body: String
}

struct SharedSection: Decodable, Identifiable {
    let id: String
    let content: String
    let contentType: String
    let orderKey: String
    let indentLevel: Int
    let handleId: String?
    let colorIntent: String?
    let isCollapsed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case contentType = "content_type"
        case orderKey = "order_key"
        case indentLevel = "indent_level"
        case handleId = "handle_id"
        case colorIntent = "color_intent"
        case isCollapsed = "is_collapsed"
    }

    init(id: String, content: String, contentType: String, orderKey: String, indentLevel: Int, handleId: String?, colorIntent: String? = nil, isCollapsed: Bool = false) {
        self.id = id
        self.content = content
        self.contentType = contentType
        self.orderKey = orderKey
        self.indentLevel = indentLevel
        self.handleId = handleId
        self.colorIntent = colorIntent
        self.isCollapsed = isCollapsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        contentType = try container.decode(String.self, forKey: .contentType)
        orderKey = try container.decode(String.self, forKey: .orderKey)
        indentLevel = try container.decode(Int.self, forKey: .indentLevel)
        handleId = try container.decodeIfPresent(String.self, forKey: .handleId)
        colorIntent = try container.decodeIfPresent(String.self, forKey: .colorIntent)
        isCollapsed = (try? container.decode(Bool.self, forKey: .isCollapsed)) ?? false
    }

    /// Maps the Supabase color_intent string to an IntentType
    var intent: IntentType {
        IntentType.fromLegacy(colorIntent)
    }
}

struct SharedComment: Decodable, Identifiable {
    let id: String
    let userId: String
    let userDisplayName: String?
    let userEmail: String?
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userDisplayName = "user_display_name"
        case body
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        userDisplayName = try container.decodeIfPresent(String.self, forKey: .userDisplayName)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        userEmail = nil // Not stored in Supabase; populated locally when available
    }

    init(id: String, userId: String, userDisplayName: String?, userEmail: String? = nil, body: String, createdAt: String) {
        self.id = id
        self.userId = userId
        self.userDisplayName = userDisplayName
        self.userEmail = userEmail
        self.body = body
        self.createdAt = createdAt
    }
}

struct SharedInteraction: Decodable, Identifiable {
    let id: String
    let userId: String
    let userDisplayName: String?
    let interactionType: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userDisplayName = "user_display_name"
        case interactionType = "interaction_type"
        case createdAt = "created_at"
    }
}

struct SharedContentResponse {
    let shareType: String
    let shareLinkId: String
    let note: SharedNote?
    let sections: [SharedSection]?
    let commitContent: String?
    let commitName: String?
    let commitHash: String?
    let commitShortId: String?
    let creatorName: String?
    let createdAt: String?
    let comments: [SharedComment]
    let interactions: [SharedInteraction]
    let viewCount: Int
    let isOffline: Bool

    /// Convenience for creating a copy with selective field overrides.
    func copyWith(
        note: SharedNote?? = nil,
        sections: [SharedSection]?? = nil,
        comments: [SharedComment]? = nil,
        interactions: [SharedInteraction]? = nil,
        viewCount: Int? = nil,
        isOffline: Bool? = nil
    ) -> SharedContentResponse {
        SharedContentResponse(
            shareType: self.shareType,
            shareLinkId: self.shareLinkId,
            note: note ?? self.note,
            sections: sections ?? self.sections,
            commitContent: self.commitContent,
            commitName: self.commitName,
            commitHash: self.commitHash,
            commitShortId: self.commitShortId,
            creatorName: self.creatorName,
            createdAt: self.createdAt,
            comments: comments ?? self.comments,
            interactions: interactions ?? self.interactions,
            viewCount: viewCount ?? self.viewCount,
            isOffline: isOffline ?? self.isOffline
        )
    }
}
