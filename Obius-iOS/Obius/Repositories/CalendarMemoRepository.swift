import Foundation
import GRDB
import Combine

@MainActor
final class CalendarMemoRepository: ObservableObject {
    private let database: DatabaseManager
    var syncLogger: SyncOperationLogger?

    /// Published dictionary of dateKey → content for reactive UI updates
    @Published private(set) var memos: [String: String] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(database: DatabaseManager) {
        self.database = database
        observeMemos()
    }

    private func observeMemos() {
        database.observeCalendarMemos()
            .receive(on: DispatchQueue.main)
            .catch { error -> Just<[CalendarMemo]> in
                print("[CalendarMemo] Error observing: \(error)")
                return Just([])
            }
            .sink { [weak self] memoList in
                var dict: [String: String] = [:]
                for memo in memoList {
                    dict[memo.dateKey] = memo.content
                }
                self?.memos = dict
            }
            .store(in: &cancellables)
    }

    // MARK: - Save Memo

    func saveMemo(_ text: String, for dateKey: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if trimmed.isEmpty {
                // Delete the memo
                let deleted = try await database.write { db -> CalendarMemo? in
                    guard let memo = try CalendarMemo
                        .filter(CalendarMemo.Columns.dateKey == dateKey)
                        .fetchOne(db) else { return nil }
                    try memo.delete(db)
                    return memo
                }
                if let memo = deleted {
                    syncLogger?.logCalendarMemoDelete(memo.id)
                }
            } else if let existing = try await database.read({ db in
                try CalendarMemo
                    .filter(CalendarMemo.Columns.dateKey == dateKey)
                    .fetchOne(db)
            }) {
                // Update existing
                let updated = try await database.write { db -> CalendarMemo in
                    var memo = existing
                    memo.content = trimmed
                    memo.touch()
                    try memo.update(db)
                    return memo
                }
                syncLogger?.logCalendarMemoUpdate(updated)
            } else {
                // Create new
                let memo = try await database.write { db -> CalendarMemo in
                    var memo = CalendarMemo(dateKey: dateKey, content: trimmed)
                    try memo.insert(db)
                    return memo
                }
                syncLogger?.logCalendarMemoCreate(memo)
            }
        } catch {
            print("[CalendarMemo] Failed to save memo for \(dateKey): \(error)")
        }
    }

    // MARK: - Read

    func getMemo(dateKey: String) async throws -> CalendarMemo? {
        try await database.read { db in
            try CalendarMemo
                .filter(CalendarMemo.Columns.dateKey == dateKey)
                .fetchOne(db)
        }
    }

    func getAllMemos() async throws -> [CalendarMemo] {
        try await database.read { db in
            try CalendarMemo.fetchAll(db)
        }
    }
}
