import Foundation
import GRDB
import Combine

@MainActor
final class HandleRepository: ObservableObject {
    private let database: DatabaseManager

    @Published private(set) var handles: [Handle] = []
    private var cancellables = Set<AnyCancellable>()

    init(database: DatabaseManager) {
        self.database = database
        observeHandles()
    }

    private func observeHandles() {
        database.observeAllHandles()
            .receive(on: DispatchQueue.main)
            .catch { error -> Just<[Handle]> in
                print("Error observing handles: \(error)")
                return Just([])
            }
            .sink { [weak self] handles in
                self?.handles = handles
            }
            .store(in: &cancellables)
    }

    // MARK: - Observation

    func observeHandle(id: String) -> AnyPublisher<Handle?, Error> {
        database.observeHandle(id: id)
    }

    func observeAllHandles() -> AnyPublisher<[Handle], Error> {
        database.observeAllHandles()
    }

    // MARK: - Create

    /// Create a new handle with the given name and optional initial content
    /// - Parameters:
    ///   - name: The handle name (will be validated and normalized)
    ///   - content: Initial content for the handle
    ///   - intent: Visual styling intent
    /// - Returns: The created handle
    /// - Throws: HandleError if validation fails or name already exists
    func createHandle(name: String, content: String = "", intent: IntentType = .idea) async throws -> Handle {
        // Validate name
        if let error = Handle.validateName(name) {
            throw HandleError.invalidName(error)
        }

        let normalizedName = Handle.normalizeName(name)

        return try await database.write { db in
            // Check if name already exists
            let existingCount = try Handle
                .filter(Handle.Columns.name == normalizedName)
                .filter(Handle.Columns.deletedAt == nil)
                .fetchCount(db)

            if existingCount > 0 {
                throw HandleError.nameAlreadyExists(name)
            }

            let handle = Handle(
                name: normalizedName,
                displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content,
                intent: intent
            )

            try handle.insert(db)
            return handle
        }
    }

    // MARK: - Read

    func getHandle(id: String) async throws -> Handle? {
        try await database.read { db in
            try Handle.fetchOne(db, key: id)
        }
    }

    func getHandleByName(_ name: String) async throws -> Handle? {
        let normalizedName = Handle.normalizeName(name)
        return try await database.read { db in
            try Handle
                .filter(Handle.Columns.name == normalizedName)
                .filter(Handle.Columns.deletedAt == nil)
                .fetchOne(db)
        }
    }

    func getAllHandles() async throws -> [Handle] {
        try await database.read { db in
            try Handle
                .filter(Handle.Columns.deletedAt == nil)
                .order(Handle.Columns.name)
                .fetchAll(db)
        }
    }

    /// Search handles by name (for autocomplete)
    func searchHandles(query: String) async throws -> [Handle] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedQuery.isEmpty {
            return try await getAllHandles()
        }

        return try await database.read { db in
            try Handle
                .filter(Handle.Columns.name.like("%\(normalizedQuery)%"))
                .filter(Handle.Columns.deletedAt == nil)
                .order(Handle.Columns.name)
                .limit(20)
                .fetchAll(db)
        }
    }

    // MARK: - Update

    func updateHandleContent(id: String, content: String) async throws {
        try await database.write { db in
            guard var handle = try Handle.fetchOne(db, key: id) else {
                throw HandleError.notFound(id)
            }
            handle.updateContent(content)
            try handle.update(db)
        }
    }

    func updateHandleIntent(id: String, intent: IntentType) async throws {
        try await database.write { db in
            guard var handle = try Handle.fetchOne(db, key: id) else {
                throw HandleError.notFound(id)
            }
            handle.setIntent(intent)
            try handle.update(db)
        }
    }

    func renameHandle(id: String, newName: String) async throws {
        // Validate new name
        if let error = Handle.validateName(newName) {
            throw HandleError.invalidName(error)
        }

        let normalizedName = Handle.normalizeName(newName)

        try await database.write { db in
            // Check if new name already exists (excluding this handle)
            let existingCount = try Handle
                .filter(Handle.Columns.name == normalizedName)
                .filter(Handle.Columns.id != id)
                .filter(Handle.Columns.deletedAt == nil)
                .fetchCount(db)

            if existingCount > 0 {
                throw HandleError.nameAlreadyExists(newName)
            }

            guard var handle = try Handle.fetchOne(db, key: id) else {
                throw HandleError.notFound(id)
            }

            handle.name = normalizedName
            handle.displayName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            handle.touch()
            try handle.update(db)
        }
    }

    // MARK: - Delete

    func deleteHandle(id: String) async throws {
        try await database.write { db in
            guard var handle = try Handle.fetchOne(db, key: id) else {
                throw HandleError.notFound(id)
            }
            handle.softDelete()
            try handle.update(db)

            // Unlink all sections from this handle (set handleId to NULL)
            try db.execute(sql: """
                UPDATE sections SET handleId = NULL, updatedAt = ?, localVersion = localVersion + 1, syncStatus = 'pending'
                WHERE handleId = ?
            """, arguments: [Int64(Date().timeIntervalSince1970 * 1000), id])
        }
    }

    func permanentlyDelete(id: String) async throws {
        try await database.write { db in
            try Handle.deleteOne(db, key: id)
        }
    }

    // MARK: - Section Linking

    /// Get all sections linked to a specific handle
    func getSectionsWithHandle(handleId: String) async throws -> [Section] {
        try await database.read { db in
            try Section
                .filter(Section.Columns.handleId == handleId)
                .filter(Section.Columns.deletedAt == nil)
                .order(Section.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Get the count of sections linked to a handle
    func getSectionCount(handleId: String) async throws -> Int {
        try await database.read { db in
            try Section
                .filter(Section.Columns.handleId == handleId)
                .filter(Section.Columns.deletedAt == nil)
                .fetchCount(db)
        }
    }
}

// MARK: - Handle Errors

enum HandleError: LocalizedError {
    case invalidName(String)
    case nameAlreadyExists(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let message):
            return message
        case .nameAlreadyExists(let name):
            return "A handle named '@\(name)' already exists"
        case .notFound(let id):
            return "Handle not found: \(id)"
        }
    }
}
