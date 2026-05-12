import Foundation
import SQLite3

/// One-time migration of the SQLite database from ~/Library/Application Support/
/// to the App Group container so the iMessage extension can read it.
///
/// Also handles the per-user-file rework: a single legacy `obius.sqlite` (App Group
/// or Application Support) is renamed to `obius_<userId>.sqlite` so that signing
/// out and signing in as a different account no longer surfaces the previous
/// account's local data.
enum DatabaseMigrationHelper {

    private static let legacyPathMigrationKey = "hasMigratedDatabaseToAppGroup"
    private static let perUserMigrationKey = "hasMigratedDatabaseToPerUserFile_v1"

    /// The legacy database path in ~/Library/Application Support/
    static var legacyDatabaseURL: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("obius.sqlite")
    }

    /// The pre-multi-account App Group database path.
    static var legacyAppGroupDatabaseURL: URL? {
        DatabaseManager.legacyAppGroupDatabaseURL
    }

    /// Migrate the database if needed. Safe to call multiple times.
    /// - Parameter currentUserId: The currently authenticated user, if known. The
    ///   legacy single-DB file is assigned to this user (or anonymous if `nil`).
    static func migrateIfNeeded(currentUserId: String? = nil) {
        migrateLegacyApplicationSupportIfNeeded(currentUserId: currentUserId)
        migrateLegacyAppGroupSingleFileIfNeeded(currentUserId: currentUserId)
    }

    // MARK: - Phase 1: ~/Library/Application Support → App Group

    private static func migrateLegacyApplicationSupportIfNeeded(currentUserId: String?) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyPathMigrationKey) else { return }

        guard let legacyURL = legacyDatabaseURL,
              let destinationURL = DatabaseManager.appGroupDatabaseURL(forUserId: currentUserId) else {
            // Can't determine paths — mark as done (fresh install will create in App Group)
            defaults.set(true, forKey: legacyPathMigrationKey)
            return
        }

        let fm = FileManager.default

        // If old DB doesn't exist, nothing to migrate (fresh install)
        guard fm.fileExists(atPath: legacyURL.path) else {
            defaults.set(true, forKey: legacyPathMigrationKey)
            return
        }

        // If new DB already exists, skip migration
        guard !fm.fileExists(atPath: destinationURL.path) else {
            defaults.set(true, forKey: legacyPathMigrationKey)
            return
        }

        // Ensure the App Group directory exists
        let appGroupDir = destinationURL.deletingLastPathComponent()
        try? fm.createDirectory(at: appGroupDir, withIntermediateDirectories: true)

        do {
            // Checkpoint WAL to ensure all data is in the main .sqlite file
            checkpointWAL(at: legacyURL)

            // Copy the main database file
            try fm.copyItem(at: legacyURL, to: destinationURL)

            // Copy WAL and SHM files if they exist
            let walURL = legacyURL.appendingPathExtension("wal")
            let shmURL = legacyURL.appendingPathExtension("shm")
            let newWalURL = destinationURL.appendingPathExtension("wal")
            let newShmURL = destinationURL.appendingPathExtension("shm")

            // Remove stale WAL/SHM at destination (shouldn't exist but be safe)
            try? fm.removeItem(at: newWalURL)
            try? fm.removeItem(at: newShmURL)

            if fm.fileExists(atPath: walURL.path) {
                try fm.copyItem(at: walURL, to: newWalURL)
            }
            if fm.fileExists(atPath: shmURL.path) {
                try fm.copyItem(at: shmURL, to: newShmURL)
            }

            // Verify the new database is readable
            guard verifyDatabase(at: destinationURL) else {
                // Verification failed — remove the bad copy and bail
                try? fm.removeItem(at: destinationURL)
                try? fm.removeItem(at: newWalURL)
                try? fm.removeItem(at: newShmURL)
                print("[DatabaseMigration] Verification failed, will retry next launch")
                return
            }

            // Remove old files only after confirming new DB is valid
            try? fm.removeItem(at: legacyURL)
            try? fm.removeItem(at: walURL)
            try? fm.removeItem(at: shmURL)

            defaults.set(true, forKey: legacyPathMigrationKey)
            // Implicit: this also satisfies the per-user migration since the data
            // landed at the user-scoped destination directly.
            defaults.set(true, forKey: perUserMigrationKey)
            print("[DatabaseMigration] Migrated legacy DB to per-user file: \(destinationURL.lastPathComponent)")
        } catch {
            print("[DatabaseMigration] Migration failed: \(error). Will retry next launch.")
        }
    }

    // MARK: - Phase 2: legacy shared App Group obius.sqlite → per-user file

    private static func migrateLegacyAppGroupSingleFileIfNeeded(currentUserId: String?) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: perUserMigrationKey) else { return }

        guard let legacySharedURL = legacyAppGroupDatabaseURL,
              let destinationURL = DatabaseManager.appGroupDatabaseURL(forUserId: currentUserId) else {
            defaults.set(true, forKey: perUserMigrationKey)
            return
        }

        let fm = FileManager.default

        // Nothing to migrate if there's no legacy file.
        guard fm.fileExists(atPath: legacySharedURL.path) else {
            defaults.set(true, forKey: perUserMigrationKey)
            return
        }

        // If destination already exists with content, leave the legacy file in place
        // and mark migration done so we don't try again. The legacy file becomes a
        // stranded artifact but no data is lost or leaked.
        if fm.fileExists(atPath: destinationURL.path) {
            defaults.set(true, forKey: perUserMigrationKey)
            return
        }

        do {
            // Checkpoint WAL into the main file before moving.
            checkpointWAL(at: legacySharedURL)

            try fm.moveItem(at: legacySharedURL, to: destinationURL)

            // Move WAL/SHM siblings if present.
            let walURL = legacySharedURL.appendingPathExtension("wal")
            let shmURL = legacySharedURL.appendingPathExtension("shm")
            let newWalURL = destinationURL.appendingPathExtension("wal")
            let newShmURL = destinationURL.appendingPathExtension("shm")
            if fm.fileExists(atPath: walURL.path) {
                try? fm.moveItem(at: walURL, to: newWalURL)
            }
            if fm.fileExists(atPath: shmURL.path) {
                try? fm.moveItem(at: shmURL, to: newShmURL)
            }

            defaults.set(true, forKey: perUserMigrationKey)
            print("[DatabaseMigration] Renamed legacy shared DB to \(destinationURL.lastPathComponent)")
        } catch {
            print("[DatabaseMigration] Per-user rename failed: \(error). Will retry next launch.")
        }
    }

    // MARK: - Helpers

    /// Checkpoint the WAL to flush pending writes into the main database file.
    private static func checkpointWAL(at url: URL) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
    }

    /// Verify the database file is a valid SQLite database by running an integrity check.
    private static func verifyDatabase(at url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        guard let result = sqlite3_column_text(stmt, 0) else { return false }
        return String(cString: result) == "ok"
    }
}
