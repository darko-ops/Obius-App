import Foundation
import GRDB

// MARK: - Commit (Hot Store Record)

/// A commit record stored in the Hot Store (SQLite) for quick lookups.
/// The actual commit content is stored in the Cold Store as a .obx file.
struct Commit: Codable, Identifiable, Hashable {
    var id: String
    var noteId: String
    var name: String?          // User-provided commit name
    var shortId: String        // Human reference e.g. #OBX-A1B2-C3D4
    var hash: String           // SHA-256 content hash (e.g., "sha256:abc123...")
    var parentHash: String?    // Previous commit hash for this note
    var filePath: String       // Relative path to .obx file in Cold Store
    var createdAt: Int64

    init(
        id: String = UUID().uuidString,
        noteId: String,
        name: String? = nil,
        shortId: String = Commit.generateShortId(),
        hash: String,
        parentHash: String? = nil,
        filePath: String,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.noteId = noteId
        self.name = name
        self.shortId = shortId
        self.hash = hash
        self.parentHash = parentHash
        self.filePath = filePath
        self.createdAt = createdAt
    }

    /// Generates a unique short ID in the format OBX-XXXX-XXXX (uppercase letters + digits)
    static func generateShortId() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let block = { (0..<4).map { _ in chars.randomElement()! } }
        return "OBX-\(String(block()))-\(String(block()))"
    }
}

// MARK: - GRDB Conformance

extension Commit: FetchableRecord, PersistableRecord {
    static let databaseTableName = "commits"

    enum Columns: String, ColumnExpression {
        case id, noteId, name, shortId, hash, parentHash, filePath, createdAt
    }

    // Relationships
    static let note = belongsTo(Note.self)

    var note: QueryInterfaceRequest<Note> {
        request(for: Commit.note)
    }
}

// MARK: - CommitContent (.obx File Content)

/// The full content of a commit stored in a .obx file in the Cold Store.
/// This is the immutable snapshot of a note at a specific point in time.
struct CommitContent: Codable {
    let version: Int           // Schema version for future compatibility
    let hash: String           // SHA-256 hash of this commit's content
    let parentHash: String?    // Hash of parent commit (nil for first commit)
    let createdAt: Int64       // Timestamp when commit was created
    let note: CommitNoteSnapshot
    let sections: [CommitSectionSnapshot]
    let mediaRefs: [MediaReference]

    init(
        version: Int = 1,
        hash: String,
        parentHash: String? = nil,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        note: CommitNoteSnapshot,
        sections: [CommitSectionSnapshot],
        mediaRefs: [MediaReference] = []
    ) {
        self.version = version
        self.hash = hash
        self.parentHash = parentHash
        self.createdAt = createdAt
        self.note = note
        self.sections = sections
        self.mediaRefs = mediaRefs
    }
}

// MARK: - CommitNoteSnapshot

/// Snapshot of a note's state at commit time.
struct CommitNoteSnapshot: Codable {
    let id: String
    let title: String?
    let body: String
    let intent: String
    let isPinned: Bool
    let createdAt: Int64
    let updatedAt: Int64

    init(
        id: String,
        title: String?,
        body: String,
        intent: String,
        isPinned: Bool,
        createdAt: Int64,
        updatedAt: Int64
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.intent = intent
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Create snapshot from a Note model
    init(from note: Note) {
        self.id = note.id
        self.title = note.title
        self.body = note.body
        self.intent = note.intent.rawValue
        self.isPinned = note.isPinned
        self.createdAt = note.createdAt
        self.updatedAt = note.updatedAt
    }
}

// MARK: - CommitSectionSnapshot

/// Snapshot of a section's state at commit time.
struct CommitSectionSnapshot: Codable {
    let id: String
    let content: String
    let contentType: String
    let sectionType: String
    let intent: String
    let orderKey: String
    let indentLevel: Int
    let parentSectionId: String?
    let handleId: String?
    let isCollapsed: Bool
    let isLocked: Bool
    let isTemplateContent: Bool
    let templatePrefix: String?
    let contentBefore: String?

    init(
        id: String,
        content: String,
        contentType: String,
        sectionType: String,
        intent: String,
        orderKey: String,
        indentLevel: Int,
        parentSectionId: String?,
        handleId: String?,
        isCollapsed: Bool,
        isLocked: Bool,
        isTemplateContent: Bool = false,
        templatePrefix: String? = nil,
        contentBefore: String? = nil
    ) {
        self.id = id
        self.content = content
        self.contentType = contentType
        self.sectionType = sectionType
        self.intent = intent
        self.orderKey = orderKey
        self.indentLevel = indentLevel
        self.parentSectionId = parentSectionId
        self.handleId = handleId
        self.isCollapsed = isCollapsed
        self.isLocked = isLocked
        self.isTemplateContent = isTemplateContent
        self.templatePrefix = templatePrefix
        self.contentBefore = contentBefore
    }

    /// Create snapshot from a Section model
    init(from section: Section) {
        self.id = section.id
        self.content = section.content
        self.contentType = section.contentType.rawValue
        self.sectionType = section.sectionType.rawValue
        self.intent = section.intent.rawValue
        self.orderKey = section.orderKey
        self.indentLevel = section.indentLevel
        self.parentSectionId = section.parentSectionId
        self.handleId = section.handleId
        self.isCollapsed = section.isCollapsed
        self.isLocked = section.isLocked
        self.isTemplateContent = section.isTemplateContent
        self.templatePrefix = section.templatePrefix
        self.contentBefore = section.contentBefore
    }

    // Custom decoder to handle commits without isTemplateContent/templatePrefix/contentBefore
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        contentType = try container.decode(String.self, forKey: .contentType)
        sectionType = try container.decode(String.self, forKey: .sectionType)
        intent = try container.decode(String.self, forKey: .intent)
        orderKey = try container.decode(String.self, forKey: .orderKey)
        indentLevel = try container.decode(Int.self, forKey: .indentLevel)
        parentSectionId = try container.decodeIfPresent(String.self, forKey: .parentSectionId)
        handleId = try container.decodeIfPresent(String.self, forKey: .handleId)
        isCollapsed = try container.decode(Bool.self, forKey: .isCollapsed)
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
        isTemplateContent = try container.decodeIfPresent(Bool.self, forKey: .isTemplateContent) ?? false
        templatePrefix = try container.decodeIfPresent(String.self, forKey: .templatePrefix)
        contentBefore = try container.decodeIfPresent(String.self, forKey: .contentBefore)
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, contentType, sectionType, intent, orderKey, indentLevel
        case parentSectionId, handleId, isCollapsed, isLocked, isTemplateContent, templatePrefix, contentBefore
    }
}

// MARK: - MediaReference

/// Reference to a media file stored in the Cold Store.
/// Uses content-addressable storage via SHA-256 hashing for deduplication.
struct MediaReference: Codable, Hashable {
    let hash: String       // SHA-256 hash of media content (e.g., "sha256:abc123...")
    let filename: String   // Original filename
    let mimeType: String   // MIME type (e.g., "image/png")
    let size: Int64        // File size in bytes

    init(hash: String, filename: String, mimeType: String, size: Int64) {
        self.hash = hash
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
    }
}

// MARK: - CommitHashContent (for deterministic hashing)

/// Content structure for computing commit hash.
/// Excludes timestamp to ensure deterministic hashes for identical content.
struct CommitHashContent: Codable {
    let parentHash: String?
    let note: CommitNoteSnapshot
    let sections: [CommitSectionSnapshot]
    let mediaRefs: [MediaReference]
}

// MARK: - NodeCommitContent

/// Content for a node (section) commit stored as a named .obx file.
/// Unlike full note commits, these are named by the user and store a single section.
struct NodeCommitContent: Codable {
    let version: Int
    let name: String           // User-provided name (filename without .obx)
    let shortId: String?       // Human reference e.g. #OBX-A1B2-C3D4
    let hash: String?          // SHA-256 content hash
    let createdAt: Int64
    let section: CommitSectionSnapshot
    let sourceNoteId: String   // The note this node came from
    let sourceNoteTitle: String?

    init(
        version: Int = 1,
        name: String,
        shortId: String? = Commit.generateShortId(),
        hash: String? = nil,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        section: CommitSectionSnapshot,
        sourceNoteId: String,
        sourceNoteTitle: String?
    ) {
        self.version = version
        self.name = name
        self.shortId = shortId
        self.hash = hash
        self.createdAt = createdAt
        self.section = section
        self.sourceNoteId = sourceNoteId
        self.sourceNoteTitle = sourceNoteTitle
    }
}

// MARK: - CommitType

/// Distinguishes between page commits and node commits
enum CommitType: String, Codable {
    case page = "page"   // Full note commit (hash-based naming)
    case node = "node"   // Single section commit (user-named)
}

// MARK: - CommitError

enum CommitError: Error, LocalizedError {
    case noteNotFound
    case sectionNotFound
    case commitNotFound
    case hashMismatch
    case fileWriteError(String)
    case fileReadError(String)
    case encodingError
    case decodingError
    case invalidName(String)
    case nameAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .noteNotFound:
            return "Note not found in Hot Store"
        case .sectionNotFound:
            return "Section not found"
        case .commitNotFound:
            return "Commit not found in Cold Store"
        case .hashMismatch:
            return "Commit hash does not match content"
        case .fileWriteError(let path):
            return "Failed to write commit file: \(path)"
        case .fileReadError(let path):
            return "Failed to read commit file: \(path)"
        case .encodingError:
            return "Failed to encode commit content"
        case .decodingError:
            return "Failed to decode commit content"
        case .invalidName(let name):
            return "Invalid commit name: \(name)"
        case .nameAlreadyExists(let name):
            return "A commit named '\(name)' already exists"
        }
    }
}
