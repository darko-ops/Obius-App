import Foundation
import GRDB
import SwiftUI

// MARK: - InsightType

enum InsightType: String, Codable, DatabaseValueConvertible, CaseIterable {
    case suggestedTask   // Content that reads like an action item
    case openQuestion    // Unanswered question detected in content
    case staleContent    // Note untouched for 14+ days
    case growingNote     // Note accumulating many sections quickly
    case lonelyHandle    // Handle only referenced in one place
    case connection      // (future) Two notes share overlapping themes
    case nonsenseContent // Page with meaningless/gibberish content
    case upcomingEcho    // Echo firing within 24 hours
    case conceptCluster  // 3+ notes share the same hashtag
    case aiSuggestion    // AI-powered suggestion (echo, intent, connection, handle)
    case activeLoop      // Handle edited recently + used on 2+ pages
    case dormantLoop     // Handle not edited in 14+ days
    case emergingLoop    // Handle used on 3+ pages this week
    case loopConnection  // Two handles appear on the same page
    case suggestedEcho   // AI-detected temporal phrase suggesting an Echo

    var icon: String {
        switch self {
        case .suggestedTask:  return "checkmark.circle"
        case .openQuestion:   return "questionmark.bubble"
        case .staleContent:   return "clock.arrow.circlepath"
        case .growingNote:    return "chart.line.uptrend.xyaxis"
        case .lonelyHandle:   return "link"
        case .connection:     return "arrow.triangle.branch"
        case .nonsenseContent: return "trash.circle"
        case .upcomingEcho:   return "bell.badge"
        case .conceptCluster: return "number"
        case .aiSuggestion:   return "sparkles"
        case .activeLoop:     return "arrow.triangle.2.circlepath"
        case .dormantLoop:    return "moon.zzz"
        case .emergingLoop:   return "arrow.up.right"
        case .loopConnection: return "link.badge.plus"
        case .suggestedEcho:  return "bell.and.waves.left.and.right"
        }
    }

    var label: String {
        switch self {
        case .suggestedTask:  return "Task"
        case .openQuestion:   return "Question"
        case .staleContent:   return "Stale"
        case .growingNote:    return "Growing"
        case .lonelyHandle:   return "Lonely Loop"
        case .connection:     return "Connection"
        case .nonsenseContent: return "Cleanup"
        case .upcomingEcho:   return "Echo"
        case .conceptCluster: return "Cluster"
        case .aiSuggestion:   return "AI"
        case .activeLoop:     return "Loop"
        case .dormantLoop:    return "Dormant"
        case .emergingLoop:   return "Emerging"
        case .loopConnection: return "Connected"
        case .suggestedEcho:  return "Echo"
        }
    }

    var tint: InsightTint {
        switch self {
        case .suggestedTask:  return .green
        case .openQuestion:   return .yellow
        case .staleContent:   return .gray
        case .growingNote:    return .purple
        case .lonelyHandle:   return .orange
        case .connection:     return .blue
        case .nonsenseContent: return .red
        case .upcomingEcho:   return .orange
        case .conceptCluster: return .blue
        case .aiSuggestion:   return .blue
        case .activeLoop:     return .green
        case .dormantLoop:    return .gray
        case .emergingLoop:   return .purple
        case .loopConnection: return .blue
        case .suggestedEcho:  return .orange
        }
    }
}

// MARK: - InsightTint

enum InsightTint: String, Codable {
    case green, yellow, purple, gray, blue, orange, red

    var color: Color {
        switch self {
        case .green:  return .green
        case .yellow: return .yellow
        case .purple: return .purple
        case .gray:   return .gray
        case .blue:   return .blue
        case .orange: return .orange
        case .red:    return .red
        }
    }
}

// MARK: - InsightStatus

enum InsightStatus: String, Codable, DatabaseValueConvertible {
    case surfaced   // Newly generated, shown to user
    case tracked    // User confirmed; lightweight pin
    case dismissed  // User dismissed
}

// MARK: - Insight

struct Insight: Codable, Identifiable, Hashable {
    var id: String
    var insightType: InsightType
    var title: String
    var body: String
    var status: InsightStatus
    var sourceNoteId: String?
    var sourceSectionId: String?
    var relatedNoteId: String?
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

// MARK: - Dedup

extension Insight {
    /// Stable key used to prevent duplicate insights across scans.
    /// Tasks and questions dedup per-note (consolidated), others include sectionId.
    var dedupKey: String {
        switch insightType {
        case .suggestedTask, .openQuestion, .suggestedEcho:
            // One insight per note — consolidated
            return "\(insightType.rawValue)|\(sourceNoteId ?? "")|"
        default:
            return "\(insightType.rawValue)|\(sourceNoteId ?? "")|\(sourceSectionId ?? "")"
        }
    }
}

// MARK: - Display (AI subtype-aware)

extension Insight {
    /// Icon that reflects the AI suggestion subtype, or falls back to the insight type icon.
    var displayIcon: String {
        guard insightType == .aiSuggestion, let subtype = sourceSectionId else {
            return insightType.icon
        }
        switch subtype {
        case "echo_suggestion":   return "bell.badge"
        case "intent_correction": return "arrow.triangle.swap"
        case "connection":        return "arrow.triangle.branch"
        case "handle_promotion":  return "link"
        default:                  return insightType.icon
        }
    }

    /// Label that reflects the AI suggestion subtype.
    var displayLabel: String {
        guard insightType == .aiSuggestion, let subtype = sourceSectionId else {
            return insightType.label
        }
        switch subtype {
        case "echo_suggestion":   return "Echo"
        case "intent_correction": return "Intent"
        case "connection":        return "Link"
        case "handle_promotion":  return "Loop"
        default:                  return insightType.label
        }
    }

    /// Tint that reflects the AI suggestion subtype.
    var displayTint: InsightTint {
        guard insightType == .aiSuggestion, let subtype = sourceSectionId else {
            return insightType.tint
        }
        switch subtype {
        case "echo_suggestion":   return .orange
        case "intent_correction": return .yellow
        case "connection":        return .blue
        case "handle_promotion":  return .purple
        default:                  return insightType.tint
        }
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
