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
                print("Error observing modules: \(error)")
                return Just([])
            }
            .sink { [weak self] modules in
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

    func getLocalModule() -> Module? {
        modules.first { $0.isDefault && $0.name == "Local" }
    }

    func getCloudModule() -> Module? {
        modules.first { $0.isDefault && $0.name == "Cloud" }
    }

    // MARK: - Update

    func renameModule(id: String, newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ModuleError.emptyName
        }

        try await database.write { db in
            guard var module = try Module.fetchOne(db, key: id) else { return }

            if module.isDefault {
                throw ModuleError.cannotModifyDefault
            }

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

    func deleteModule(id: String) async throws {
        try await database.write { db in
            guard var module = try Module.fetchOne(db, key: id) else { return }

            if module.isDefault {
                throw ModuleError.cannotModifyDefault
            }

            // Find the Local module to reassign notes
            guard let localModule = try Module
                .filter(Module.Columns.name == "Local")
                .filter(Module.Columns.isDefault == true)
                .filter(Module.Columns.deletedAt == nil)
                .fetchOne(db)
            else { return }

            // Move all notes from this module to Local
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            try db.execute(sql: """
                UPDATE notes SET moduleId = ?, updatedAt = ?, localVersion = localVersion + 1, syncStatus = 'pending'
                WHERE moduleId = ?
            """, arguments: [localModule.id, now, id])

            // Soft-delete the module
            module.softDelete()
            try module.update(db)
        }
    }
}

// MARK: - Module Errors

enum ModuleError: LocalizedError {
    case emptyName
    case duplicateName(String)
    case cannotModifyDefault

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Folder name cannot be empty"
        case .duplicateName(let name):
            return "A folder named '\(name)' already exists"
        case .cannotModifyDefault:
            return "Default folders cannot be modified"
        }
    }
}
