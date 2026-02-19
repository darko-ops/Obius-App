import Foundation
import GRDB

/// The type of shared content
enum ShareType: String, Codable, CaseIterable {
    case live       // Live, mutable note content
    case commit     // Immutable commit snapshot
}

/// A ShareLink represents a publicly accessible link to shared content.
/// Each link has a unique slug used in the URL (e.g., obius.io/s/{slug}).
struct ShareLink: Codable, Identifiable, Hashable {
    var id: String
    var slug: String                    // 8-char base62 URL identifier
    var userId: String                  // Supabase auth user ID
    var shareType: ShareType

    // Content references (one will be set based on shareType)
    var noteId: String?                 // For live shares
    var commitHash: String?             // For commit shares
    var commitName: String?             // Display name for commit shares

    var isActive: Bool
    var viewCount: Int

    // Timestamps (milliseconds since epoch)
    var createdAt: Int64
    var updatedAt: Int64
    var expiresAt: Int64?
    var deletedAt: Int64?

    // Sync fields
    var localVersion: Int
    var serverVersion: Int?
    var syncStatus: SyncStatus

    init(
        id: String = UUID().uuidString,
        slug: String = ShareLink.generateSlug(),
        userId: String,
        shareType: ShareType,
        noteId: String? = nil,
        commitHash: String? = nil,
        commitName: String? = nil,
        isActive: Bool = true,
        viewCount: Int = 0,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        expiresAt: Int64? = nil,
        deletedAt: Int64? = nil,
        localVersion: Int = 1,
        serverVersion: Int? = nil,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.slug = slug
        self.userId = userId
        self.shareType = shareType
        self.noteId = noteId
        self.commitHash = commitHash
        self.commitName = commitName
        self.isActive = isActive
        self.viewCount = viewCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.deletedAt = deletedAt
        self.localVersion = localVersion
        self.serverVersion = serverVersion
        self.syncStatus = syncStatus
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    /// The full shareable URL
    var url: String {
        "https://obius.io/s/\(slug)"
    }

    /// Generates a random 8-character base62 slug
    static func generateSlug() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<8).map { _ in chars.randomElement()! })
    }
}

// MARK: - GRDB Conformance

extension ShareLink: FetchableRecord, PersistableRecord {
    static let databaseTableName = "shareLinks"

    enum Columns: String, ColumnExpression {
        case id, slug, userId, shareType
        case noteId, commitHash, commitName
        case isActive, viewCount
        case createdAt, updatedAt, expiresAt, deletedAt
        case localVersion, serverVersion, syncStatus
    }
}

// MARK: - Mutations

extension ShareLink {
    mutating func touch() {
        updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        localVersion += 1
        syncStatus = .pending
    }

    mutating func deactivate() {
        isActive = false
        touch()
    }

    mutating func softDelete() {
        deletedAt = Int64(Date().timeIntervalSince1970 * 1000)
        isActive = false
        touch()
    }
}
