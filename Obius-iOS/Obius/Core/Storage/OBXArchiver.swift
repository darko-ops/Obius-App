import Foundation
import CryptoKit
import ZIPFoundation

/// Result of reading a zip-format .obx archive.
struct OBXArchiveContents {
    let manifest: OBXManifest
    let commitJSON: Data
    let mediaEntries: [(path: String, data: Data)]
}

/// Builds, reads, and verifies zip-format .obx archives.
///
/// Archive structure:
/// ```
/// mycommit.obx (zip)
/// +-- manifest.json
/// +-- commit.json
/// +-- media/
///     +-- sha256_aaa111...
///     +-- sha256_bbb222...
/// ```
enum OBXArchiver {

    // MARK: - Format Detection

    /// Checks whether data begins with the zip magic bytes (`PK\x03\x04`).
    static func isZipArchive(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[data.startIndex] == 0x50       // P
            && data[data.startIndex + 1] == 0x4B   // K
            && data[data.startIndex + 2] == 0x03
            && data[data.startIndex + 3] == 0x04
    }

    // MARK: - Build

    /// Creates a zip archive containing `commit.json`, optional media entries, and a `manifest.json`.
    ///
    /// - Parameters:
    ///   - commitJSON: The encoded `CommitContent` JSON data.
    ///   - commitHash: The deterministic commit hash (e.g. `"sha256:abc123..."`).
    ///   - mediaEntries: Media blobs to embed. Each tuple is `(archivePath, rawData)`.
    ///                   Archive paths should be `"media/sha256_<hex>"`.
    /// - Returns: The complete zip archive as `Data`.
    static func buildArchive(
        commitJSON: Data,
        commitHash: String,
        mediaEntries: [(path: String, data: Data)]
    ) throws -> Data {
        // Collect all non-manifest entries for archive hash
        var entries: [(path: String, data: Data)] = [("commit.json", commitJSON)]
        entries.append(contentsOf: mediaEntries)

        // Sort by path for deterministic hashing
        let sorted = entries.sorted { $0.path < $1.path }

        // Compute per-entry SHA-256 hashes
        var contentHashes: [String: String] = [:]
        var mediaHashes: [String: String] = [:]

        contentHashes["commit.json"] = sha256String(commitJSON)

        for entry in mediaEntries {
            mediaHashes[entry.path] = sha256String(entry.data)
        }

        // Compute archive hash = SHA-256 of concatenated entry bytes in sorted path order
        var concatenated = Data()
        for entry in sorted {
            concatenated.append(entry.data)
        }
        let archiveHash = sha256String(concatenated)

        // Build manifest
        let manifest = OBXManifest(
            commitHash: commitHash,
            contentHashes: contentHashes,
            mediaHashes: mediaHashes,
            archiveHash: archiveHash
        )

        let manifestEncoder = JSONEncoder()
        manifestEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try manifestEncoder.encode(manifest)

        // Build zip in memory
        let archive = try Archive(accessMode: .create)

        try archive.addEntry(
            with: "manifest.json",
            type: .file,
            uncompressedSize: Int64(manifestData.count),
            provider: { position, size in
                let start = Int(position)
                return manifestData[start..<(start + size)]
            }
        )

        try archive.addEntry(
            with: "commit.json",
            type: .file,
            uncompressedSize: Int64(commitJSON.count),
            provider: { position, size in
                let start = Int(position)
                return commitJSON[start..<(start + size)]
            }
        )

        for entry in mediaEntries {
            let entryData = entry.data
            try archive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: Int64(entryData.count),
                provider: { position, size in
                    let start = Int(position)
                    return entryData[start..<(start + size)]
                }
            )
        }

        guard let archiveData = archive.data else {
            throw CommitError.encodingError
        }
        return archiveData
    }

    // MARK: - Read

    /// Reads and parses a zip-format .obx archive.
    ///
    /// - Parameter data: Raw bytes of the zip file.
    /// - Returns: Parsed archive contents including manifest, commit JSON, and media entries.
    static func readArchive(data: Data) throws -> OBXArchiveContents {
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw CommitError.archiveCorrupted("Failed to open zip archive: \(error.localizedDescription)")
        }

        // Extract manifest
        guard let manifestEntry = archive["manifest.json"] else {
            throw CommitError.manifestMissing
        }
        var manifestData = Data()
        _ = try archive.extract(manifestEntry) { chunk in manifestData.append(chunk) }

        let manifest: OBXManifest
        do {
            manifest = try JSONDecoder().decode(OBXManifest.self, from: manifestData)
        } catch {
            throw CommitError.archiveCorrupted("Invalid manifest.json: \(error.localizedDescription)")
        }

        // Extract commit.json
        guard let commitEntry = archive["commit.json"] else {
            throw CommitError.archiveCorrupted("Missing commit.json in archive")
        }
        var commitData = Data()
        _ = try archive.extract(commitEntry) { chunk in commitData.append(chunk) }

        // Extract media entries
        var mediaEntries: [(path: String, data: Data)] = []
        for entry in archive {
            guard entry.path.hasPrefix("media/"), entry.type == .file else { continue }
            var entryData = Data()
            _ = try archive.extract(entry) { chunk in entryData.append(chunk) }
            mediaEntries.append((path: entry.path, data: entryData))
        }

        return OBXArchiveContents(
            manifest: manifest,
            commitJSON: commitData,
            mediaEntries: mediaEntries
        )
    }

    // MARK: - Verify

    /// Verifies that all manifest hashes match the actual archive contents.
    ///
    /// - Parameter data: Raw bytes of the zip file.
    /// - Returns: `true` if all hashes match.
    static func verifyArchive(data: Data) throws -> Bool {
        let contents = try readArchive(data: data)
        let manifest = contents.manifest

        // Verify commit.json hash
        if let expectedHash = manifest.contentHashes["commit.json"] {
            let actual = sha256String(contents.commitJSON)
            guard actual == expectedHash else {
                throw CommitError.manifestHashMismatch(
                    entry: "commit.json", expected: expectedHash, actual: actual
                )
            }
        }

        // Verify media hashes
        for (path, entryData) in contents.mediaEntries {
            if let expectedHash = manifest.mediaHashes[path] {
                let actual = sha256String(entryData)
                guard actual == expectedHash else {
                    throw CommitError.manifestHashMismatch(
                        entry: path, expected: expectedHash, actual: actual
                    )
                }
            }
        }

        // Verify archive hash
        var allEntries: [(path: String, data: Data)] = [("commit.json", contents.commitJSON)]
        allEntries.append(contentsOf: contents.mediaEntries)
        let sorted = allEntries.sorted { $0.path < $1.path }

        var concatenated = Data()
        for entry in sorted {
            concatenated.append(entry.data)
        }
        let computedArchiveHash = sha256String(concatenated)

        guard computedArchiveHash == manifest.archiveHash else {
            throw CommitError.manifestHashMismatch(
                entry: "archive", expected: manifest.archiveHash, actual: computedArchiveHash
            )
        }

        return true
    }

    // MARK: - Helpers

    /// Decodes `CommitContent` from raw .obx data, handling both zip and legacy JSON formats.
    static func decodeCommitContent(from data: Data) throws -> CommitContent {
        if isZipArchive(data) {
            let contents = try readArchive(data: data)
            return try JSONDecoder().decode(CommitContent.self, from: contents.commitJSON)
        } else {
            return try JSONDecoder().decode(CommitContent.self, from: data)
        }
    }

    private static func sha256String(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}
