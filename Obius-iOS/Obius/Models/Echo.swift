import Foundation
import GRDB

// MARK: - Echo Interval Unit

enum EchoIntervalUnit: String, Codable, CaseIterable {
    case minutes
    case hours
    case days
    case weeks
    case months

    var displayName: String {
        switch self {
        case .minutes: return "Minutes"
        case .hours: return "Hours"
        case .days: return "Days"
        case .weeks: return "Weeks"
        case .months: return "Months"
        }
    }

    var singularName: String {
        switch self {
        case .minutes: return "Minute"
        case .hours: return "Hour"
        case .days: return "Day"
        case .weeks: return "Week"
        case .months: return "Month"
        }
    }
}

// MARK: - Echo Interval

struct EchoInterval: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var value: Int
    var unit: EchoIntervalUnit

    /// Time interval in seconds
    var timeIntervalSeconds: TimeInterval {
        switch unit {
        case .minutes: return TimeInterval(value * 60)
        case .hours: return TimeInterval(value * 3600)
        case .days: return TimeInterval(value * 86400)
        case .weeks: return TimeInterval(value * 604800)
        case .months: return TimeInterval(value * 2592000) // ~30 days
        }
    }

    /// Human-readable description (e.g. "every 10 hours")
    var description: String {
        if value == 1 {
            return "every \(unit.singularName.lowercased())"
        }
        return "every \(value) \(unit.displayName.lowercased())"
    }
}

// MARK: - Echo

struct Echo: Codable, Identifiable, Hashable {
    var id: String
    var handleId: String
    var isRecurring: Bool
    var intervalsJSON: String?
    var fireDate: Int64           // Start date (ms since epoch) — always required
    var isActive: Bool
    var nextFireDate: Int64?      // Computed next fire time (ms since epoch)
    var isAlerted: Bool
    var lastAcknowledgedAt: Int64?
    var createdAt: Int64
    var updatedAt: Int64

    init(
        id: String = UUID().uuidString,
        handleId: String,
        isRecurring: Bool = false,
        intervalsJSON: String? = nil,
        fireDate: Int64,
        isActive: Bool = true,
        nextFireDate: Int64? = nil,
        isAlerted: Bool = false,
        lastAcknowledgedAt: Int64? = nil,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.handleId = handleId
        self.isRecurring = isRecurring
        self.intervalsJSON = intervalsJSON
        self.fireDate = fireDate
        self.isActive = isActive
        self.nextFireDate = nextFireDate
        self.isAlerted = isAlerted
        self.lastAcknowledgedAt = lastAcknowledgedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed Properties

    var fireDateAsDate: Date {
        Date(timeIntervalSince1970: Double(fireDate) / 1000)
    }

    var nextFireDateAsDate: Date? {
        guard let nextFireDate else { return nil }
        return Date(timeIntervalSince1970: Double(nextFireDate) / 1000)
    }

    /// Decoded intervals from JSON
    var intervals: [EchoInterval] {
        guard let json = intervalsJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([EchoInterval].self, from: data)) ?? []
    }

    /// Human-readable cadence description
    var cadenceDescription: String {
        if !isRecurring {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: fireDateAsDate)
        }

        let ints = intervals
        if ints.isEmpty {
            return "Recurring"
        }

        let descriptions = ints.map { interval -> String in
            if interval.value == 1 {
                return "Every \(interval.unit.singularName.lowercased())"
            }
            return "Every \(interval.value) \(interval.unit.displayName.lowercased())"
        }
        return descriptions.joined(separator: ", ")
    }

    /// Compute the next fire date — soonest across all intervals from the start date
    var computedNextFireDate: Date? {
        let startDate = fireDateAsDate
        let now = Date()

        if !isRecurring {
            // One-time: the fire date itself (if in the future)
            return startDate > now ? startDate : nil
        }

        let ints = intervals
        if ints.isEmpty { return nil }

        var soonest: Date?

        for interval in ints {
            var components = DateComponents()
            switch interval.unit {
            case .minutes: components.minute = interval.value
            case .hours: components.hour = interval.value
            case .days: components.day = interval.value
            case .weeks: components.day = interval.value * 7
            case .months: components.month = interval.value
            }

            // Walk forward from startDate by this interval until we pass now
            var candidate = startDate
            while candidate <= now {
                guard let next = Calendar.current.date(byAdding: components, to: candidate) else { break }
                candidate = next
            }

            if soonest == nil || candidate < soonest! {
                soonest = candidate
            }
        }

        return soonest
    }
}

// MARK: - GRDB Conformance

extension Echo: FetchableRecord, PersistableRecord {
    static let databaseTableName = "echoes"

    enum Columns: String, ColumnExpression {
        case id, handleId, isRecurring, intervalsJSON
        case fireDate, isActive, nextFireDate, isAlerted, lastAcknowledgedAt, createdAt, updatedAt
    }

    // Relationship to handle
    static let handle = belongsTo(Handle.self)

    var handle: QueryInterfaceRequest<Handle> {
        request(for: Echo.handle)
    }
}

// MARK: - Mutations

extension Echo {
    mutating func touch() {
        updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    }

    mutating func deactivate() {
        isActive = false
        touch()
    }

    mutating func updateNextFireDate() {
        if let next = computedNextFireDate {
            nextFireDate = Int64(next.timeIntervalSince1970 * 1000)
        }
        touch()
    }

    mutating func alert() {
        isAlerted = true
        touch()
    }

    mutating func acknowledge() {
        isAlerted = false
        lastAcknowledgedAt = Int64(Date().timeIntervalSince1970 * 1000)
        touch()
    }
}

// MARK: - Echo Config (temporary, pre-creation)

struct EchoConfig {
    var startDate: Date = Date().addingTimeInterval(300)
    var isRecurring: Bool = false
    var intervals: [EchoInterval] = [EchoInterval(value: 1, unit: .days)]
}

// MARK: - Helpers

extension EchoConfig {
    /// Encode intervals to JSON string
    var intervalsJSON: String? {
        guard isRecurring, !intervals.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(intervals) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
