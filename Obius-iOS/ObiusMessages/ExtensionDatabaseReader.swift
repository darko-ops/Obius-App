import Foundation
import GRDB

/// Read-only database access for the iMessage extension.
/// Opens the shared App Group SQLite database without running migrations.
final class ExtensionDatabaseReader {
    static let shared = ExtensionDatabaseReader()

    private var dbQueue: DatabaseQueue?

    /// Whether the shared database is available for reading
    var isAvailable: Bool { dbQueue != nil }

    private init() {
        do {
            guard let url = Self.databaseURL,
                  FileManager.default.fileExists(atPath: url.path) else {
                print("[ExtensionDB] Shared database not found")
                return
            }

            var config = Configuration()
            config.readonly = true
            self.dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        } catch {
            print("[ExtensionDB] Failed to open database: \(error)")
        }
    }

    /// The database URL in the App Group container
    private static var databaseURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.obius.shared")?
            .appendingPathComponent("obius.sqlite")
    }

    /// Perform a read-only query. Returns nil if the database is unavailable.
    func read<T>(_ block: (Database) throws -> T) -> T? {
        guard let dbQueue else { return nil }
        do {
            return try dbQueue.read(block)
        } catch {
            print("[ExtensionDB] Read error: \(error)")
            return nil
        }
    }
}
