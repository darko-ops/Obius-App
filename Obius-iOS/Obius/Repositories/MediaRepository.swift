import Foundation
import GRDB
import Combine

/// Repository for managing Media records and note-media relationships.
/// Works with ColdStore for content-addressable media storage.
/// Syncs media to/from Supabase Storage for cross-device availability.
@MainActor
final class MediaRepository: ObservableObject {
    private let database: DatabaseManager
    private let coldStore: ColdStore
    private static let storageBucket = "note-media"

    init(database: DatabaseManager, coldStore: ColdStore) {
        self.database = database
        self.coldStore = coldStore
    }

    // MARK: - Add Media

    /// Adds media data to the Cold Store and records it in the Hot Store.
    /// Uses content-addressable storage for automatic deduplication.
    /// - Parameters:
    ///   - data: The raw media data
    ///   - filename: The original filename
    ///   - mimeType: The MIME type (e.g., "image/png")
    /// - Returns: The created Media record
    func addMedia(data: Data, filename: String, mimeType: String) async throws -> Media {
        // Write to Cold Store (handles deduplication)
        let ref = try coldStore.writeMedia(data: data, filename: filename, mimeType: mimeType)

        // Create Media record
        let media = Media(from: ref)

        // Save to Hot Store (ignore conflict if already exists - same content = same hash)
        try await database.write { db in
            try media.insert(db, onConflict: .ignore)
        }

        // Upload to cloud storage for cross-device sync (fire and forget)
        let hash = media.hash
        let mime = mimeType
        Task.detached {
            await MediaRepository.uploadToCloud(data: data, hash: hash, mimeType: mime)
        }

        return media
    }

    /// Adds a media reference without the actual data (for commit restoration).
    /// - Parameter ref: The media reference from a commit
    /// - Returns: The created Media record
    func addMediaReference(_ ref: MediaReference) async throws -> Media {
        let media = Media(from: ref)

        try await database.write { db in
            try media.insert(db, onConflict: .ignore)
        }

        return media
    }

    // MARK: - Link Media to Notes

    /// Links a media file to a note.
    /// - Parameters:
    ///   - noteId: The note ID
    ///   - mediaHash: The media hash to link
    func linkMediaToNote(noteId: String, mediaHash: String) async throws {
        let noteMedia = NoteMedia(noteId: noteId, mediaHash: mediaHash)

        try await database.write { db in
            try noteMedia.insert(db, onConflict: .ignore)
        }
    }

    /// Unlinks a media file from a note.
    /// - Parameters:
    ///   - noteId: The note ID
    ///   - mediaHash: The media hash to unlink
    func unlinkMediaFromNote(noteId: String, mediaHash: String) async throws {
        try await database.write { db in
            _ = try NoteMedia
                .filter(NoteMedia.Columns.noteId == noteId)
                .filter(NoteMedia.Columns.mediaHash == mediaHash)
                .deleteAll(db)
        }
    }

    /// Unlinks all media from a note.
    /// - Parameter noteId: The note ID
    func unlinkAllMediaFromNote(noteId: String) async throws {
        try await database.write { db in
            _ = try NoteMedia
                .filter(NoteMedia.Columns.noteId == noteId)
                .deleteAll(db)
        }
    }

    // MARK: - Read

    /// Gets media by hash.
    /// - Parameter hash: The media hash
    /// - Returns: The Media record if found
    func getMedia(hash: String) async throws -> Media? {
        try await database.read { db in
            try Media.fetchOne(db, key: hash)
        }
    }

    /// Gets all media linked to a note.
    /// - Parameter noteId: The note ID
    /// - Returns: Array of Media records
    func getMediaForNote(noteId: String) async throws -> [Media] {
        try await database.read { db in
            try Media
                .joining(required: Media.noteMedias.filter(NoteMedia.Columns.noteId == noteId))
                .fetchAll(db)
        }
    }

    /// Gets media references for a note (suitable for commit snapshots).
    /// - Parameter noteId: The note ID
    /// - Returns: Array of MediaReference objects
    func getMediaReferencesForNote(noteId: String) async throws -> [MediaReference] {
        let media = try await getMediaForNote(noteId: noteId)
        return media.map { $0.toReference() }
    }

    /// Gets all media in the database.
    /// - Returns: Array of all Media records
    func getAllMedia() async throws -> [Media] {
        try await database.read { db in
            try Media
                .order(Media.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Read Media Data

    /// Reads the actual media data from Cold Store.
    /// - Parameter hash: The media hash
    /// - Returns: The raw media data
    func getMediaData(hash: String) throws -> Data {
        try coldStore.readMedia(hash: hash)
    }

    /// Reads media data, falling back to cloud download if missing locally.
    /// - Parameter hash: The media hash
    /// - Returns: The raw media data, or nil if unavailable
    func getMediaDataWithCloudFallback(hash: String) async -> Data? {
        // Try local first
        if let data = try? coldStore.readMedia(hash: hash) {
            return data
        }

        // Try downloading from cloud
        return await MediaRepository.downloadFromCloud(hash: hash, coldStore: coldStore)
    }

    /// Checks if media data exists in Cold Store.
    /// - Parameter hash: The media hash
    /// - Returns: true if the media file exists
    func mediaDataExists(hash: String) -> Bool {
        coldStore.mediaExists(hash: hash)
    }

    // MARK: - Cloud Storage

    /// Uploads media data to Supabase Storage for cross-device sync.
    private static func uploadToCloud(data: Data, hash: String, mimeType: String) async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id.uuidString.lowercased() else { return }

        let hashValue = hash.replacingOccurrences(of: "sha256:", with: "")
        let path = "\(userId)/\(hashValue)"

        do {
            try await SupabaseManager.shared.client.storage
                .from(storageBucket)
                .upload(
                    path: path,
                    file: data,
                    options: .init(contentType: mimeType, upsert: true)
                )
            print("[Media] Uploaded \(hashValue.prefix(12)) to cloud (\(data.count) bytes)")
        } catch {
            print("[Media] Cloud upload failed for \(hashValue.prefix(12)): \(error.localizedDescription)")
        }
    }

    /// Uploads all existing local media to cloud storage (one-time migration).
    /// Call on app launch to ensure media created before cloud sync was added gets uploaded.
    func syncExistingMediaToCloud() async {
        let syncKey = "hasUploadedExistingMedia_v1"
        guard !UserDefaults.standard.bool(forKey: syncKey) else { return }
        guard SupabaseManager.shared.isAuthenticated else { return }

        do {
            let allMedia = try await getAllMedia()
            guard !allMedia.isEmpty else {
                UserDefaults.standard.set(true, forKey: syncKey)
                return
            }

            var uploaded = 0
            for media in allMedia {
                guard let data = try? coldStore.readMedia(hash: media.hash) else { continue }
                await MediaRepository.uploadToCloud(data: data, hash: media.hash, mimeType: media.mimeType)
                uploaded += 1
            }
            print("[Media] Uploaded \(uploaded)/\(allMedia.count) existing media files to cloud")
            UserDefaults.standard.set(true, forKey: syncKey)
        } catch {
            print("[Media] Failed to sync existing media: \(error.localizedDescription)")
        }
    }

    /// Downloads media data from Supabase Storage and saves to local Cold Store.
    private static func downloadFromCloud(hash: String, coldStore: ColdStore) async -> Data? {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id.uuidString.lowercased() else { return nil }

        let hashValue = hash.replacingOccurrences(of: "sha256:", with: "")
        let path = "\(userId)/\(hashValue)"

        do {
            let data = try await SupabaseManager.shared.client.storage
                .from(storageBucket)
                .download(path: path)

            // Save to local Cold Store so subsequent reads are instant
            _ = try? coldStore.writeMedia(data: data, filename: hashValue, mimeType: "image/jpeg")
            print("[Media] Downloaded \(hashValue.prefix(12)) from cloud (\(data.count) bytes)")
            return data
        } catch {
            print("[Media] Cloud download failed for \(hashValue.prefix(12)): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Delete

    /// Deletes a media record from the Hot Store.
    /// Note: Does not delete the actual file from Cold Store.
    /// - Parameter hash: The media hash to delete
    func deleteMediaRecord(hash: String) async throws {
        try await database.write { db in
            // First remove all note links
            _ = try NoteMedia
                .filter(NoteMedia.Columns.mediaHash == hash)
                .deleteAll(db)

            // Then remove the media record
            _ = try Media.deleteOne(db, key: hash)
        }
    }

    /// Deletes media data from Cold Store.
    /// Warning: This is destructive and should only be done for orphaned media.
    /// - Parameter hash: The media hash to delete
    func deleteMediaData(hash: String) throws {
        try coldStore.deleteMedia(hash: hash)
    }

    /// Deletes both the media record and data.
    /// - Parameter hash: The media hash to delete
    func deleteMedia(hash: String) async throws {
        try await deleteMediaRecord(hash: hash)
        try deleteMediaData(hash: hash)
    }

    // MARK: - Observation

    /// Observes media for a specific note.
    /// - Parameter noteId: The note ID to observe
    /// - Returns: Publisher emitting media arrays
    func observeMediaForNote(noteId: String) -> AnyPublisher<[Media], Error> {
        let observation = ValueObservation.tracking { db in
            try Media
                .joining(required: Media.noteMedias.filter(NoteMedia.Columns.noteId == noteId))
                .fetchAll(db)
        }

        return observation
            .publisher(in: database.dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    // MARK: - Statistics

    /// Gets the total number of media files.
    /// - Returns: Media count
    func getTotalMediaCount() async throws -> Int {
        try await database.read { db in
            try Media.fetchCount(db)
        }
    }

    /// Gets the total size of all media.
    /// - Returns: Total size in bytes
    func getTotalMediaSize() async throws -> Int64 {
        try await database.read { db in
            let result = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(size), 0) FROM media")
            return result ?? 0
        }
    }

    /// Gets media usage statistics per note.
    /// - Returns: Dictionary of noteId -> (count, totalSize)
    func getMediaStatsPerNote() async throws -> [String: (count: Int, size: Int64)] {
        try await database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT nm.noteId, COUNT(*) as count, COALESCE(SUM(m.size), 0) as totalSize
                FROM note_media nm
                JOIN media m ON m.hash = nm.mediaHash
                GROUP BY nm.noteId
            """)

            var stats: [String: (count: Int, size: Int64)] = [:]
            for row in rows {
                if let noteId = row["noteId"] as String?,
                   let count = row["count"] as Int?,
                   let size = row["totalSize"] as Int64? {
                    stats[noteId] = (count, size)
                }
            }
            return stats
        }
    }

    // MARK: - Orphan Detection

    /// Finds orphaned media (media not linked to any note).
    /// - Returns: Array of orphaned Media records
    func getOrphanedMedia() async throws -> [Media] {
        try await database.read { db in
            try Media.fetchAll(db, sql: """
                SELECT m.* FROM media m
                LEFT JOIN note_media nm ON nm.mediaHash = m.hash
                WHERE nm.noteId IS NULL
                ORDER BY m.createdAt DESC
            """)
        }
    }

    /// Deletes all orphaned media records and their data.
    /// - Returns: Number of orphaned media deleted
    func deleteOrphanedMedia() async throws -> Int {
        let orphans = try await getOrphanedMedia()

        for media in orphans {
            try? coldStore.deleteMedia(hash: media.hash)
        }

        try await database.write { db in
            _ = try Media.fetchAll(db, sql: """
                DELETE FROM media
                WHERE hash IN (
                    SELECT m.hash FROM media m
                    LEFT JOIN note_media nm ON nm.mediaHash = m.hash
                    WHERE nm.noteId IS NULL
                )
            """)
        }

        return orphans.count
    }
}
