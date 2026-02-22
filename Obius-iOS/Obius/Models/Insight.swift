import Foundation
import GRDB

/// The type of insight the system has detected from user content
enum InsightType: String, Codable, DatabaseValueConvertible, CaseIterable {
    case suggestedTask       // Content that reads like a task/action item
    case openQuestion        // An unanswered question detected in content
    case connection          // Two or more notes/sections share overlapping themes
    case staleContent        // Content that hasn't been touched in a while
    case growingNote         // A note that's accumulating a lot of content quickly
    case lonelyHandle        // A handle that's only referenced once
}

/// The user's disposition toward an insight
enum InsightStatus: String, Codable, DatabaseValueConvertible {
    case surfaced            // Newly generated, shown to user
    case tracked             // User confirmed — acts like a pin
    case dismissed           // User swiped away / not interested
}

/// A system-generated insight about the user's content.
/// When tracked, it acts as a lightweight pin for nodes and pages.
struct Insight: Codable, Identifiable, Hashable {
    var id: String
    var insightType: InsightType
    var title: String
    var body: String
    var status: InsightStatus

    // Source references — which content triggered this insight
    var sourceNoteId: String?
    var sourceSectionId: String?
    var relatedNoteId: String?       // For connection-type insights (the second note)

    var createdAt: Int64
    var updatedAt: Int64

    init(
        id: String = UUID().uuidString,
        insightType: InsightType,
        title: String,
        body: String,
        status: InsightStatus = .surfaced,
        sourceNoteId: String? = nil,
        sourceSectionId: String? = nil,
        relatedNoteId: String? = nil,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.insightType = insightType
        self.title = title
        self.body = body
        self.status = status
        self.sourceNoteId = sourceNoteId
        self.sourceSectionId = sourceSectionId
        self.relatedNoteId = relatedNoteId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: Double(createdAt) / 1000)
    }

    var updatedDate: Date {
        Date(timeIntervalSince1970: Double(updatedAt) / 1000)
    }
}

// MARK: - GRDB Conformance

extension Insight: FetchableRecord, PersistableRecord {
    static let databaseTableName = "insights"

    enum Columns: String, ColumnExpression {
        case id, insightType, title, body, status
        case sourceNoteId, sourceSectionId, relatedNoteId
        case createdAt, updatedAt
    }
}

// MARK: - Mutations

extension Insight {
    mutating func touch() {
        updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    }

    mutating func track() {
        status = .tracked
        touch()
    }

    mutating func dismiss() {
        status = .dismissed
        touch()
    }
}

// MARK: - Display Helpers

extension InsightType {
    var icon: String {
        switch self {
        case .suggestedTask:  return "checkmark.circle"
        case .openQuestion:   return "questionmark.bubble"
        case .connection:     return "link"
        case .staleContent:   return "clock.arrow.circlepath"
        case .growingNote:    return "chart.line.uptrend.xyaxis"
        case .lonelyHandle:   return "at"
        }
    }

    var label: String {
        switch self {
        case .suggestedTask:  return "Task"
        case .openQuestion:   return "Question"
        case .connection:     return "Connection"
        case .staleContent:   return "Stale"
        case .growingNote:    return "Growing"
        case .lonelyHandle:   return "Lonely Handle"
        }
    }

    var tint: InsightTint {
        switch self {
        case .suggestedTask:  return .green
        case .openQuestion:   return .yellow
        case .connection:     return .purple
        case .staleContent:   return .gray
        case .growingNote:    return .blue
        case .lonelyHandle:   return .orange
        }
    }
}

/// Lightweight color tokens for insight cards (avoids coupling to IntentType)
enum InsightTint {
    case green, yellow, purple, gray, blue, orange
}
