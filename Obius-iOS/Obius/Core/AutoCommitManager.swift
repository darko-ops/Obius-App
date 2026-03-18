import Foundation

/// Automatically creates daily commits for notes that were modified since the last check.
/// Runs on app launch and when the app returns to the foreground, after a day boundary crossing.
@MainActor
class AutoCommitManager {
    private let commitModule: CommitModule
    private let noteRepository: NoteRepository
    private let commitRepository: CommitRepository
    private let sectionRepository: SectionRepository
    private let coldStore: ColdStore

    private static let lastCheckDateKey = "autoCommit_lastCheckDate"

    init(
        commitModule: CommitModule,
        noteRepository: NoteRepository,
        commitRepository: CommitRepository,
        sectionRepository: SectionRepository,
        coldStore: ColdStore
    ) {
        self.commitModule = commitModule
        self.noteRepository = noteRepository
        self.commitRepository = commitRepository
        self.sectionRepository = sectionRepository
        self.coldStore = coldStore
    }

    /// Checks whether a day boundary has been crossed since the last check,
    /// and creates auto-commits for notes the user edited yesterday.
    func checkAndAutoCommit() async {
        guard TierManager.shared.limits.commits else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 1. Read last check date
        guard let lastCheckEpoch = UserDefaults.standard.object(forKey: Self.lastCheckDateKey) as? Double else {
            // First launch ever — record today, no retroactive commits
            UserDefaults.standard.set(today.timeIntervalSince1970, forKey: Self.lastCheckDateKey)
            return
        }

        let lastCheckDate = calendar.startOfDay(for: Date(timeIntervalSince1970: lastCheckEpoch))

        // 2. Same calendar day — nothing to do
        guard lastCheckDate < today else { return }

        // 3. Day boundary crossed — only auto-commit notes edited between
        //    the last check and today (i.e. yesterday's edits, not older ones)
        let lastCheckMs = Int64(lastCheckDate.timeIntervalSince1970 * 1000)
        let todayMs = Int64(today.timeIntervalSince1970 * 1000)
        let notes = noteRepository.notes

        for note in notes {
            do {
                try await autoCommitIfNeeded(note: note, editWindowStartMs: lastCheckMs, editWindowEndMs: todayMs)
            } catch {
                // Log but don't block other notes
                print("[AutoCommit] Failed for note \(note.id): \(error.localizedDescription)")
            }
        }

        // 4. Update last check date
        UserDefaults.standard.set(today.timeIntervalSince1970, forKey: Self.lastCheckDateKey)
    }

    private func autoCommitIfNeeded(note: Note, editWindowStartMs: Int64, editWindowEndMs: Int64) async throws {
        // Skip deleted pages
        if note.isDeleted { return }

        // Only auto-commit notes edited within the window (since last check, before today)
        guard note.updatedAt >= editWindowStartMs && note.updatedAt < editWindowEndMs else {
            return
        }

        // Fetch sections once for both content check and title generation
        let sections = try await sectionRepository.getSections(noteId: note.id)

        // Get latest commit for this note
        let latestCommit = try await commitRepository.getLatestCommit(noteId: note.id)

        if let latestCommit = latestCommit {
            // Skip if note hasn't been modified since the last commit
            if note.updatedAt <= latestCommit.createdAt {
                return
            }
        } else {
            // No commits yet — skip if note has no content
            if note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sections.isEmpty {
                return
            }
        }

        // Format the commit name: "Page Title · Feb 19"
        let noteUpdatedDate = Date(timeIntervalSince1970: Double(note.updatedAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dateLabel = formatter.string(from: noteUpdatedDate)
        let pageTitle = note.displayTitle(sections: sections)
        let commitName = "\(pageTitle) \u{00B7} \(dateLabel)"

        // Create the auto-commit (ColdStore handles hash dedup — identical content produces same hash)
        _ = try await commitModule.createCommit(
            noteId: note.id,
            name: commitName,
            isAutoCommit: true
        )
    }
}
