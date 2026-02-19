import Foundation
import SQLite3

/// One-time migration of the SQLite database from ~/Library/Application Support/
/// to the App Group container so the iMessage extension can read it.
enum DatabaseMigrationHelper {

    private static let migrationKey = "hasMigratedDatabaseToAppGroup"

    /// The legacy database path in ~/Library/Application Support/
    static var legacyDatabaseURL: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("obius.sqlite")
    }

    /// The new database path in the App Group container
    static var appGroupDatabaseURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.obius.shared")?
            .appendingPathComponent("obius.sqlite")
    }

    /// Migrate the database if needed. Safe to call multiple times.
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        guard let legacyURL = legacyDatabaseURL,
              let appGroupURL = appGroupDatabaseURL else {
            // Can't determine paths — mark as done (fresh install will create in App Group)
            defaults.set(true, forKey: migrationKey)
            return
        }

        let fm = FileManager.default

        // If old DB doesn't exist, nothing to migrate (fresh install)
        guard fm.fileExists(atPath: legacyURL.path) else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        // If new DB already exists, skip migration
        guard !fm.fileExists(atPath: appGroupURL.path) else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        // Ensure the App Group directory exists
        let appGroupDir = appGroupURL.deletingLastPathComponent()
        try? fm.createDirectory(at: appGroupDir, withIntermediateDirectories: true)

        do {
            // Checkpoint WAL to ensure all data is in the main .sqlite file
            checkpointWAL(at: legacyURL)

            // Copy the main database file
            try fm.copyItem(at: legacyURL, to: appGroupURL)

            // Copy WAL and SHM files if they exist
            let walURL = legacyURL.appendingPathExtension("wal")
            let shmURL = legacyURL.appendingPathExtension("shm")
            let newWalURL = appGroupURL.appendingPathExtension("wal")
            let newShmURL = appGroupURL.appendingPathExtension("shm")

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
            guard verifyDatabase(at: appGroupURL) else {
                // Verification failed — remove the bad copy and bail
                try? fm.removeItem(at: appGroupURL)
                try? fm.removeItem(at: newWalURL)
                try? fm.removeItem(at: newShmURL)
                print("[DatabaseMigration] Verification failed, will retry next launch")
                return
            }

            // Remove old files only after confirming new DB is valid
            try? fm.removeItem(at: legacyURL)
            try? fm.removeItem(at: walURL)
            try? fm.removeItem(at: shmURL)

            defaults.set(true, forKey: migrationKey)
            print("[DatabaseMigration] Successfully migrated database to App Group container")
        } catch {
            print("[DatabaseMigration] Migration failed: \(error). Will retry next launch.")
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
