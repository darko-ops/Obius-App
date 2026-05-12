import Foundation
import CryptoKit

/// ColdStore manages the file-system-based vault for immutable commits.
/// It provides content-addressable storage for both .obx commit files and media files.
@MainActor
class ColdStore: ObservableObject {
    static let shared = ColdStore()

    private let fileManager = FileManager.default

    /// The user this store is currently scoped to. `nil` means anonymous.
    private(set) var userId: String?

    /// Directory for .obx commit files (per-user)
    private var vaultDirectory: URL

    /// Directory for content-addressable media files (per-user)
    private var mediaDirectory: URL

    init() {
        let userId: String? = nil
        let dirs = Self.directories(forUserId: userId)
        self.userId = userId
        self.vaultDirectory = dirs.vault
        self.mediaDirectory = dirs.media
        createDirectoriesIfNeeded()
    }

    /// Initialize with custom directories (for testing)
    init(vaultDirectory: URL, mediaDirectory: URL) {
        self.userId = nil
        self.vaultDirectory = vaultDirectory
        self.mediaDirectory = mediaDirectory
        createDirectoriesIfNeeded()
    }

    /// Returns per-user vault and media directories. Anonymous users get a
    /// dedicated `users/anon` scope so account A's commits never appear in B.
    private static func directories(forUserId userId: String?) -> (vault: URL, media: URL) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let scope = (userId?.isEmpty == false ? userId!.lowercased() : "anon")
        let userRoot = documents
            .appendingPathComponent("users", isDirectory: true)
            .appendingPathComponent(scope, isDirectory: true)
        return (
            vault: userRoot.appendingPathComponent("vault", isDirectory: true),
            media: userRoot.appendingPathComponent("media", isDirectory: true)
        )
    }

    /// Re-point the Cold Store at a different user's directories. Existing
    /// commits/media are not touched — each scope keeps its own files.
    func switchUser(_ userId: String?) {
        guard userId != self.userId else { return }
        let dirs = Self.directories(forUserId: userId)
        self.userId = userId
        self.vaultDirectory = dirs.vault
        self.mediaDirectory = dirs.media
        createDirectoriesIfNeeded()
    }

    private func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
    }

    /// One-time migration from the legacy single-tenant `Documents/vault` and
    /// `Documents/media` into the current user's scoped directory. Safe to call
    /// repeatedly — only runs while legacy directories still exist and the
    /// destination is empty.
    static func migrateLegacyDirectoriesIfNeeded(currentUserId: String?) {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let legacyVault = documents.appendingPathComponent("vault", isDirectory: true)
        let legacyMedia = documents.appendingPathComponent("media", isDirectory: true)

        let dirs = directories(forUserId: currentUserId)

        for (legacy, destination) in [(legacyVault, dirs.vault), (legacyMedia, dirs.media)] {
            guard fm.fileExists(atPath: legacy.path) else { continue }

            // If destination doesn't exist yet, just rename the whole tree.
            if !fm.fileExists(atPath: destination.path) {
                try? fm.createDirectory(at: destination.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
                do {
                    try fm.moveItem(at: legacy, to: destination)
                    print("[ColdStore] Migrated legacy \(legacy.lastPathComponent) → \(destination.path)")
                    continue
                } catch {
                    print("[ColdStore] Migration move failed for \(legacy.lastPathComponent): \(error)")
                }
            }

            // Otherwise merge contents and remove the legacy dir if empty.
            if let contents = try? fm.contentsOfDirectory(atPath: legacy.path) {
                try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
                for item in contents {
                    let src = legacy.appendingPathComponent(item)
                    let dst = destination.appendingPathComponent(item)
                    if !fm.fileExists(atPath: dst.path) {
                        try? fm.moveItem(at: src, to: dst)
                    }
                }
                if let remaining = try? fm.contentsOfDirectory(atPath: legacy.path), remaining.isEmpty {
                    try? fm.removeItem(at: legacy)
                }
            }
        }
    }

    // MARK: - Commit Storage

    /// Writes a commit to the Cold Store.
    /// Uses git-style sharding: first 2 chars of hash as subdirectory.
    /// - Parameter content: The commit content to write
    /// - Returns: The relative file path within the vault
    func writeCommit(_ content: CommitContent) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let commitJSON = try? encoder.encode(content) else {
            throw CommitError.encodingError
        }

        // Gather referenced media from the media/ directory
        var mediaEntries: [(path: String, data: Data)] = []
        for ref in content.mediaRefs {
            let hashValue = ref.hash.replacingOccurrences(of: "sha256:", with: "")
            if let mediaData = try? readMedia(hash: ref.hash) {
                mediaEntries.append((path: "media/sha256_\(hashValue)", data: mediaData))
            }
        }

        // Build zip archive
        let archiveData = try OBXArchiver.buildArchive(
            commitJSON: commitJSON,
            commitHash: content.hash,
            mediaEntries: mediaEntries
        )

        // Extract hash value (remove "sha256:" prefix)
        let hashValue = content.hash.replacingOccurrences(of: "sha256:", with: "")

        // Use first 2 chars as subdirectory (git-style sharding)
        let hashPrefix = String(hashValue.prefix(2))
        let subdir = vaultDirectory.appendingPathComponent(hashPrefix, isDirectory: true)

        // Create subdirectory if needed
        try? fileManager.createDirectory(at: subdir, withIntermediateDirectories: true)

        // Create .obx file
        let filename = "\(hashValue).obx"
        let fileURL = subdir.appendingPathComponent(filename)
        let relativePath = "\(hashPrefix)/\(filename)"

        do {
            try archiveData.write(to: fileURL, options: .atomic)
        } catch {
            throw CommitError.fileWriteError(relativePath)
        }

        return relativePath
    }

    /// Reads a commit from the Cold Store by hash.
    /// - Parameter hash: The commit hash (with or without "sha256:" prefix)
    /// - Returns: The decoded commit content
    func readCommit(hash: String) throws -> CommitContent {
        let hashValue = hash.replacingOccurrences(of: "sha256:", with: "")
        let hashPrefix = String(hashValue.prefix(2))
        let fileURL = vaultDirectory
            .appendingPathComponent(hashPrefix, isDirectory: true)
            .appendingPathComponent("\(hashValue).obx")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw CommitError.commitNotFound
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try OBXArchiver.decodeCommitContent(from: data)
        } catch let error as CommitError {
            throw error
        } catch is DecodingError {
            throw CommitError.decodingError
        } catch {
            throw CommitError.fileReadError(fileURL.lastPathComponent)
        }
    }

    /// Reads a commit from the Cold Store by relative file path.
    /// - Parameter filePath: The relative path within the vault (e.g., "ab/abc123.obx")
    /// - Returns: The decoded commit content
    func readCommit(filePath: String) throws -> CommitContent {
        let fileURL = vaultDirectory.appendingPathComponent(filePath)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw CommitError.commitNotFound
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try OBXArchiver.decodeCommitContent(from: data)
        } catch let error as CommitError {
            throw error
        } catch is DecodingError {
            throw CommitError.decodingError
        } catch {
            throw CommitError.fileReadError(filePath)
        }
    }

    /// Checks if a commit exists in the Cold Store.
    /// - Parameter hash: The commit hash to check
    /// - Returns: true if the commit file exists
    func commitExists(hash: String) -> Bool {
        let hashValue = hash.replacingOccurrences(of: "sha256:", with: "")
        let hashPrefix = String(hashValue.prefix(2))
        let fileURL = vaultDirectory
            .appendingPathComponent(hashPrefix, isDirectory: true)
            .appendingPathComponent("\(hashValue).obx")

        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Deletes a commit from the Cold Store.
    /// - Parameter hash: The commit hash to delete
    func deleteCommit(hash: String) throws {
        let hashValue = hash.replacingOccurrences(of: "sha256:", with: "")
        let hashPrefix = String(hashValue.prefix(2))
        let fileURL = vaultDirectory
            .appendingPathComponent(hashPrefix, isDirectory: true)
            .appendingPathComponent("\(hashValue).obx")

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Media Storage

    /// Writes media data to the Cold Store with content-addressable deduplication.
    /// - Parameters:
    ///   - data: The raw media data
    ///   - filename: The original filename
    ///   - mimeType: The MIME type of the media
    /// - Returns: A MediaReference with the computed hash
    func writeMedia(data: Data, filename: String, mimeType: String) throws -> MediaReference {
        let hash = computeHash(data)
        let hashValue = hash.replacingOccurrences(of: "sha256:", with: "")
        let hashPrefix = String(hashValue.prefix(2))

        let subdir = mediaDirectory.appendingPathComponent(hashPrefix, isDirectory: true)
        try? fileManager.createDirectory(at: subdir, withIntermediateDirectories: true)

        let fileURL = subdir.appendingPathComponent(hashValue)

        // Only write if file doesn't exist (content-addressable deduplication)
        if !fileManager.fileExists(atPath: fileURL.path) {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                throw MediaError.writeFailed(fileURL.path)
            }
        }

        return MediaReference(
            hash: hash,
            filename: filename,
            mimeType: mimeType,
            size: Int64(data.count)
        )
    }

    /// Reads media data from the Cold Store by hash.
    /// - Parameter hash: The media hash (with or without "sha256:" prefix)
    /// - Returns: The raw media data
    func readMedia(hash: String) throws -> Data {
        let hashValue = hash.replacingOccurrences(of: "sha256:", with: "")
        let hashPrefix = String(hashValue.prefix(2))
        let fileURL = mediaDirectory
            .appendingPathComponent(hashPrefix, isDirectory: true)
            .appendingPathComponent(hashValue)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw MediaError.fileNotFound(hash)
        }

        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw MediaError.readFailed(fileURL.path)
        }
    }

    /// Checks if media exists in the Cold Store.
    /// - Parameter hash: The media hash to check
    /// - Returns: true if the media file exists
    func mediaExists(hash: String) -> Bool {
        let hashValue = hash.replacingOccurrences(of: "sha256:", with: "")
        let hashPrefix = String(hashValue.prefix(2))
        let fileURL = mediaDirectory
            .appendingPathComponent(hashPrefix, isDirectory: true)
            .appendingPathComponent(hashValue)

        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Deletes media from the Cold Store.
    /// - Parameter hash: The media hash to delete
    func deleteMedia(hash: String) throws {
        let hashValue = hash.replacingOccurrences(of: "sha256:", with: "")
        let hashPrefix = String(hashValue.prefix(2))
        let fileURL = mediaDirectory
            .appendingPathComponent(hashPrefix, isDirectory: true)
            .appendingPathComponent(hashValue)

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Hash Computation

    /// Computes the SHA-256 hash of data.
    /// - Parameter data: The data to hash
    /// - Returns: The hash string with "sha256:" prefix
    func computeHash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hashString = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hashString)"
    }

    /// Computes the content hash for a commit.
    /// Uses sorted JSON encoding for deterministic hashing.
    /// - Parameter content: The content to hash (parentHash, note, sections, mediaRefs)
    /// - Returns: The hash string with "sha256:" prefix
    func computeCommitHash(
        parentHash: String?,
        note: CommitNoteSnapshot,
        sections: [CommitSectionSnapshot],
        mediaRefs: [MediaReference]
    ) -> String {
        let hashContent = CommitHashContent(
            parentHash: parentHash,
            note: note,
            sections: sections,
            mediaRefs: mediaRefs
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        guard let data = try? encoder.encode(hashContent) else {
            return "sha256:error"
        }

        return computeHash(data)
    }

    /// Clears all data from the Cold Store.
    /// WARNING: This is destructive and cannot be undone.
    func clearAll() throws {
        try fileManager.removeItem(at: vaultDirectory)
        try fileManager.removeItem(at: mediaDirectory)
        createDirectoriesIfNeeded()
    }
}
