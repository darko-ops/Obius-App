import Foundation
import GRDB
import Combine

@MainActor
final class ModuleRepository: ObservableObject {
    private let database: DatabaseManager
    var syncLogger: SyncOperationLogger?
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var modules: [Module] = []

    init(database: DatabaseManager) {
        self.database = database
        observeModules()
    }

    private func observeModules() {
        database.observeAllModules()
            .receive(on: DispatchQueue.main)
            .catch { error -> Just<[Module]> in
                print("[ModuleRepository] Error observing modules: \(error)")
                return Just([])
            }
            .sink { [weak self] modules in
                print("[ModuleRepository] Observed \(modules.count) modules: \(modules.map { $0.name })")
                self?.modules = modules
            }
            .store(in: &cancellables)
    }

    // MARK: - Create

    func createModule(name: String, icon: String = "folder", storageType: ModuleStorageType = .local) async throws -> Module {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ModuleError.emptyName
        }

        return try await database.write { db in
            // Check for duplicate name
            let existing = try Module
                .filter(Module.Columns.name == trimmed)
                .filter(Module.Columns.deletedAt == nil)
                .fetchCount(db)

            if existing > 0 {
                throw ModuleError.duplicateName(trimmed)
            }

            // Get max order index
            let maxOrder = try Module
                .filter(Module.Columns.deletedAt == nil)
                .select(max(Module.Columns.orderIndex))
                .asRequest(of: Int?.self)
                .fetchOne(db) ?? 0

            let module = Module(
                name: trimmed,
                icon: icon,
                isDefault: false,
                storageType: storageType,
                orderIndex: (maxOrder ?? 0) + 1
            )

            try module.insert(db)
            return module
        }
    }

    // MARK: - Read

    func getModule(id: String) async throws -> Module? {
        try await database.read { db in
            try Module.fetchOne(db, key: id)
        }
    }

    func getModuleByName(_ name: String) async throws -> Module? {
        try await database.read { db in
            try Module
                .filter(Module.Columns.name == name)
                .filter(Module.Columns.deletedAt == nil)
                .fetchOne(db)
        }
    }

    /// Returns the first available module as a fallback
    func getLocalModule() -> Module? {
        modules.first
    }

    /// Returns the Cloud module if it exists
    func getCloudModule() -> Module? {
        modules.first { $0.name == "Cloud" }
    }

    // MARK: - Update

    func renameModule(id: String, newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ModuleError.emptyName
        }

        try await database.write { db in
            guard var module = try Module.fetchOne(db, key: id) else { return }

            // Check for duplicate name (excluding self)
            let existing = try Module
                .filter(Module.Columns.name == trimmed)
                .filter(Module.Columns.id != id)
                .filter(Module.Columns.deletedAt == nil)
                .fetchCount(db)

            if existing > 0 {
                throw ModuleError.duplicateName(trimmed)
            }

            module.name = trimmed
            module.isDefault = false
            module.touch()
            try module.update(db)
        }

        // Re-sync all notes in this module so the updated name propagates to other devices
        if let syncLogger = syncLogger {
            let notes = try await database.read { db in
                try Note.filter(Note.Columns.moduleId == id)
                    .filter(Note.Columns.deletedAt == nil)
                    .fetchAll(db)
            }
            for note in notes {
                syncLogger.logNoteUpdate(note)
            }
            if !notes.isEmpty {
                print("[ModuleRepository] Queued \(notes.count) note sync ops for module rename '\(trimmed)'")
            }
        }
    }

    // MARK: - Reorder

    func reorderModules(ids: [String]) async throws {
        try await database.write { db in
            for (index, id) in ids.enumerated() {
                guard var module = try Module.fetchOne(db, key: id) else { continue }
                module.orderIndex = index
                module.touch()
                try module.update(db)
            }
        }
    }

    // MARK: - Delete

    /// Deletes a module and all its contents (notes, sections, handles, echoes).
    /// Returns a tuple of deleted note IDs and section IDs for sync logging.
    @discardableResult
    func deleteModule(id: String) async throws -> (noteIds: [String], sectionIds: [String]) {
        try await database.write { db in
            guard var module = try Module.fetchOne(db, key: id) else { return ([], []) }

            // Must have at least one other module
            let otherCount = try Module
                .filter(Module.Columns.id != id)
                .filter(Module.Columns.deletedAt == nil)
                .fetchCount(db)
            guard otherCount > 0 else {
                throw ModuleError.cannotDeleteLast
            }

            let now = Int64(Date().timeIntervalSince1970 * 1000)

            // Get IDs of notes in this module
            let noteIds = try String.fetchAll(db, sql: """
                SELECT id FROM notes WHERE moduleId = ? AND deletedAt IS NULL
            """, arguments: [id])

            // Get IDs of sections belonging to those notes
            var sectionIds: [String] = []
            if !noteIds.isEmpty {
                let placeholders = noteIds.map { _ in "?" }.joined(separator: ",")
                sectionIds = try String.fetchAll(db, sql: """
                    SELECT id FROM sections WHERE noteId IN (\(placeholders)) AND deletedAt IS NULL
                """, arguments: StatementArguments(noteIds))

                // Soft-delete all sections
                try db.execute(sql: """
                    UPDATE sections SET deletedAt = ?, syncStatus = 'pending', localVersion = localVersion + 1
                    WHERE noteId IN (\(placeholders)) AND deletedAt IS NULL
                """, arguments: StatementArguments([now] + noteIds))

                // Soft-delete all notes
                try db.execute(sql: """
                    UPDATE notes SET deletedAt = ?, syncStatus = 'pending', localVersion = localVersion + 1
                    WHERE moduleId = ? AND deletedAt IS NULL
                """, arguments: [now, id])
            }

            // Soft-delete the module
            module.softDelete()
            try module.update(db)

            return (noteIds, sectionIds)
        }
    }
}

// MARK: - Module Errors

enum ModuleError: LocalizedError {
    case emptyName
    case duplicateName(String)
    case cannotDeleteLast

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Project name cannot be empty"
        case .duplicateName(let name):
            return "A project named '\(name)' already exists"
        case .cannotDeleteLast:
            return "You must have at least one project"
        }
    }
}
