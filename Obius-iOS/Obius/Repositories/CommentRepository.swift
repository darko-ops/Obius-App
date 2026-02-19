import Foundation
import GRDB
import Combine

@MainActor
final class CommentRepository: ObservableObject {
    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - Create

    func saveComment(_ comment: Comment) async throws {
        try await database.write { db in
            try comment.insert(db, onConflict: .replace)
        }
    }

    // MARK: - Read

    func getComment(id: String) async throws -> Comment? {
        try await database.read { db in
            try Comment.fetchOne(db, key: id)
        }
    }

    func getComments(shareLinkId: String) async throws -> [Comment] {
        try await database.read { db in
            try Comment
                .filter(Comment.Columns.shareLinkId == shareLinkId)
                .filter(Comment.Columns.deletedAt == nil)
                .order(Comment.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    func getReplies(parentCommentId: String) async throws -> [Comment] {
        try await database.read { db in
            try Comment
                .filter(Comment.Columns.parentCommentId == parentCommentId)
                .filter(Comment.Columns.deletedAt == nil)
                .order(Comment.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    func getCommentCount(shareLinkId: String) async throws -> Int {
        try await database.read { db in
            try Comment
                .filter(Comment.Columns.shareLinkId == shareLinkId)
                .filter(Comment.Columns.deletedAt == nil)
                .fetchCount(db)
        }
    }

    // MARK: - Delete

    func deleteComment(id: String) async throws {
        try await database.write { db in
            _ = try Comment.deleteOne(db, key: id)
        }
    }

    // MARK: - Observation

    func observeComments(shareLinkId: String) -> AnyPublisher<[Comment], Error> {
        ValueObservation.tracking { db in
            try Comment
                .filter(Comment.Columns.shareLinkId == shareLinkId)
                .filter(Comment.Columns.deletedAt == nil)
                .order(Comment.Columns.createdAt.asc)
                .fetchAll(db)
        }
        .publisher(in: database.dbQueue, scheduling: .immediate)
        .eraseToAnyPublisher()
    }
}
