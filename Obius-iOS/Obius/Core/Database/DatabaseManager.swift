import Foundation
import GRDB
import Combine

final class DatabaseManager {
    private let migrator: DatabaseMigrator

    static let schemaVersion = 19

    // Expose dbQueue for repositories that need direct observation
    var dbQueue: DatabaseQueue { _dbQueue }
    private let _dbQueue: DatabaseQueue

    init(inMemory: Bool = false) throws {
        if inMemory {
            _dbQueue = try DatabaseQueue()
        } else {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbPath = appSupport.appendingPathComponent("obius.sqlite")
            _dbQueue = try DatabaseQueue(path: dbPath.path)
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

        self.migrator = migrator
        try migrator.migrate(_dbQueue)
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
                    .order(Note.Columns.isPinned.desc, Note.Columns.updatedAt.desc)
                    .fetchAll(db)
            }
            .publisher(in: dbQueue, scheduling: .immediate)
            .eraseToAnyPublisher()
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
