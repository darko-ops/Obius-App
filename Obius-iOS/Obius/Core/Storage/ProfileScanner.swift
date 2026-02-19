import Foundation

/// ProfileScanner (Ledger) scans the Cold Store and maintains the commit index.
/// It can rebuild the Hot Store index from Cold Store files and verify integrity.
@MainActor
class ProfileScanner: ObservableObject {
    private let coldStore: ColdStore
    private let commitRepository: CommitRepository

    @Published var isScanning = false
    @Published var lastScanDate: Date?
    @Published var scanProgress: Double = 0

    // Scan results
    @Published var totalCommits = 0
    @Published var totalNotes = 0
    @Published var totalMediaRefs = 0

    init(coldStore: ColdStore, commitRepository: CommitRepository) {
        self.coldStore = coldStore
        self.commitRepository = commitRepository
    }

    // MARK: - Scan and Rebuild Index

    /// Scans the Cold Store and rebuilds the commit index in Hot Store.
    /// This is useful for recovering from database corruption or syncing from another device.
    /// - Returns: ScanResult with statistics
    @discardableResult
    func scanAndRebuildIndex() async throws -> ScanResult {
        isScanning = true
        scanProgress = 0
        defer {
            isScanning = false
            lastScanDate = Date()
        }

        // Clear existing index
        try await commitRepository.deleteAllCommits()

        let files = coldStore.getAllCommitFiles()
        var noteIds = Set<String>()
        var processedCount = 0
        var errorCount = 0
        var mediaRefCount = 0
        var errors: [ScanError] = []

        for (index, fileURL) in files.enumerated() {
            scanProgress = Double(index + 1) / Double(files.count)

            do {
                let data = try Data(contentsOf: fileURL)
                let content = try OBXArchiver.decodeCommitContent(from: data)

                // Extract relative path
                let relativePath = extractRelativePath(from: fileURL)

                // Create commit record
                let commit = Commit(
                    noteId: content.note.id,
                    hash: content.hash,
                    parentHash: content.parentHash,
                    filePath: relativePath,
                    createdAt: content.createdAt
                )

                try await commitRepository.saveCommit(commit)
                noteIds.insert(content.note.id)
                mediaRefCount += content.mediaRefs.count
                processedCount += 1
            } catch {
                errorCount += 1
                errors.append(ScanError(
                    filePath: fileURL.lastPathComponent,
                    error: error.localizedDescription
                ))
            }
        }

        totalCommits = processedCount
        totalNotes = noteIds.count
        totalMediaRefs = mediaRefCount

        return ScanResult(
            commitsProcessed: processedCount,
            uniqueNotes: noteIds.count,
            mediaReferences: mediaRefCount,
            errorCount: errorCount,
            errors: errors
        )
    }

    /// Incrementally scans for new commits not in the index.
    /// - Returns: Number of new commits found
    func incrementalScan() async throws -> Int {
        isScanning = true
        defer { isScanning = false }

        let files = coldStore.getAllCommitFiles()
        var newCommits = 0

        for fileURL in files {
            // Extract hash from filename
            let filename = fileURL.deletingPathExtension().lastPathComponent
            let hash = "sha256:\(filename)"

            // Check if already indexed
            if let _ = try await commitRepository.getCommit(hash: hash) {
                continue
            }

            // Index this commit
            do {
                let data = try Data(contentsOf: fileURL)
                let content = try OBXArchiver.decodeCommitContent(from: data)

                let relativePath = extractRelativePath(from: fileURL)

                let commit = Commit(
                    noteId: content.note.id,
                    hash: content.hash,
                    parentHash: content.parentHash,
                    filePath: relativePath,
                    createdAt: content.createdAt
                )

                try await commitRepository.saveCommit(commit)
                newCommits += 1
            } catch {
                print("Failed to index commit: \(fileURL.lastPathComponent), error: \(error)")
            }
        }

        return newCommits
    }

    // MARK: - Commit Chain

    /// Gets the full commit chain for a note, with content from Cold Store.
    /// - Parameter noteId: The note ID
    /// - Returns: Array of CommitContent, newest first
    func getCommitChain(noteId: String) async throws -> [CommitContent] {
        let commits = try await commitRepository.getCommits(noteId: noteId)

        return commits.compactMap { commit in
            try? coldStore.readCommit(hash: commit.hash)
        }
    }

    /// Gets commit content with metadata for display.
    /// - Parameter noteId: The note ID
    /// - Returns: Array of CommitWithContent
    func getCommitHistoryWithContent(noteId: String) async throws -> [CommitWithContent] {
        let commits = try await commitRepository.getCommits(noteId: noteId)

        return commits.compactMap { commit -> CommitWithContent? in
            guard let content = try? coldStore.readCommit(hash: commit.hash) else {
                return nil
            }
            return CommitWithContent(commit: commit, content: content)
        }
    }

    // MARK: - Integrity Verification

    /// Verifies the integrity of all commits in the Cold Store.
    /// Checks that stored hashes match computed hashes.
    /// - Returns: IntegrityReport with results
    func verifyIntegrity() async throws -> IntegrityReport {
        isScanning = true
        scanProgress = 0
        defer { isScanning = false }

        let files = coldStore.getAllCommitFiles()
        var validCount = 0
        var invalidCount = 0
        var orphanedCount = 0
        var missingParentCount = 0
        var errors: [IntegrityError] = []

        for (index, fileURL) in files.enumerated() {
            scanProgress = Double(index + 1) / Double(files.count)

            do {
                let data = try Data(contentsOf: fileURL)
                let content = try OBXArchiver.decodeCommitContent(from: data)

                // Verify hash matches content
                let computedHash = coldStore.computeCommitHash(
                    parentHash: content.parentHash,
                    note: content.note,
                    sections: content.sections,
                    mediaRefs: content.mediaRefs
                )

                if computedHash != content.hash {
                    invalidCount += 1
                    errors.append(IntegrityError(
                        hash: content.hash,
                        type: .hashMismatch,
                        message: "Computed hash \(computedHash) does not match stored hash"
                    ))
                } else {
                    validCount += 1
                }

                // Verify manifest hashes for zip-format archives
                if OBXArchiver.isZipArchive(data) {
                    do {
                        _ = try OBXArchiver.verifyArchive(data: data)
                    } catch {
                        errors.append(IntegrityError(
                            hash: content.hash,
                            type: .hashMismatch,
                            message: "Archive manifest verification failed: \(error.localizedDescription)"
                        ))
                    }
                }

                // Check for missing parent
                if let parentHash = content.parentHash {
                    if !coldStore.commitExists(hash: parentHash) {
                        missingParentCount += 1
                        errors.append(IntegrityError(
                            hash: content.hash,
                            type: .missingParent,
                            message: "Parent commit \(parentHash) not found"
                        ))
                    }
                }

                // Check if indexed in Hot Store
                if let _ = try await commitRepository.getCommit(hash: content.hash) {
                    // Indexed
                } else {
                    orphanedCount += 1
                    errors.append(IntegrityError(
                        hash: content.hash,
                        type: .notIndexed,
                        message: "Commit exists in Cold Store but not indexed in Hot Store"
                    ))
                }
            } catch {
                invalidCount += 1
                errors.append(IntegrityError(
                    hash: fileURL.lastPathComponent,
                    type: .readError,
                    message: error.localizedDescription
                ))
            }
        }

        return IntegrityReport(
            validCount: validCount,
            invalidCount: invalidCount,
            orphanedCount: orphanedCount,
            missingParentCount: missingParentCount,
            errors: errors
        )
    }

    /// Verifies integrity of a specific commit.
    /// - Parameter hash: The commit hash to verify
    /// - Returns: true if the commit is valid
    func verifyCommit(hash: String) throws -> Bool {
        let content = try coldStore.readCommit(hash: hash)

        let computedHash = coldStore.computeCommitHash(
            parentHash: content.parentHash,
            note: content.note,
            sections: content.sections,
            mediaRefs: content.mediaRefs
        )

        return computedHash == content.hash
    }

    // MARK: - Statistics

    /// Gets storage statistics from both Hot and Cold stores.
    /// - Returns: StorageStats with combined statistics
    func getStorageStats() async throws -> StorageStats {
        let hotStoreCommits = try await commitRepository.getTotalCommitCount()
        let (coldCommits, mediaFiles, totalBytes) = coldStore.getStorageStats()

        return StorageStats(
            hotStoreCommits: hotStoreCommits,
            coldStoreCommits: coldCommits,
            mediaFiles: mediaFiles,
            totalBytes: totalBytes,
            isInSync: hotStoreCommits == coldCommits
        )
    }

    // MARK: - Private Helpers

    private func extractRelativePath(from url: URL) -> String {
        // URL format: .../vault/ab/abc123.obx
        // We want: ab/abc123.obx
        let components = url.pathComponents
        guard components.count >= 2 else {
            return url.lastPathComponent
        }
        let hashPrefix = components[components.count - 2]
        let filename = components[components.count - 1]
        return "\(hashPrefix)/\(filename)"
    }
}

// MARK: - Supporting Types

struct ScanResult {
    let commitsProcessed: Int
    let uniqueNotes: Int
    let mediaReferences: Int
    let errorCount: Int
    let errors: [ScanError]

    var summary: String {
        var parts = ["\(commitsProcessed) commits processed"]
        parts.append("\(uniqueNotes) unique notes")
        if mediaReferences > 0 {
            parts.append("\(mediaReferences) media references")
        }
        if errorCount > 0 {
            parts.append("\(errorCount) errors")
        }
        return parts.joined(separator: ", ")
    }
}

struct ScanError {
    let filePath: String
    let error: String
}

struct IntegrityReport {
    let validCount: Int
    let invalidCount: Int
    let orphanedCount: Int
    let missingParentCount: Int
    let errors: [IntegrityError]

    var isHealthy: Bool {
        invalidCount == 0 && orphanedCount == 0
    }

    var summary: String {
        if isHealthy {
            return "\(validCount) commits verified, all healthy"
        }

        var parts = ["\(validCount) valid"]
        if invalidCount > 0 {
            parts.append("\(invalidCount) invalid")
        }
        if orphanedCount > 0 {
            parts.append("\(orphanedCount) not indexed")
        }
        if missingParentCount > 0 {
            parts.append("\(missingParentCount) missing parents")
        }
        return parts.joined(separator: ", ")
    }
}

struct IntegrityError {
    let hash: String
    let type: IntegrityErrorType
    let message: String
}

enum IntegrityErrorType {
    case hashMismatch
    case missingParent
    case notIndexed
    case readError
}

struct StorageStats {
    let hotStoreCommits: Int
    let coldStoreCommits: Int
    let mediaFiles: Int
    let totalBytes: Int64

    let isInSync: Bool

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }
}

struct CommitWithContent {
    let commit: Commit
    let content: CommitContent

    var displayDate: Date {
        Date(timeIntervalSince1970: Double(commit.createdAt) / 1000)
    }

    var sectionCount: Int {
        content.sections.count
    }

    var hasMedia: Bool {
        !content.mediaRefs.isEmpty
    }
}
