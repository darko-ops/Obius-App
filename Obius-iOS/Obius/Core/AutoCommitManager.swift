import Foundation
import BackgroundTasks

/// Automatically creates daily commits for notes modified since the last check.
/// Schedules a BGProcessingTask to run at midnight so versions are created
/// even if the user doesn't open the app the next day.
@MainActor
class AutoCommitManager {
    private let commitModule: CommitModule
    private let noteRepository: NoteRepository
    private let commitRepository: CommitRepository
    private let sectionRepository: SectionRepository
    private let coldStore: ColdStore

    private static let lastCheckDateKey = "autoCommit_lastCheckDate"
    static let backgroundTaskId = "app.obius.ios.autocommit"

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

    // MARK: - Background Task Registration

    /// Call once during app launch (in ObiusApp.init) to register the handler.
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskId,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                // AppState may not be alive in background — create minimal commit path
                await AppState.backgroundAutoCommit(task: processingTask)
            }
        }
    }

    /// Schedule the next midnight auto-commit background task.
    func scheduleMidnightTask() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskId)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        // Schedule for next midnight
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
        request.earliestBeginDate = tomorrow

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[AutoCommit] Failed to schedule midnight task: \(error)")
        }
    }

    // MARK: - Auto Commit Logic

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
            scheduleMidnightTask()
            return
        }

        let lastCheckDate = calendar.startOfDay(for: Date(timeIntervalSince1970: lastCheckEpoch))

        // 2. Same calendar day — nothing to do
        guard lastCheckDate < today else {
            scheduleMidnightTask()
            return
        }

        // 3. Day boundary crossed — auto-commit notes edited between last check and today
        let lastCheckMs = Int64(lastCheckDate.timeIntervalSince1970 * 1000)
        let todayMs = Int64(today.timeIntervalSince1970 * 1000)
        let notes = noteRepository.notes

        for note in notes {
            do {
                try await autoCommitIfNeeded(note: note, editWindowStartMs: lastCheckMs, editWindowEndMs: todayMs)
            } catch {
                print("[AutoCommit] Failed for note \(note.id): \(error.localizedDescription)")
            }
        }

        // 4. Update last check date and schedule next midnight
        UserDefaults.standard.set(today.timeIntervalSince1970, forKey: Self.lastCheckDateKey)
        scheduleMidnightTask()
    }

    private func autoCommitIfNeeded(note: Note, editWindowStartMs: Int64, editWindowEndMs: Int64) async throws {
        // Skip deleted pages
        if note.isDeleted { return }

        // Only auto-commit notes edited within the window (since last check, before today)
        guard note.updatedAt >= editWindowStartMs && note.updatedAt < editWindowEndMs else {
            return
        }

        // Fetch sections for content check and title generation
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

        _ = try await commitModule.createCommit(
            noteId: note.id,
            name: commitName,
            isAutoCommit: true
        )
    }
}
