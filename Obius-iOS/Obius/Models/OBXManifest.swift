import Foundation

/// Manifest embedded in zip-format .obx archives for integrity verification.
struct OBXManifest: Codable {
    let formatVersion: Int
    let commitHash: String
    let contentHashes: [String: String]
    let mediaHashes: [String: String]
    let archiveHash: String

    init(
        formatVersion: Int = 2,
        commitHash: String,
        contentHashes: [String: String],
        mediaHashes: [String: String],
        archiveHash: String
    ) {
        self.formatVersion = formatVersion
        self.commitHash = commitHash
        self.contentHashes = contentHashes
        self.mediaHashes = mediaHashes
        self.archiveHash = archiveHash
    }
}
