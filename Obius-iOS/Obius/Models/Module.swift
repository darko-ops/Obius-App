import Foundation
import GRDB

enum ModuleStorageType: String, Codable, CaseIterable {
    case local
    case cloud

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .cloud: return "Cloud"
        }
    }

    var icon: String {
        switch self {
        case .local: return "iphone"
        case .cloud: return "cloud"
        }
    }
}

struct Module: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var icon: String              // SF Symbol name
    var isDefault: Bool           // Default modules cannot be deleted/renamed
    var storageType: ModuleStorageType
    var orderIndex: Int
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    init(
        id: String = UUID().uuidString,
        name: String,
        icon: String = "folder",
        isDefault: Bool = false,
        storageType: ModuleStorageType = .local,
        orderIndex: Int = 0,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        deletedAt: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isDefault = isDefault
        self.storageType = storageType
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var isDeleted: Bool {
        deletedAt != nil
    }
}

// MARK: - GRDB Conformance

extension Module: FetchableRecord, PersistableRecord {
    static let databaseTableName = "modules"

    enum Columns: String, ColumnExpression {
        case id, name, icon, isDefault, storageType, orderIndex
        case createdAt, updatedAt, deletedAt
    }
}

// MARK: - Mutations

extension Module {
    mutating func touch() {
        updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    }

    mutating func softDelete() {
        deletedAt = Int64(Date().timeIntervalSince1970 * 1000)
        touch()
    }
}
