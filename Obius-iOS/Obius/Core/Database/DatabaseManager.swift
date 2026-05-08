import Foundation
import GRDB
import Combine

final class DatabaseManager {
    private let migrator: DatabaseMigrator

    static let schemaVersion = 39

    /// The user this database is scoped to. `nil` means anonymous (signed-out).
    let userId: String?

    /// Filename for the per-user SQLite file. Anonymous users get a dedicated `_anon` file
    /// so account A's local data can never appear in account B.
    static func databaseFilename(forUserId userId: String?) -> String {
        if let userId, !userId.isEmpty {
            return "obius_\(userId.lowercased()).sqlite"
        }
        return "obius_anon.sqlite"
    }

    /// The App Group container directory used to host all per-user database files.
    static var appGroupContainerURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.obius.shared")
    }

    /// Returns the App Group URL for the database scoped to the given user (or anon).
    static func appGroupDatabaseURL(forUserId userId: String?) -> URL? {
        appGroupContainerURL?.appendingPathComponent(databaseFilename(forUserId: userId))
    }

    /// Legacy shared path (pre-multi-account). Kept so the migration helper can find it.
    static var legacyAppGroupDatabaseURL: URL? {
        appGroupContainerURL?.appendingPathComponent("obius.sqlite")
    }

    // Expose dbQueue for repositories that need direct observation
    var dbQueue: DatabaseQueue { _dbQueue }
    private let _dbQueue: DatabaseQueue

    /// Whether this manager was opened in read-only mode (for extensions)
    let isReadOnly: Bool

    /// - Parameters:
    ///   - userId: The signed-in user's id, or `nil` for anonymous. Selects the on-disk
    ///     SQLite file so each account has its own isolated local data.
    ///   - inMemory: Use an in-memory database (for testing)
    ///   - readOnly: Open the database in read-only mode (for extensions). Skips migrations.
    init(userId: String? = nil, inMemory: Bool = false, readOnly: Bool = false) throws {
        self.userId = userId
        self.isReadOnly = readOnly

        if inMemory {
            _dbQueue = try DatabaseQueue()
        } else {
            let dbURL: URL
            if let appGroupURL = Self.appGroupDatabaseURL(forUserId: userId) {
                // Ensure the directory exists
                let dir = appGroupURL.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                dbURL = appGroupURL
                #if DEBUG
                print("[DatabaseManager] Using app group database: \(appGroupURL.path)")
                #endif
            } else {
                // Fallback to legacy path if App Group unavailable
                let appSupport = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                dbURL = appSupport.appendingPathComponent(Self.databaseFilename(forUserId: userId))
                #if DEBUG
                print("[DatabaseManager] ⚠️ App group unavailable — using fallback: \(dbURL.path)")
                #endif
            }

            var config = Configuration()
            if readOnly {
                config.readonly = true
            }
            _dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
        }

        var migrator = DatabaseMigrator()

        // Migration v1: Initial schema
        migrator.registerMigration("v1_initial") { db in
            // Notes table
            try db.create(table: "notes") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text)
                t.column("aiTitle", .text)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("deletedAt", .integer)
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("colorIntent", .text).notNull().defaults(to: "default")
                t.column("localVersion", .integer).notNull().defaults(to: 1)
                t.column("serverVersion", .integer)
                t.column("syncStatus", .text).notNull().defaults(to: "pending")
                t.column("lastSyncedAt", .integer)
            }

            // Sections table
            try db.create(table: "sections") { t in
                t.column("id", .text).primaryKey()
                t.column("noteId", .text).notNull()
                    .references("notes", onDelete: .cascade)
                t.column("content", .text).notNull().defaults(to: "")
                t.column("contentType", .text).notNull().defaults(to: "text")
                t.column("parentSectionId", .text)
                    .references("sections", onDelete: .setNull)
                t.column("orderKey", .text).notNull()
                t.column("indentLevel", .integer).notNull().defaults(to: 0)
                t.column("isCollapsed", .boolean).notNull().defaults(to: false)
                t.column("colorIntent", .text)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("deletedAt", .integer)
                t.column("localVersion", .integer).notNull().defaults(to: 1)
                t.column("serverVersion", .integer)
                t.column("syncStatus", .text).notNull().defaults(to: "pending")
            }

            // Sync operations log
            try db.create(table: "syncOperations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("operationId", .text).notNull().unique()
                t.column("entityType", .text).notNull()
                t.column("entityId", .text).notNull()
                t.column("operationType", .text).notNull()
                t.column("payload", .text).notNull()
                t.column("timestamp", .integer).notNull()
                t.column("synced", .boolean).notNull().defaults(to: false)
            }

            // Sync metadata
            try db.create(table: "syncMetadata") { t in
                t.column("id", .text).primaryKey().defaults(to: "singleton")
                t.column("lastSyncTimestamp", .integer).notNull().defaults(to: 0)
                t.column("deviceId", .text).notNull()
                t.column("schemaVersion", .integer).notNull().defaults(to: 1)
            }

            // Indexes
            try db.create(index: "idx_notes_updated", on: "notes", columns: ["updatedAt"])
            try db.create(index: "idx_notes_sync", on: "notes", columns: ["syncStatus"])
            try db.create(index: "idx_sections_note", on: "sections", columns: ["noteId"])
            try db.create(index: "idx_sections_order", on: "sections", columns: ["noteId", "orderKey"])
            try db.create(index: "idx_sections_sync", on: "sections", columns: ["syncStatus"])
            try db.create(index: "idx_sync_ops_unsynced", on: "syncOperations", columns: ["synced"])

            // FTS5 virtual table for full-text search
            try db.execute(sql: """
                CREATE VIRTUAL TABLE sections_fts USING fts5(
                    content,
                    content='sections',
                    content_rowid='rowid'
                )
            """)

            // Triggers to keep FTS in sync
            try db.execute(sql: """
                CREATE TRIGGER sections_ai AFTER INSERT ON sections BEGIN
                    INSERT INTO sections_fts(rowid, content) VALUES (NEW.rowid, NEW.content);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER sections_ad AFTER DELETE ON sections BEGIN
                    INSERT INTO sections_fts(sections_fts, rowid, content)
                    VALUES('delete', OLD.rowid, OLD.content);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER sections_au AFTER UPDATE ON sections BEGIN
                    INSERT INTO sections_fts(sections_fts, rowid, content)
                    VALUES('delete', OLD.rowid, OLD.content);
                    INSERT INTO sections_fts(rowid, content) VALUES (NEW.rowid, NEW.content);
                END
            """)

            // Initialize sync metadata with device ID
            let deviceId = UUID().uuidString
            try db.execute(sql: """
                INSERT INTO syncMetadata (id, lastSyncTimestamp, deviceId, schemaVersion)
                VALUES ('singleton', 0, ?, 1)
            """, arguments: [deviceId])
        }
        
        // Migration v2: Add title, isLocked to sections; rename colorIntent to intent
        migrator.registerMigration("v2_section_enhancements") { db in
            // Add new columns to sections
            try db.alter(table: "sections") { t in
                t.add(column: "title", .text)
                t.add(column: "isLocked", .boolean).notNull().defaults(to: false)
            }
            
            // Rename colorIntent to intent in sections (SQLite doesn't support rename, so we handle via migration)
            // The new column will be populated from the old one
            try db.alter(table: "sections") { t in
                t.add(column: "intent", .text).notNull().defaults(to: "idea")
            }
            
            // Migrate existing colorIntent values to intent
            try db.execute(sql: """
                UPDATE sections SET intent = CASE
                    WHEN colorIntent = 'important' THEN 'task'
                    WHEN colorIntent = 'task' THEN 'task'
                    WHEN colorIntent = 'reference' THEN 'evidence'
                    WHEN colorIntent = 'idea' THEN 'idea'
                    WHEN colorIntent = 'default' THEN 'idea'
                    ELSE 'idea'
                END
            """)
            
            // Rename colorIntent to intent in notes
            try db.alter(table: "notes") { t in
                t.add(column: "intent", .text).notNull().defaults(to: "idea")
            }
            
            // Migrate existing colorIntent values to intent for notes
            try db.execute(sql: """
                UPDATE notes SET intent = CASE
                    WHEN colorIntent = 'important' THEN 'task'
                    WHEN colorIntent = 'task' THEN 'task'
                    WHEN colorIntent = 'reference' THEN 'evidence'
                    WHEN colorIntent = 'idea' THEN 'idea'
                    WHEN colorIntent = 'default' THEN 'idea'
                    ELSE 'idea'
                END
            """)
            
            // Update schema version in metadata
            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 2
            """)
        }

        // Migration v3: Add body field to notes for direct content
        migrator.registerMigration("v3_note_body") { db in
            try db.alter(table: "notes") { t in
                t.add(column: "body", .text).notNull().defaults(to: "")
            }

            // Update schema version in metadata
            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 3
            """)
        }

        // Migration v4: Add interstitialContent field for text between sections
        migrator.registerMigration("v4_interstitial_content") { db in
            try db.alter(table: "notes") { t in
                t.add(column: "interstitialContent", .text).notNull().defaults(to: "{}")
            }

            // Update schema version in metadata
            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 4
            """)
        }

        // Migration v5: Add handles table and handleId to sections for Handle Loop feature
        migrator.registerMigration("v5_handles") { db in
            // Create handles table
            try db.create(table: "handles") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().unique()  // Lowercase name for case-insensitive lookup
                t.column("displayName", .text).notNull()    // Original case-preserved name
                t.column("content", .text).notNull().defaults(to: "")
                t.column("intent", .text).notNull().defaults(to: "idea")
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("deletedAt", .integer)
                t.column("localVersion", .integer).notNull().defaults(to: 1)
                t.column("serverVersion", .integer)
                t.column("syncStatus", .text).notNull().defaults(to: "pending")
            }

            // Create indexes for handles
            try db.create(index: "idx_handles_name", on: "handles", columns: ["name"])
            try db.create(index: "idx_handles_sync", on: "handles", columns: ["syncStatus"])

            // Add handleId column to sections
            try db.alter(table: "sections") { t in
                t.add(column: "handleId", .text).references("handles", onDelete: .setNull)
            }

            // Create index for sections with handles
            try db.create(index: "idx_sections_handle", on: "sections", columns: ["handleId"])

            // Update schema version in metadata
            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 5
            """)
        }

        // Migration v6: Add sectionType field to sections for fold vs line distinction
        migrator.registerMigration("v6_section_type") { db in
            try db.alter(table: "sections") { t in
                t.add(column: "sectionType", .text).notNull().defaults(to: "fold")
            }

            // Update schema version in metadata
            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 6
            """)
        }

        // Migration v7: Add Split-Storage Engine tables (commits, media, note_media)
        migrator.registerMigration("v7_split_storage") { db in
            // Commits table - index of commits in Cold Store
            try db.create(table: "commits") { t in
                t.column("id", .text).primaryKey()
                t.column("noteId", .text).notNull()
                    .references("notes", onDelete: .cascade)
                t.column("hash", .text).notNull().unique()
                t.column("parentHash", .text)
                t.column("filePath", .text).notNull()
                t.column("createdAt", .integer).notNull()
            }

            // Create indexes for commits
            try db.create(index: "idx_commits_note", on: "commits", columns: ["noteId"])
            try db.create(index: "idx_commits_hash", on: "commits", columns: ["hash"])
            try db.create(index: "idx_commits_parent", on: "commits", columns: ["parentHash"])

            // Media table - content-addressable media metadata
            try db.create(table: "media") { t in
                t.column("hash", .text).primaryKey()
                t.column("filename", .text).notNull()
                t.column("mimeType", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("createdAt", .integer).notNull()
            }

            // Create index for media
            try db.create(index: "idx_media_filename", on: "media", columns: ["filename"])

            // Note-Media junction table
            try db.create(table: "note_media") { t in
                t.column("noteId", .text).notNull()
                    .references("notes", onDelete: .cascade)
                t.column("mediaHash", .text).notNull()
                    .references("media", column: "hash", onDelete: .cascade)
                t.primaryKey(["noteId", "mediaHash"])
            }

            // Update schema version in metadata
            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 7
            """)
        }

        // v8: Add isTemplateContent column to sections
        migrator.registerMigration("v8_template_content") { db in
            // Add isTemplateContent column to sections table
            try db.execute(sql: """
                ALTER TABLE sections ADD COLUMN isTemplateContent INTEGER NOT NULL DEFAULT 0
            """)

            // Update schema version in metadata
            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 8
            """)
        }

        // v9: Add templatePrefix column to sections for inline template editing
        migrator.registerMigration("v9_template_prefix") { db in
            // Add templatePrefix column to sections table
            try db.execute(sql: """
                ALTER TABLE sections ADD COLUMN templatePrefix TEXT
            """)

            // Update schema version in metadata
            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 9
            """)
        }

        // v10: Add contentBefore column to sections for editing before template text
        migrator.registerMigration("v10_content_before") { db in
            // Add contentBefore column to sections table
            try db.execute(sql: """
                ALTER TABLE sections ADD COLUMN contentBefore TEXT
            """)

            // Update schema version in metadata
            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 10
            """)
        }

        // v11: Add groupName column to notes for grouping pages
        migrator.registerMigration("v11_note_groups") { db in
            // Add groupName column to notes table
            try db.execute(sql: """
                ALTER TABLE notes ADD COLUMN groupName TEXT
            """)

            // Update schema version in metadata
            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 11
            """)
        }

        // v12: Add echoes table for Echo alert/reminder system
        migrator.registerMigration("v12_echoes") { db in
            try db.create(table: "echoes") { t in
                t.column("id", .text).primaryKey()
                t.column("handleId", .text).notNull()
                    .references("handles", onDelete: .cascade)
                t.column("echoType", .text).notNull()
                t.column("intervalValue", .integer)
                t.column("intervalUnit", .text)
                t.column("fireDate", .integer)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("nextFireDate", .integer)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
            }

            try db.create(index: "idx_echoes_handle", on: "echoes", columns: ["handleId"])
            try db.create(index: "idx_echoes_active", on: "echoes", columns: ["isActive"])
            try db.create(index: "idx_echoes_next_fire", on: "echoes", columns: ["nextFireDate"])

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 12
            """)
        }

        // v13: Echo redesign — drop and recreate echoes with new schema
        migrator.registerMigration("v13_echo_redesign") { db in
            try db.drop(table: "echoes")
            try db.create(table: "echoes") { t in
                t.column("id", .text).primaryKey()
                t.column("handleId", .text).notNull()
                    .references("handles", onDelete: .cascade)
                t.column("isRecurring", .boolean).notNull().defaults(to: false)
                t.column("intervalsJSON", .text)
                t.column("fireDate", .integer).notNull()
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("nextFireDate", .integer)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
            }

            try db.create(index: "idx_echoes_handle", on: "echoes", columns: ["handleId"])
            try db.create(index: "idx_echoes_active", on: "echoes", columns: ["isActive"])
            try db.create(index: "idx_echoes_next_fire", on: "echoes", columns: ["nextFireDate"])

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 13
            """)
        }

        // v14: Add isAlerted column to echoes for alert state tracking
        migrator.registerMigration("v14_echo_alert_state") { db in
            try db.alter(table: "echoes") { t in
                t.add(column: "isAlerted", .boolean).notNull().defaults(to: false)
            }

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 14
            """)
        }

        // v15: Add lastAcknowledgedAt to echoes so acknowledged echoes don't re-alert
        migrator.registerMigration("v15_echo_last_acknowledged") { db in
            try db.alter(table: "echoes") { t in
                t.add(column: "lastAcknowledgedAt", .integer)
            }

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 15
            """)
        }

        // v16: Add name column to commits for user-provided page commit names
        migrator.registerMigration("v16_commit_name") { db in
            try db.alter(table: "commits") { t in
                t.add(column: "name", .text)
            }

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 16
            """)
        }

        // v17: Add shortId column to commits for human-readable reference
        migrator.registerMigration("v17_commit_short_id") { db in
            try db.alter(table: "commits") { t in
                t.add(column: "shortId", .text).notNull().defaults(to: "")
            }

            // Backfill existing commits with generated short IDs
            let rows = try Row.fetchAll(db, sql: "SELECT id FROM commits")
            let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
            for row in rows {
                let id: String = row["id"]
                let block = { (0..<4).map { _ in chars.randomElement()! } }
                let shortId = "OBX-\(String(block()))-\(String(block()))"
                try db.execute(sql: "UPDATE commits SET shortId = ? WHERE id = ?", arguments: [shortId, id])
            }

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 17
            """)
        }

        // v18: Add rich text columns for persistent formatting
        migrator.registerMigration("v18_rich_text") { db in
            try db.alter(table: "notes") { t in
                t.add(column: "bodyRichText", .text)
            }

            try db.alter(table: "sections") { t in
                t.add(column: "richContent", .text)
            }

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 18
            """)
        }

        // Migration v19: Add interstitialRichContent for rich text in interstitial lines
        migrator.registerMigration("v19_interstitial_rich_text") { db in
            try db.alter(table: "notes") { t in
                t.add(column: "interstitialRichContent", .text).notNull().defaults(to: "{}")
            }

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 19
            """)
        }

        // v20: Add shareLinks table for sharing system
        migrator.registerMigration("v20_share_links") { db in
            try db.create(table: "shareLinks") { t in
                t.column("id", .text).primaryKey()
                t.column("slug", .text).notNull().unique()
                t.column("userId", .text).notNull()
                t.column("shareType", .text).notNull()
                t.column("noteId", .text)
                t.column("commitHash", .text)
                t.column("commitName", .text)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("viewCount", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("expiresAt", .integer)
                t.column("deletedAt", .integer)
                t.column("localVersion", .integer).notNull().defaults(to: 1)
                t.column("serverVersion", .integer)
                t.column("syncStatus", .text).notNull().defaults(to: "pending")
            }

            try db.create(index: "idx_shareLinks_slug", on: "shareLinks", columns: ["slug"], unique: true)
            try db.create(index: "idx_shareLinks_noteId", on: "shareLinks", columns: ["noteId"])
            try db.create(index: "idx_shareLinks_userId", on: "shareLinks", columns: ["userId"])
            try db.create(index: "idx_shareLinks_commitHash", on: "shareLinks", columns: ["commitHash"])
            try db.create(index: "idx_shareLinks_sync", on: "shareLinks", columns: ["syncStatus"])

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 20
            """)
        }

        // v21: Add comments table for shared content discussions (Handshakes)
        migrator.registerMigration("v21_comments") { db in
            try db.create(table: "comments") { t in
                t.column("id", .text).primaryKey()
                t.column("shareLinkId", .text).notNull()
                    .references("shareLinks", onDelete: .cascade)
                t.column("userId", .text).notNull()
                t.column("userDisplayName", .text)
                t.column("parentCommentId", .text)
                    .references("comments", onDelete: .setNull)
                t.column("body", .text).notNull()
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("deletedAt", .integer)
                t.column("sealedCommitHash", .text)
            }

            try db.create(index: "idx_comments_shareLink", on: "comments", columns: ["shareLinkId"])
            try db.create(index: "idx_comments_userId", on: "comments", columns: ["userId"])
            try db.create(index: "idx_comments_parent", on: "comments", columns: ["parentCommentId"])

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 21
            """)
        }

        migrator.registerMigration("v22_resolve_portal_content") { db in
            // Copy handle content into portal sections so Supabase has the resolved display content
            try db.execute(sql: """
                UPDATE sections SET
                    content = (SELECT h.content FROM handles h WHERE h.id = sections.handleId),
                    updatedAt = ?,
                    localVersion = localVersion + 1,
                    syncStatus = 'pending'
                WHERE handleId IS NOT NULL
                    AND deletedAt IS NULL
                    AND handleId IN (SELECT id FROM handles WHERE deletedAt IS NULL)
            """, arguments: [Int64(Date().timeIntervalSince1970 * 1000)])

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 22
            """)
        }

        // v23: Add isHidden column to commits
        migrator.registerMigration("v23_commit_hidden") { db in
            try db.alter(table: "commits") { t in
                t.add(column: "isHidden", .boolean).notNull().defaults(to: false)
            }

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 23
            """)
        }

        // v24: Add commitShortId column to shareLinks for sharing the human-readable ID
        migrator.registerMigration("v24_share_link_short_id") { db in
            try db.alter(table: "shareLinks") { t in
                t.add(column: "commitShortId", .text)
            }

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 24
            """)
        }

        // v25: Add tags column to notes for hashtag labels
        migrator.registerMigration("v25_note_tags") { db in
            try db.alter(table: "notes") { t in
                t.add(column: "tags", .text).notNull().defaults(to: "[]")
            }

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 25
            """)
        }

        // v26: Add isAutoCommit column to commits for automatic daily commits
        migrator.registerMigration("v26_auto_commit") { db in
            try db.execute(sql: """
                ALTER TABLE commits ADD COLUMN isAutoCommit BOOLEAN NOT NULL DEFAULT 0
            """)

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 26
            """)
        }

        // v27: Add modules table and moduleId to notes
        migrator.registerMigration("v27_modules") { db in
            // Create modules table
            try db.create(table: "modules") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("icon", .text).notNull().defaults(to: "folder")
                t.column("isDefault", .boolean).notNull().defaults(to: false)
                t.column("orderIndex", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("deletedAt", .integer)
            }

            try db.create(index: "idx_modules_order", on: "modules", columns: ["orderIndex"])

            // Add moduleId column to notes
            try db.execute(sql: """
                ALTER TABLE notes ADD COLUMN moduleId TEXT
            """)

            // Seed default modules
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let localId = UUID().uuidString
            let cloudId = UUID().uuidString

            #if os(macOS)
            let localIcon = "laptopcomputer"
            #else
            let localIcon = "iphone"
            #endif
            try db.execute(sql: """
                INSERT INTO modules (id, name, icon, isDefault, orderIndex, createdAt, updatedAt)
                VALUES (?, 'Local', ?, 1, 0, ?, ?)
            """, arguments: [localId, localIcon, now, now])

            try db.execute(sql: """
                INSERT INTO modules (id, name, icon, isDefault, orderIndex, createdAt, updatedAt)
                VALUES (?, 'Cloud', 'cloud', 1, 1, ?, ?)
            """, arguments: [cloudId, now, now])

            // Assign all existing notes to the Local module
            try db.execute(sql: """
                UPDATE notes SET moduleId = ? WHERE moduleId IS NULL
            """, arguments: [localId])

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 27
            """)
        }

        // v28: Add storageType column to modules
        migrator.registerMigration("v28_module_storage_type") { db in
            try db.execute(sql: """
                ALTER TABLE modules ADD COLUMN storageType TEXT NOT NULL DEFAULT 'local'
            """)

            // Backfill: Local module → local, Cloud module → cloud
            try db.execute(sql: """
                UPDATE modules SET storageType = 'cloud' WHERE name = 'Cloud' AND isDefault = 1
            """)

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 28
            """)
        }

        // v29: Add insights table for Intelligence page
        migrator.registerMigration("v29_insights") { db in
            try db.create(table: "insights") { t in
                t.column("id", .text).primaryKey()
                t.column("insightType", .text).notNull()
                t.column("title", .text).notNull()
                t.column("body", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull().defaults(to: "surfaced")
                t.column("sourceNoteId", .text)
                t.column("sourceSectionId", .text)
                t.column("relatedNoteId", .text)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
            }

            try db.create(index: "idx_insights_status", on: "insights", columns: ["status"])
            try db.create(index: "idx_insights_type", on: "insights", columns: ["insightType"])
            try db.create(index: "idx_insights_source_note", on: "insights", columns: ["sourceNoteId"])

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 29
            """)
        }

        // v30: Add aiTags column to notes for AI-generated concept tags
        migrator.registerMigration("v30_note_ai_tags") { db in
            try db.alter(table: "notes") { t in
                t.add(column: "aiTags", .text).notNull().defaults(to: "[]")
            }

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 30
            """)
        }

        // v31: Consolidate insight types into 6 project-scoped categories
        migrator.registerMigration("v31_insight_type_consolidation") { db in
            // Map tracked insights to new types
            try db.execute(sql: """
                UPDATE insights SET insightType = 'cleanup', sourceSectionId = 'stale'
                  WHERE insightType = 'staleContent' AND status = 'tracked'
            """)
            try db.execute(sql: """
                UPDATE insights SET insightType = 'cleanup', sourceSectionId = 'dormant_loop'
                  WHERE insightType = 'dormantLoop' AND status = 'tracked'
            """)
            try db.execute(sql: """
                UPDATE insights SET insightType = 'cleanup', sourceSectionId = 'lonely_loop'
                  WHERE insightType = 'lonelyHandle' AND status = 'tracked'
            """)
            try db.execute(sql: """
                UPDATE insights SET insightType = 'cleanup', sourceSectionId = 'nonsense'
                  WHERE insightType = 'nonsenseContent' AND status = 'tracked'
            """)
            try db.execute(sql: """
                UPDATE insights SET insightType = 'reminder', sourceSectionId = 'task'
                  WHERE insightType = 'suggestedTask' AND status = 'tracked'
            """)
            try db.execute(sql: """
                UPDATE insights SET insightType = 'reminder', sourceSectionId = 'question'
                  WHERE insightType = 'openQuestion' AND status = 'tracked'
            """)
            try db.execute(sql: """
                UPDATE insights SET insightType = 'reminder', sourceSectionId = 'suggested_echo'
                  WHERE insightType = 'suggestedEcho' AND status = 'tracked'
            """)

            // Purge all non-tracked insights (re-detected by new scan)
            try db.execute(sql: """
                DELETE FROM insights WHERE status != 'tracked'
            """)

            // Purge tracked insights with killed types (no new-type mapping)
            try db.execute(sql: """
                DELETE FROM insights WHERE insightType NOT IN
                  ('cleanup','reminder','safety','drift','weeklyReport','progress','upcomingEcho')
            """)

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 31
            """)
        }

        migrator.registerMigration("v32_note_view_count") { db in
            try db.alter(table: "notes") { t in
                t.add(column: "viewCount", .integer).notNull().defaults(to: 0)
            }

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 32
            """)
        }

        // v33: Migrate list/link insights to dedicated types and remove orphaned reminder rows
        migrator.registerMigration("v33_insight_list_link_types") { db in
            // Lists were stored as cleanup with sourceSectionId 'list'
            try db.execute(sql: """
                UPDATE insights SET insightType = 'list'
                WHERE insightType = 'cleanup' AND sourceSectionId = 'list'
            """)

            // Links were stored as reminder with sourceSectionId 'link'
            try db.execute(sql: """
                UPDATE insights SET insightType = 'link'
                WHERE insightType = 'reminder' AND sourceSectionId = 'link'
            """)

            // Delete remaining orphaned reminder rows
            try db.execute(sql: """
                DELETE FROM insights WHERE insightType = 'reminder'
            """)

            try db.execute(sql: """
                UPDATE syncMetadata SET schemaVersion = 33
            """)
        }

        // v34: Remove default Local/Cloud modules — all projects are user-created now
        migrator.registerMigration("v34_remove_default_modules") { db in
            // Un-default all modules so they can be renamed/deleted
            try db.execute(sql: "UPDATE modules SET isDefault = 0")

            // Soft-delete the auto-created Local and Cloud modules if they have no notes
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            for name in ["Local", "Cloud"] {
                let noteCount = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM notes
                    WHERE moduleId IN (SELECT id FROM modules WHERE name = ? AND deletedAt IS NULL)
                    AND deletedAt IS NULL
                """, arguments: [name]) ?? 0

                if noteCount == 0 {
                    try db.execute(sql: """
                        UPDATE modules SET deletedAt = ?, updatedAt = ? WHERE name = ? AND deletedAt IS NULL
                    """, arguments: [now, now, name])
                }
            }

            // Ensure at least one module exists — create "Artifacts" if all were deleted
            let remaining = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM modules WHERE deletedAt IS NULL") ?? 0
            if remaining == 0 {
                try db.execute(sql: """
                    INSERT INTO modules (id, name, icon, isDefault, storageType, orderIndex, createdAt, updatedAt)
                    VALUES (?, 'Artifacts', 'folder', 0, 'local', 0, ?, ?)
                """, arguments: [UUID().uuidString, now, now])
            }

            try db.execute(sql: "UPDATE syncMetadata SET schemaVersion = 34")
        }

        // v35: Add sync columns to echoes table for cloud sync
        migrator.registerMigration("v35_echo_sync_fields") { db in
            try db.execute(sql: "ALTER TABLE echoes ADD COLUMN localVersion INTEGER NOT NULL DEFAULT 1")
            try db.execute(sql: "ALTER TABLE echoes ADD COLUMN serverVersion INTEGER")
            try db.execute(sql: "ALTER TABLE echoes ADD COLUMN syncStatus TEXT NOT NULL DEFAULT 'pending'")

            try db.execute(sql: "UPDATE syncMetadata SET schemaVersion = 35")
        }

        // v36: Recreate echoes table without FK constraint on handleId.
        // Handles don't fully sync to cloud, so the FK causes echo inserts
        // to fail on devices where the handle doesn't exist locally yet.
        migrator.registerMigration("v36_echo_drop_handle_fk") { db in
            // Preserve existing data
            try db.execute(sql: "ALTER TABLE echoes RENAME TO echoes_old")

            // Recreate without FK reference
            try db.create(table: "echoes") { t in
                t.column("id", .text).primaryKey()
                t.column("handleId", .text).notNull()
                t.column("isRecurring", .boolean).notNull().defaults(to: false)
                t.column("intervalsJSON", .text)
                t.column("fireDate", .integer).notNull()
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("nextFireDate", .integer)
                t.column("isAlerted", .boolean).notNull().defaults(to: false)
                t.column("lastAcknowledgedAt", .integer)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("localVersion", .integer).notNull().defaults(to: 1)
                t.column("serverVersion", .integer)
                t.column("syncStatus", .text).notNull().defaults(to: "pending")
            }

            let now = Int64(Date().timeIntervalSince1970 * 1000)
            try db.execute(sql: """
                INSERT INTO echoes (id, handleId, isRecurring, intervalsJSON, fireDate, isActive, nextFireDate, isAlerted, lastAcknowledgedAt, createdAt, updatedAt, localVersion, serverVersion, syncStatus)
                SELECT id, handleId, isRecurring, intervalsJSON, fireDate, isActive, nextFireDate, isAlerted, lastAcknowledgedAt,
                       COALESCE(createdAt, ?), COALESCE(updatedAt, ?),
                       COALESCE(localVersion, 1), serverVersion, COALESCE(syncStatus, 'pending')
                FROM echoes_old
            """, arguments: [now, now])
            try db.execute(sql: "DROP TABLE echoes_old")

            try db.create(index: "idx_echoes_handle", on: "echoes", columns: ["handleId"])
            try db.create(index: "idx_echoes_active", on: "echoes", columns: ["isActive"])
            try db.create(index: "idx_echoes_next_fire", on: "echoes", columns: ["nextFireDate"])

            try db.execute(sql: "UPDATE syncMetadata SET schemaVersion = 36")
        }

        // v37: Add cached engagementScore column to notes
        migrator.registerMigration("v37_notes_engagement_score") { db in
            try db.alter(table: "notes") { t in
                t.add(column: "engagementScore", .double).notNull().defaults(to: 0)
            }

            // Back-fill scores for existing notes
            let now = Double(Int64(Date().timeIntervalSince1970 * 1000))

            let sectionCounts = try Row.fetchAll(db, sql: """
                SELECT noteId, COUNT(*) as cnt FROM sections
                WHERE deletedAt IS NULL GROUP BY noteId
            """)
            var secMap: [String: Int] = [:]
            for row in sectionCounts { secMap[row["noteId"]] = row["cnt"] }

            let echoRows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT s.noteId FROM sections s
                JOIN echoes e ON e.handleId = s.handleId
                WHERE s.deletedAt IS NULL AND s.handleId IS NOT NULL AND e.isActive = 1
            """)
            let echoSet = Set(echoRows.compactMap { $0["noteId"] as String? })

            // Insight feedback maps: cleanup, safety, tracked, dismissed
            let cleanupRows = try Row.fetchAll(db, sql: """
                SELECT sourceNoteId, COUNT(*) as cnt FROM insights
                WHERE insightType = 'cleanup' AND status = 'surfaced'
                GROUP BY sourceNoteId
            """)
            var cleanupMap: [String: Int] = [:]
            for row in cleanupRows {
                if let nid: String = row["sourceNoteId"] { cleanupMap[nid] = row["cnt"] }
            }

            let safetyRows = try Row.fetchAll(db, sql: """
                SELECT sourceNoteId, COUNT(*) as cnt FROM insights
                WHERE insightType = 'safety' AND status = 'surfaced'
                GROUP BY sourceNoteId
            """)
            var safetyMap: [String: Int] = [:]
            for row in safetyRows {
                if let nid: String = row["sourceNoteId"] { safetyMap[nid] = row["cnt"] }
            }

            let trackedRows = try Row.fetchAll(db, sql: """
                SELECT sourceNoteId, COUNT(*) as cnt FROM insights
                WHERE status = 'tracked'
                GROUP BY sourceNoteId
            """)
            var trackedMap: [String: Int] = [:]
            for row in trackedRows {
                if let nid: String = row["sourceNoteId"] { trackedMap[nid] = row["cnt"] }
            }

            let dismissedRows = try Row.fetchAll(db, sql: """
                SELECT sourceNoteId, COUNT(*) as cnt FROM insights
                WHERE status = 'dismissed'
                GROUP BY sourceNoteId
            """)
            var dismissedMap: [String: Int] = [:]
            for row in dismissedRows {
                if let nid: String = row["sourceNoteId"] { dismissedMap[nid] = row["cnt"] }
            }

            let notes = try Row.fetchAll(db, sql: """
                SELECT id, isPinned, updatedAt, viewCount FROM notes WHERE deletedAt IS NULL
            """)
            for note in notes {
                let id: String = note["id"]
                let isPinned: Bool = note["isPinned"]
                let updatedAt: Int64 = note["updatedAt"]
                let viewCount: Int = note["viewCount"]

                let pinBoost: Double = isPinned ? 1000 : 0
                let ageMs = max(now - Double(updatedAt), 0)
                let ageDays = ageMs / (1000 * 60 * 60 * 24)
                let recencyBoost = 100 * exp(-ageDays / 7)
                let viewBoost = min(Double(viewCount) * 2, 100)
                let sectionBoost = Double(secMap[id] ?? 0)
                let echoBoost: Double = echoSet.contains(id) ? 50 : 0
                let cleanupPenalty = Double(cleanupMap[id] ?? 0) * -20
                let safetyPenalty = Double(safetyMap[id] ?? 0) * -30
                let trackedBoost = min(Double(trackedMap[id] ?? 0) * 30, 90)
                let dismissedPenalty = max(Double(dismissedMap[id] ?? 0) * -5, -25)

                let score = pinBoost + recencyBoost + viewBoost + sectionBoost + echoBoost
                          + cleanupPenalty + safetyPenalty + trackedBoost + dismissedPenalty

                try db.execute(sql: "UPDATE notes SET engagementScore = ? WHERE id = ?", arguments: [score, id])
            }

            try db.execute(sql: "UPDATE syncMetadata SET schemaVersion = 37")
        }

        // v38: Calendar day memos table for cloud sync
        migrator.registerMigration("v38_calendar_memos") { db in
            try db.create(table: "calendarMemos") { t in
                t.column("id", .text).primaryKey()
                t.column("dateKey", .text).notNull().unique()
                t.column("content", .text).notNull().defaults(to: "")
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("localVersion", .integer).notNull().defaults(to: 1)
                t.column("serverVersion", .integer)
                t.column("syncStatus", .text).notNull().defaults(to: "pending")
            }

            try db.create(index: "idx_calendar_memos_date_key", on: "calendarMemos", columns: ["dateKey"], unique: true)

            // Migrate existing @AppStorage memos into the new table
            if let json = UserDefaults.standard.string(forKey: "calendarDayMemos"),
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                for (dateKey, content) in dict where !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO calendarMemos (id, dateKey, content, createdAt, updatedAt, localVersion, syncStatus)
                        VALUES (?, ?, ?, ?, ?, 1, 'pending')
                    """, arguments: [UUID().uuidString, dateKey, content, now, now])
                }
                print("[Migration v38] Migrated \(dict.count) calendar memos from UserDefaults")
            }

            try db.execute(sql: "UPDATE syncMetadata SET schemaVersion = 38")
        }

        // v39: Local note index for smart context assembly (AI Workspace)
        migrator.registerMigration("v39_note_index") { db in
            try db.create(table: "note_index") { t in
                t.column("id", .text).primaryKey()
                t.column("entityType", .text).notNull()        // 'note_body', 'section', 'handle'
                t.column("noteId", .text).references("notes", onDelete: .cascade)
                t.column("contentHash", .text).notNull()        // SHA-256 of content
                t.column("tokenCount", .integer).notNull()      // pre-counted for budget management
                t.column("intent", .text)
                t.column("handleId", .text)
                t.column("lastIndexedAt", .integer).notNull()   // ms since epoch
            }

            try db.create(index: "idx_note_index_note", on: "note_index", columns: ["noteId"])
            try db.create(index: "idx_note_index_type", on: "note_index", columns: ["entityType"])
            try db.create(index: "idx_note_index_handle", on: "note_index", columns: ["handleId"])

            try db.execute(sql: "UPDATE syncMetadata SET schemaVersion = 39")
        }

        self.migrator = migrator

        // Extensions open read-only and must not run migrations
        if !readOnly {
            try migrator.migrate(_dbQueue)
        }
    }

    // MARK: - Corruption Recovery

    /// Move the corrupted database aside and return true if recovery was performed.
    /// The caller should retry initialization after this returns true.
    static func recoverFromCorruption(forUserId userId: String? = nil) -> Bool {
        guard let dbURL = appGroupDatabaseURL(forUserId: userId) else { return false }
        let fm = FileManager.default
        guard fm.fileExists(atPath: dbURL.path) else { return false }

        let scope = userId?.lowercased() ?? "anon"
        let backupName = "obius_\(scope)_corrupt_\(Int(Date().timeIntervalSince1970)).sqlite"
        let backupURL = dbURL.deletingLastPathComponent().appendingPathComponent(backupName)

        do {
            // Move the corrupted file (and WAL/SHM) to a backup
            try fm.moveItem(at: dbURL, to: backupURL)
            let wal = dbURL.appendingPathExtension("wal")
            let shm = dbURL.appendingPathExtension("shm")
            if fm.fileExists(atPath: wal.path) { try? fm.removeItem(at: wal) }
            if fm.fileExists(atPath: shm.path) { try? fm.removeItem(at: shm) }
            print("[DatabaseManager] Corrupted database backed up to \(backupName)")
            return true
        } catch {
            // Last resort: just delete it
            try? fm.removeItem(at: dbURL)
            print("[DatabaseManager] Corrupted database deleted (backup failed: \(error))")
            return true
        }
    }

    // MARK: - Read Operations

    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    func read<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.read(block)
    }

    // MARK: - Write Operations

    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }

    func write<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.write(block)
    }

    // MARK: - Observation

    func observeNotes() -> AnyPublisher<[Note], Error> {
        ValueObservation
            .tracking { db in
                try Note
                    .filter(Note.Columns.deletedAt == nil)
                    .order(Note.Columns.updatedAt.desc)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    /// Recompute and persist the cached engagement score for a single note.
    /// Call this inside an existing write transaction after mutating a note,
    /// its sections, echoes, or insights.
    static func recomputeEngagementScore(noteId: String, in db: Database) throws {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT isPinned, updatedAt, viewCount FROM notes WHERE id = ?
        """, arguments: [noteId]) else { return }

        let isPinned: Bool = row["isPinned"]
        let updatedAt: Int64 = row["updatedAt"]
        let viewCount: Int = row["viewCount"]

        let sectionCount: Int = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM sections WHERE noteId = ? AND deletedAt IS NULL
        """, arguments: [noteId]) ?? 0

        let hasActiveEcho: Bool = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM sections s
            JOIN echoes e ON e.handleId = s.handleId
            WHERE s.noteId = ? AND s.deletedAt IS NULL AND s.handleId IS NOT NULL AND e.isActive = 1
        """, arguments: [noteId]).map { $0 > 0 } ?? false

        // Insight feedback signals: surfaced problems penalize, tracked insights boost,
        // repeatedly-dismissed insights indicate noise.
        let surfacedCleanupCount: Int = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM insights
            WHERE sourceNoteId = ? AND insightType = 'cleanup' AND status = 'surfaced'
        """, arguments: [noteId]) ?? 0

        let surfacedSafetyCount: Int = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM insights
            WHERE sourceNoteId = ? AND insightType = 'safety' AND status = 'surfaced'
        """, arguments: [noteId]) ?? 0

        let trackedCount: Int = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM insights
            WHERE sourceNoteId = ? AND status = 'tracked'
        """, arguments: [noteId]) ?? 0

        let dismissedCount: Int = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM insights
            WHERE sourceNoteId = ? AND status = 'dismissed'
        """, arguments: [noteId]) ?? 0

        let now = Double(Int64(Date().timeIntervalSince1970 * 1000))
        let pinBoost: Double = isPinned ? 1000 : 0
        let ageMs = max(now - Double(updatedAt), 0)
        let ageDays = ageMs / (1000 * 60 * 60 * 24)
        let recencyBoost = 100 * exp(-ageDays / 7)
        let viewBoost = min(Double(viewCount) * 2, 100)
        let sectionBoost = Double(sectionCount)
        let echoBoost: Double = hasActiveEcho ? 50 : 0

        // Feedback loop:
        // - Surfaced cleanup/safety insights penalize (unresolved problems)
        // - Tracked insights boost (user confirmed value, capped at 90)
        // - Dismissed insights mildly penalize (note generates noise, capped at -25)
        let cleanupPenalty = Double(surfacedCleanupCount) * -20
        let safetyPenalty = Double(surfacedSafetyCount) * -30
        let trackedBoost = min(Double(trackedCount) * 30, 90)
        let dismissedPenalty = max(Double(dismissedCount) * -5, -25)

        let score = pinBoost + recencyBoost + viewBoost + sectionBoost + echoBoost
                  + cleanupPenalty + safetyPenalty + trackedBoost + dismissedPenalty

        try db.execute(sql: "UPDATE notes SET engagementScore = ? WHERE id = ?", arguments: [score, noteId])
    }

    func observeNote(id: String) -> AnyPublisher<Note?, Error> {
        ValueObservation
            .tracking { db in
                try Note.fetchOne(db, key: id)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    func observeSections(noteId: String) -> AnyPublisher<[Section], Error> {
        ValueObservation
            .tracking { db in
                try Section
                    .filter(Section.Columns.noteId == noteId)
                    .filter(Section.Columns.deletedAt == nil)
                    .order(Section.Columns.orderKey)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    func observeNoteWithSections(noteId: String) -> AnyPublisher<NoteWithSections?, Error> {
        ValueObservation
            .tracking { db -> NoteWithSections? in
                guard let note = try Note.fetchOne(db, key: noteId) else {
                    return nil
                }
                let sections = try Section
                    .filter(Section.Columns.noteId == noteId)
                    .filter(Section.Columns.deletedAt == nil)
                    .order(Section.Columns.orderKey)
                    .fetchAll(db)
                return NoteWithSections(note: note, sections: sections)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    // MARK: - Handle Observation

    func observeAllHandles() -> AnyPublisher<[Handle], Error> {
        ValueObservation
            .tracking { db in
                try Handle
                    .filter(Handle.Columns.deletedAt == nil)
                    .order(Handle.Columns.name)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    func observeHandle(id: String) -> AnyPublisher<Handle?, Error> {
        ValueObservation
            .tracking { db in
                try Handle.fetchOne(db, key: id)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    // MARK: - Calendar Memo Observation

    func observeCalendarMemos() -> AnyPublisher<[CalendarMemo], Error> {
        ValueObservation
            .tracking { db in
                try CalendarMemo
                    .order(CalendarMemo.Columns.dateKey)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    // MARK: - Module Observation

    func observeAllModules() -> AnyPublisher<[Module], Error> {
        ValueObservation
            .tracking { db in
                try Module
                    .filter(Module.Columns.deletedAt == nil)
                    .order(Module.Columns.orderIndex)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    // MARK: - Echo Observation

    func observeActiveEchoes() -> AnyPublisher<[Echo], Error> {
        ValueObservation
            .tracking { db in
                try Echo
                    .filter(Echo.Columns.isActive == true)
                    .order(Echo.Columns.nextFireDate)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    // MARK: - Insight Observation

    func observeInsights(status: InsightStatus) -> AnyPublisher<[Insight], Error> {
        ValueObservation
            .tracking { db in
                try Insight
                    .filter(Insight.Columns.status == status.rawValue)
                    .order(Insight.Columns.createdAt.desc)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    func fetchInsightsForNote(_ noteId: String) throws -> [Insight] {
        try dbQueue.read { db in
            try Insight
                .filter(Insight.Columns.sourceNoteId == noteId)
                .filter(Insight.Columns.status != InsightStatus.dismissed.rawValue)
                .order(Insight.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Full-Text Search

    func searchSections(query: String) throws -> [Section] {
        try dbQueue.read { db in
            let pattern = FTS5Pattern(matchingAllTokensIn: query)
            guard let pattern = pattern else { return [] }

            let sql = """
                SELECT sections.*
                FROM sections
                JOIN sections_fts ON sections.rowid = sections_fts.rowid
                WHERE sections_fts MATCH ?
                AND sections.deletedAt IS NULL
                ORDER BY bm25(sections_fts)
                LIMIT 50
            """

            return try Section.fetchAll(db, sql: sql, arguments: [pattern.rawPattern])
        }
    }

    func searchSections(query: String) async throws -> [Section] {
        try await dbQueue.read { db in
            let pattern = FTS5Pattern(matchingAllTokensIn: query)
            guard let pattern = pattern else { return [] }

            let sql = """
                SELECT sections.*
                FROM sections
                JOIN sections_fts ON sections.rowid = sections_fts.rowid
                WHERE sections_fts MATCH ?
                AND sections.deletedAt IS NULL
                ORDER BY bm25(sections_fts)
                LIMIT 50
            """

            return try Section.fetchAll(db, sql: sql, arguments: [pattern.rawPattern])
        }
    }
}
