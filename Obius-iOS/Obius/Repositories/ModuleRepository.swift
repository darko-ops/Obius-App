import Foundation
import GRDB
import Combine

@MainActor
final class ModuleRepository: ObservableObject {
    private let database: DatabaseManager
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

    /// Deletes a module, reassigning its notes to another module.
    /// Returns the IDs of notes that were reassigned (for sync logging).
    @discardableResult
    func deleteModule(id: String) async throws -> [String] {
        try await database.write { db in
            guard var module = try Module.fetchOne(db, key: id) else { return [] }

            // Find another module to reassign notes to
            guard let fallbackModule = try Module
                .filter(Module.Columns.id != id)
                .filter(Module.Columns.deletedAt == nil)
                .order(Module.Columns.orderIndex)
                .fetchOne(db)
            else {
                throw ModuleError.cannotDeleteLast
            }

            // Get IDs of notes being reassigned
            let affectedNoteIds = try String.fetchAll(db, sql: """
                SELECT id FROM notes WHERE moduleId = ? AND deletedAt IS NULL
            """, arguments: [id])

            // Move all notes from this module to the fallback
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            try db.execute(sql: """
                UPDATE notes SET moduleId = ?, updatedAt = ?, localVersion = localVersion + 1, syncStatus = 'pending'
                WHERE moduleId = ?
            """, arguments: [fallbackModule.id, now, id])

            // Soft-delete the module
            module.softDelete()
            try module.update(db)

            return affectedNoteIds
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
