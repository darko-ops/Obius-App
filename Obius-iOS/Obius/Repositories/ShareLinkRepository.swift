import Foundation
import GRDB
import Combine

@MainActor
final class ShareLinkRepository: ObservableObject {
    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - Create

    func saveShareLink(_ shareLink: ShareLink) async throws {
        try await database.write { db in
            try shareLink.insert(db, onConflict: .replace)
        }
    }

    // MARK: - Read

    func getShareLink(id: String) async throws -> ShareLink? {
        try await database.read { db in
            try ShareLink.fetchOne(db, key: id)
        }
    }

    func getShareLink(slug: String) async throws -> ShareLink? {
        try await database.read { db in
            try ShareLink
                .filter(ShareLink.Columns.slug == slug)
                .fetchOne(db)
        }
    }

    func getShareLinks(noteId: String) async throws -> [ShareLink] {
        try await database.read { db in
            try ShareLink
                .filter(ShareLink.Columns.noteId == noteId)
                .filter(ShareLink.Columns.deletedAt == nil)
                .order(ShareLink.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func getShareLinks(commitHash: String) async throws -> [ShareLink] {
        try await database.read { db in
            try ShareLink
                .filter(ShareLink.Columns.commitHash == commitHash)
                .filter(ShareLink.Columns.deletedAt == nil)
                .order(ShareLink.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func getActiveShareLinks(userId: String) async throws -> [ShareLink] {
        try await database.read { db in
            try ShareLink
                .filter(ShareLink.Columns.userId == userId)
                .filter(ShareLink.Columns.isActive == true)
                .filter(ShareLink.Columns.deletedAt == nil)
                .order(ShareLink.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func getAllShareLinks() async throws -> [ShareLink] {
        try await database.read { db in
            try ShareLink
                .filter(ShareLink.Columns.deletedAt == nil)
                .order(ShareLink.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Update

    func updateShareLink(_ shareLink: ShareLink) async throws {
        try await database.write { db in
            try shareLink.update(db)
        }
    }

    func deactivateShareLink(id: String) async throws {
        try await database.write { db in
            guard var shareLink = try ShareLink.fetchOne(db, key: id) else { return }
            shareLink.deactivate()
            try shareLink.update(db)
        }
    }

    // MARK: - Delete

    func deleteShareLink(id: String) async throws {
        try await database.write { db in
            guard var shareLink = try ShareLink.fetchOne(db, key: id) else { return }
            shareLink.softDelete()
            try shareLink.update(db)
        }
    }

    // MARK: - Observation

    func observeShareLinks(noteId: String) -> AnyPublisher<[ShareLink], Error> {
        ValueObservation.tracking { db in
            try ShareLink
                .filter(ShareLink.Columns.noteId == noteId)
                .filter(ShareLink.Columns.deletedAt == nil)
                .order(ShareLink.Columns.createdAt.desc)
                .fetchAll(db)
        }
        .publisher(in: database.dbQueue, scheduling: .immediate)
        .eraseToAnyPublisher()
    }

    func observeActiveShareLinks(userId: String) -> AnyPublisher<[ShareLink], Error> {
        ValueObservation.tracking { db in
            try ShareLink
                .filter(ShareLink.Columns.userId == userId)
                .filter(ShareLink.Columns.isActive == true)
                .filter(ShareLink.Columns.deletedAt == nil)
                .order(ShareLink.Columns.createdAt.desc)
                .fetchAll(db)
        }
        .publisher(in: database.dbQueue, scheduling: .immediate)
        .eraseToAnyPublisher()
    }

    // MARK: - Sync

    func getPendingShareLinks() async throws -> [ShareLink] {
        try await database.read { db in
            try ShareLink
                .filter(ShareLink.Columns.syncStatus == SyncStatus.pending.rawValue)
                .fetchAll(db)
        }
    }
}
