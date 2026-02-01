import Foundation
import GRDB
import Combine

final class DatabaseManager {
    private let dbQueue: DatabaseQueue
    private let migrator: DatabaseMigrator

    static let schemaVersion = 6

    init(inMemory: Bool = false) throws {
        if inMemory {
            dbQueue = try DatabaseQueue()
        } else {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbPath = appSupport.appendingPathComponent("obius.sqlite")
            dbQueue = try DatabaseQueue(path: dbPath.path)
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

        self.migrator = migrator
        try migrator.migrate(dbQueue)
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
