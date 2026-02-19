import Foundation
import GRDB

/// A Comment on shared content (called "Handshake" in the UI).
/// Comments on commit shares create sealed records with new hashes.
struct Comment: Codable, Identifiable, Hashable {
    var id: String
    var shareLinkId: String             // FK to shareLinks
    var userId: String                  // Supabase auth user ID
    var userDisplayName: String?        // Cached display name
    var parentCommentId: String?        // For threaded replies
    var body: String

    // Timestamps (milliseconds since epoch)
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    /// For commit shares: the new version hash after this comment was added
    var sealedCommitHash: String?

    init(
        id: String = UUID().uuidString,
        shareLinkId: String,
        userId: String,
        userDisplayName: String? = nil,
        parentCommentId: String? = nil,
        body: String,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        deletedAt: Int64? = nil,
        sealedCommitHash: String? = nil
    ) {
        self.id = id
        self.shareLinkId = shareLinkId
        self.userId = userId
        self.userDisplayName = userDisplayName
        self.parentCommentId = parentCommentId
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.sealedCommitHash = sealedCommitHash
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    var displayAuthor: String {
        userDisplayName ?? "Anonymous"
    }
}

// MARK: - GRDB Conformance

extension Comment: FetchableRecord, PersistableRecord {
    static let databaseTableName = "comments"

    enum Columns: String, ColumnExpression {
        case id, shareLinkId, userId, userDisplayName
        case parentCommentId, body
        case createdAt, updatedAt, deletedAt
        case sealedCommitHash
    }

    // MARK: - Relationships

    static let shareLink = belongsTo(ShareLink.self)
    static let parent = belongsTo(Comment.self, key: "parent", using: ForeignKey(["parentCommentId"]))
    static let replies = hasMany(Comment.self, key: "replies", using: ForeignKey(["parentCommentId"]))
}
