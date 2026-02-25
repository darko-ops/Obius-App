import Foundation
import GRDB

/// A Handle represents a named, reusable content block that can be referenced across multiple sections.
/// When a section links to a handle, it becomes a "portal" displaying the handle's content directly.
/// Editing any portal section updates the handle, and all linked sections see the change instantly.
struct Handle: Codable, Identifiable, Hashable {
    var id: String
    var name: String                    // Handle name without @ (stored lowercase for case-insensitive lookup)
    var displayName: String             // Original case-preserved name for display
    var content: String                 // The actual synced content
    var intent: IntentType              // Visual styling

    // Timestamps (milliseconds since epoch)
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    // Sync fields
    var localVersion: Int
    var serverVersion: Int?
    var syncStatus: SyncStatus

    init(
        id: String = UUID().uuidString,
        name: String,
        displayName: String? = nil,
        content: String = "",
        intent: IntentType = .idea,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        deletedAt: Int64? = nil,
        localVersion: Int = 1,
        serverVersion: Int? = nil,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.name = name.lowercased()  // Store lowercase for case-insensitive lookup
        self.displayName = displayName ?? name  // Preserve original case for display
        self.content = content
        self.intent = intent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.localVersion = localVersion
        self.serverVersion = serverVersion
        self.syncStatus = syncStatus
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    /// The formatted handle name with @ prefix for display
    var formattedName: String {
        "@\(displayName)"
    }

    /// Preview of the content (first 80 characters)
    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        if firstLine.count <= 80 {
            return firstLine
        }
        return String(firstLine.prefix(80)) + "…"
    }

    // MARK: - Handle Name Validation

    /// Validates a handle name. Returns nil if valid, or an error message if invalid.
    static func validateName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return "Loop name cannot be empty"
        }

        if trimmed.count < 2 {
            return "Loop name must be at least 2 characters"
        }

        if trimmed.count > 50 {
            return "Loop name must be 50 characters or less"
        }

        // Only allow alphanumeric characters and underscores
        let validPattern = "^[a-zA-Z0-9_]+$"
        let regex = try? NSRegularExpression(pattern: validPattern)
        let range = NSRange(location: 0, length: trimmed.utf16.count)

        if regex?.firstMatch(in: trimmed, options: [], range: range) == nil {
            return "Loop name can only contain letters, numbers, and underscores"
        }

        return nil
    }

    /// Normalizes a handle name for storage/lookup (lowercase, trimmed)
    static func normalizeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - GRDB Conformance

extension Handle: FetchableRecord, PersistableRecord {
    static let databaseTableName = "handles"

    enum Columns: String, ColumnExpression {
        case id, name, displayName, content, intent
        case createdAt, updatedAt, deletedAt
        case localVersion, serverVersion, syncStatus
    }
}

// MARK: - Mutations

extension Handle {
    mutating func touch() {
        updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        localVersion += 1
        syncStatus = .pending
    }

    mutating func softDelete() {
        deletedAt = Int64(Date().timeIntervalSince1970 * 1000)
        touch()
    }

    mutating func updateContent(_ newContent: String) {
        content = newContent
        touch()
    }

    mutating func setIntent(_ newIntent: IntentType) {
        intent = newIntent
        touch()
    }
}
