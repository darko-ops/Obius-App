import Foundation
import UserNotifications
import Combine

@MainActor
final class EchoManager: ObservableObject {
    static let shared = EchoManager()

    @Published private(set) var activeEchoes: [Echo] = []
    @Published private(set) var isLoaded: Bool = false

    private var echoRepository: EchoRepository?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    /// Initialize with repository — call once during app startup
    func initialize(echoRepository: EchoRepository) {
        self.echoRepository = echoRepository

        echoRepository.$activeEchoes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] echoes in
                self?.activeEchoes = echoes
                self?.isLoaded = true
            }
            .store(in: &cancellables)
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

        let startDate = echo.fireDateAsDate

        // Non-recurring echo that already fired is complete — don't schedule anything
        if !echo.isRecurring && startDate <= Date() {
            cancelEcho(echo.id)
            return
        }

        let baseContent = UNMutableNotificationContent()
        baseContent.title = "Echo: @\(handleName)"
        baseContent.body = echo.cadenceDescription
        baseContent.sound = .default
        baseContent.userInfo = ["echoId": echo.id, "handleId": echo.handleId]

        // Always schedule a one-time notification for the start date (if in future)
        if startDate > Date() {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: startDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let startContent = baseContent.mutableCopy() as! UNMutableNotificationContent
            startContent.body = echo.isRecurring ? "Recurring echo started" : echo.cadenceDescription

            let request = UNNotificationRequest(
                identifier: "echo_\(echo.id)_start",
                content: startContent,
                trigger: trigger
            )
            center.add(request) { error in
                if let error {
                    print("EchoManager: Failed to schedule start notification: \(error)")
                }
            }
        }

        // If recurring, schedule a repeating trigger for each interval
        if echo.isRecurring {
            for (index, interval) in echo.intervals.enumerated() {
                let seconds = max(interval.timeIntervalSeconds, 60) // iOS minimum: 60s

                let intervalContent = baseContent.mutableCopy() as! UNMutableNotificationContent
                intervalContent.body = interval.description.capitalized

                // If startDate is in the future, we need to delay the recurring trigger.
                // iOS doesn't support "start at X then repeat every Y", so we schedule
                // the repeating trigger immediately — the start notification covers the first alert.
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: true)

                let request = UNNotificationRequest(
                    identifier: "echo_\(echo.id)_interval_\(index)",
                    content: intervalContent,
                    trigger: trigger
                )
                center.add(request) { error in
                    if let error {
                        print("EchoManager: Failed to schedule interval \(index) notification: \(error)")
                    }
                }
            }
        }

        // Schedule hourly reminder notifications for unaddressed echoes
        let reminderOffsets: [TimeInterval] = [3600, 7200, 10800, 21600, 43200, 86400] // 1h, 2h, 3h, 6h, 12h, 24h
        for (index, offset) in reminderOffsets.enumerated() {
            let reminderDate = startDate.addingTimeInterval(offset)
            guard reminderDate > Date() else { continue }

            let reminderContent = UNMutableNotificationContent()
            reminderContent.title = "Echo reminder"
            reminderContent.body = "@\(handleName) still needs attention"
            reminderContent.sound = .default
            reminderContent.userInfo = ["echoId": echo.id, "handleId": echo.handleId]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: reminderDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let request = UNNotificationRequest(
                identifier: "echo_\(echo.id)_reminder_\(index)",
                content: reminderContent,
                trigger: trigger
            )
            center.add(request) { error in
                if let error {
                    print("EchoManager: Failed to schedule reminder \(index) notification: \(error)")
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

        // Cancel all notifications for this echo (start, intervals, and reminders)
        cancelEcho(id)
    }

    func checkForFiredEchoes() async {
        guard let repository = echoRepository else { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        for echo in activeEchoes where echo.isActive && echo.fireDate <= now {
            // Non-recurring echo that already fired is complete — cancel all notifications
            if !echo.isRecurring {
                cancelEcho(echo.id)
                continue
            }

            guard !echo.isAlerted else { continue }

            // Skip if already acknowledged for this fire cycle
            if let ack = echo.lastAcknowledgedAt, ack >= echo.fireDate {
                continue
            }
            try? await repository.alertEcho(id: echo.id)
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
