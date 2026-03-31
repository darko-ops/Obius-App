import Foundation
import UserNotifications
import Combine

@MainActor
final class EchoManager: ObservableObject {
    static let shared = EchoManager()

    @Published private(set) var activeEchoes: [Echo] = []
    @Published private(set) var isLoaded: Bool = false
    /// Set when an echo fires while the app is open — used for in-app banner
    @Published var firedEcho: Echo?

    private var echoRepository: EchoRepository?
    private var cancellables = Set<AnyCancellable>()
    private var checkTimer: Timer?

    private init() {}

    /// Initialize with repository — call once during app startup
    func initialize(echoRepository: EchoRepository) {
        self.echoRepository = echoRepository

        echoRepository.$activeEchoes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] echoes in
                self?.activeEchoes = echoes
                self?.isLoaded = true
                // Recalculate the next fire timer whenever echoes change
                self?.scheduleNextCheck()
            }
            .store(in: &cancellables)
    }

    /// Schedule a precise timer for the next echo fire date
    func scheduleNextCheck() {
        checkTimer?.invalidate()
        checkTimer = nil

        // Find the soonest upcoming fire date across all active echoes
        let now = Date()
        var soonest: Date?

        for echo in activeEchoes where echo.isActive {
            if echo.isRecurring {
                if let next = echo.computedNextFireDate, next > now {
                    if soonest == nil || next < soonest! { soonest = next }
                }
            } else {
                let fire = echo.fireDateAsDate
                if fire > now {
                    if soonest == nil || fire < soonest! { soonest = fire }
                }
            }
        }

        guard let targetDate = soonest else { return }

        let delay = targetDate.timeIntervalSince(now)
        guard delay > 0 else { return }

        checkTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForFiredEchoes()
                // Schedule the next one
                self?.scheduleNextCheck()
            }
        }
    }

    func stopPeriodicCheck() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    // MARK: - Notification Permission

    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                print("EchoManager: Notification permission not granted")
            }
        } catch {
            print("EchoManager: Error requesting notification permission: \(error)")
        }
    }

    // MARK: - Schedule / Cancel

    func scheduleEcho(_ echo: Echo) {
        let center = UNUserNotificationCenter.current()
        let handleName = getHandleName(for: echo)
        let now = Date()

        // Non-recurring echo that already fired is complete — don't schedule anything
        if !echo.isRecurring && echo.fireDateAsDate <= now {
            cancelEcho(echo.id)
            return
        }

        let baseContent = UNMutableNotificationContent()
        baseContent.title = "Echo: @\(handleName)"
        baseContent.body = echo.cadenceDescription
        baseContent.sound = .default
        baseContent.userInfo = ["echoId": echo.id, "handleId": echo.handleId]

        // Determine the target fire date
        let targetDate: Date
        if echo.isRecurring, let nextFire = echo.computedNextFireDate, nextFire > now {
            targetDate = nextFire
        } else {
            targetDate = echo.fireDateAsDate
        }

        // Only schedule if target is in the future
        guard targetDate > now else { return }

        // Schedule a one-time notification at the exact fire time
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: targetDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let fireContent = baseContent.mutableCopy() as! UNMutableNotificationContent
        fireContent.body = echo.isRecurring ? echo.cadenceDescription : echo.cadenceDescription

        let request = UNNotificationRequest(
            identifier: "echo_\(echo.id)_start",
            content: fireContent,
            trigger: trigger
        )
        center.add(request) { error in
            if let error {
                print("EchoManager: Failed to schedule notification: \(error)")
            }
        }

        // Schedule reminder notifications (only after the fire date)
        let reminderOffsets: [TimeInterval] = [3600, 7200, 10800, 21600, 43200, 86400]
        for (index, offset) in reminderOffsets.enumerated() {
            let reminderDate = targetDate.addingTimeInterval(offset)
            guard reminderDate > now else { continue }

            let reminderContent = UNMutableNotificationContent()
            reminderContent.title = "Echo reminder"
            reminderContent.body = "@\(handleName) still needs attention"
            reminderContent.sound = .default
            reminderContent.userInfo = ["echoId": echo.id, "handleId": echo.handleId]

            let reminderComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: reminderDate
            )
            let reminderTrigger = UNCalendarNotificationTrigger(dateMatching: reminderComponents, repeats: false)

            let reminderRequest = UNNotificationRequest(
                identifier: "echo_\(echo.id)_reminder_\(index)",
                content: reminderContent,
                trigger: reminderTrigger
            )
            center.add(reminderRequest) { error in
                if let error {
                    print("EchoManager: Failed to schedule reminder \(index): \(error)")
                }
            }
        }
    }

    func cancelEcho(_ echoId: String) {
        let center = UNUserNotificationCenter.current()

        // Build list of all possible notification IDs for this echo
        var identifiers = ["echo_\(echoId)_start"]
        for i in 0...9 {
            identifiers.append("echo_\(echoId)_interval_\(i)")
        }
        for i in 0...5 {
            identifiers.append("echo_\(echoId)_reminder_\(i)")
        }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func rescheduleAllEchoes() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for echo in activeEchoes where echo.isActive {
            scheduleEcho(echo)
        }
    }

    // MARK: - Convenience Wrappers

    func createEcho(
        handleId: String,
        isRecurring: Bool,
        intervals: [EchoInterval],
        fireDate: Date
    ) async throws -> Echo {
        guard let repository = echoRepository else {
            throw EchoError.notInitialized
        }
        let fireDateMs = Int64(fireDate.timeIntervalSince1970 * 1000)

        let echo = try await repository.createEcho(
            handleId: handleId,
            isRecurring: isRecurring,
            intervals: intervals,
            fireDate: fireDateMs
        )

        scheduleEcho(echo)
        return echo
    }

    func createEcho(handleId: String, config: EchoConfig) async throws -> Echo {
        return try await createEcho(
            handleId: handleId,
            isRecurring: config.isRecurring,
            intervals: config.isRecurring ? config.intervals : [],
            fireDate: config.startDate
        )
    }

    func deleteEcho(id: String) async throws {
        guard let repository = echoRepository else {
            throw EchoError.notInitialized
        }

        cancelEcho(id)
        try await repository.deleteEcho(id: id)
    }

    func deactivateEcho(id: String) async throws {
        guard let repository = echoRepository else {
            throw EchoError.notInitialized
        }

        cancelEcho(id)
        try await repository.deactivateEcho(id: id)
    }

    func updateEcho(
        id: String,
        isRecurring: Bool,
        intervals: [EchoInterval],
        fireDate: Date
    ) async throws {
        guard let repository = echoRepository else {
            throw EchoError.notInitialized
        }

        cancelEcho(id)

        let fireDateMs = Int64(fireDate.timeIntervalSince1970 * 1000)
        try await repository.updateEcho(
            id: id,
            isRecurring: isRecurring,
            intervals: intervals,
            fireDate: fireDateMs
        )

        // Reschedule with updated settings
        if let updated = try await repository.getEcho(id: id) {
            scheduleEcho(updated)
        }
    }

    // MARK: - Acknowledge / Alert State

    func acknowledgeEcho(id: String) async throws {
        guard let repository = echoRepository else {
            throw EchoError.notInitialized
        }

        try await repository.acknowledgeEcho(id: id)
    }

    /// Complete an echo: acknowledge it and stop all notifications.
    /// For recurring echoes, reschedules for the next cycle.
    /// For one-time echoes, deactivates it entirely.
    func completeEcho(id: String) async throws {
        guard let repository = echoRepository else {
            throw EchoError.notInitialized
        }

        try await repository.acknowledgeEcho(id: id)

        // Cancel all current notifications immediately
        cancelEcho(id)

        // For recurring echoes, update next fire date and reschedule
        if let echo = activeEchoes.first(where: { $0.id == id }), echo.isRecurring {
            // Refresh from DB to get updated lastAcknowledgedAt and recomputed nextFireDate
            try await repository.updateNextFireDate(id: id)
            if let refreshed = try await repository.getEcho(id: id) {
                scheduleEcho(refreshed)
            }
        }
    }

    func checkForFiredEchoes() async {
        guard let repository = echoRepository else { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        for echo in activeEchoes where echo.isActive && echo.fireDate <= now {
            // Already alerted — nothing to do
            guard !echo.isAlerted else { continue }

            if echo.isRecurring {
                // Recurring: check if acknowledged for the current cycle
                if let ack = echo.lastAcknowledgedAt,
                   let cycleDate = echo.mostRecentFireDate {
                    let cycleDateMs = Int64(cycleDate.timeIntervalSince1970 * 1000)
                    if ack >= cycleDateMs {
                        continue
                    }
                }
            } else {
                // Non-recurring: skip if already acknowledged (already completed)
                if echo.lastAcknowledgedAt != nil {
                    cancelEcho(echo.id)
                    continue
                }
            }

            try? await repository.alertEcho(id: echo.id)
            firedEcho = echo
        }
    }

    // MARK: - Display Helpers

    func getHandleName(for echo: Echo) -> String {
        HandleManager.shared.getHandle(id: echo.handleId)?.displayName ?? "Unknown"
    }

    func getNextFireDescription(for echo: Echo) -> String {
        guard let nextDate = echo.nextFireDateAsDate else {
            return echo.cadenceDescription
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: nextDate, relativeTo: Date())
    }
}

// MARK: - Echo Errors

enum EchoError: LocalizedError {
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "EchoManager not initialized"
        }
    }
}
