import Foundation
import GRDB

// MARK: - Media

/// Metadata for a media file stored in the Cold Store.
/// The actual file content is stored in the media directory using content-addressable storage.
struct Media: Codable, Identifiable, Hashable {
    var hash: String       // SHA-256 hash of content (primary key)
    var filename: String   // Original filename
    var mimeType: String   // MIME type (e.g., "image/png", "video/mp4")
    var size: Int64        // File size in bytes
    var createdAt: Int64   // When this media was first added

    var id: String { hash }

    init(
        hash: String,
        filename: String,
        mimeType: String,
        size: Int64,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.hash = hash
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.createdAt = createdAt
    }

    /// Create from a MediaReference
    init(from ref: MediaReference, createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.hash = ref.hash
        self.filename = ref.filename
        self.mimeType = ref.mimeType
        self.size = ref.size
        self.createdAt = createdAt
    }

    /// Convert to MediaReference for commit snapshots
    func toReference() -> MediaReference {
        MediaReference(
            hash: hash,
            filename: filename,
            mimeType: mimeType,
            size: size
        )
    }
}

// MARK: - GRDB Conformance

extension Media: FetchableRecord, PersistableRecord {
    static let databaseTableName = "media"

    enum Columns: String, ColumnExpression {
        case hash, filename, mimeType, size, createdAt
    }

    // Relationships
    static let noteMedias = hasMany(NoteMedia.self)
    static let notes = hasMany(Note.self, through: noteMedias, using: NoteMedia.note)
}

// MARK: - Media Utilities

extension Media {
    /// Whether this media is an image
    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    /// Whether this media is a video
    var isVideo: Bool {
        mimeType.hasPrefix("video/")
    }

    /// Whether this media is audio
    var isAudio: Bool {
        mimeType.hasPrefix("audio/")
    }

    /// File extension based on MIME type
    var fileExtension: String {
        switch mimeType {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "audio/mpeg": return "mp3"
        case "audio/wav": return "wav"
        case "application/pdf": return "pdf"
        default:
            // Try to extract from filename
            return URL(fileURLWithPath: filename).pathExtension
        }
    }

    /// Human-readable file size
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - NoteMedia (Junction Table)

/// Junction table linking notes to their media files.
/// Enables many-to-many relationship between notes and media.
struct NoteMedia: Codable, Hashable {
    var noteId: String
    var mediaHash: String

    init(noteId: String, mediaHash: String) {
        self.noteId = noteId
        self.mediaHash = mediaHash
    }
}

// MARK: - GRDB Conformance

extension NoteMedia: FetchableRecord, PersistableRecord {
    static let databaseTableName = "note_media"

    enum Columns: String, ColumnExpression {
        case noteId, mediaHash
    }

    // Relationships
    static let note = belongsTo(Note.self)
    static let media = belongsTo(Media.self, using: ForeignKey(["mediaHash"], to: ["hash"]))

    var note: QueryInterfaceRequest<Note> {
        request(for: NoteMedia.note)
    }

    var media: QueryInterfaceRequest<Media> {
        request(for: NoteMedia.media)
    }
}

// MARK: - MediaError

enum MediaError: Error, LocalizedError {
    case fileNotFound(String)
    case hashMismatch
    case unsupportedType(String)
    case writeFailed(String)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let hash):
            return "Media file not found: \(hash)"
        case .hashMismatch:
            return "Media content hash does not match"
        case .unsupportedType(let type):
            return "Unsupported media type: \(type)"
        case .writeFailed(let path):
            return "Failed to write media file: \(path)"
        case .readFailed(let path):
            return "Failed to read media file: \(path)"
        }
    }
}
