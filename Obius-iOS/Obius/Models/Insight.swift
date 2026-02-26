import Foundation
import GRDB
import SwiftUI

// MARK: - InsightType

enum InsightType: String, Codable, DatabaseValueConvertible, CaseIterable, Identifiable {
    var id: String { rawValue }
    case cleanup        // Stale notes, dormant/lonely loops, nonsense
    case reminder       // Tasks, open questions, suggested echoes
    case safety         // API keys, passwords, personal data
    case drift          // Off-topic notes, orphan tags (Phase 2: AI)
    case weeklyReport   // Activity digest (Phase 2: AI)
    case progress       // Project health score (Phase 2: AI)
    case upcomingEcho   // Dashboard element — fires within 24h

    var icon: String {
        switch self {
        case .cleanup:      return "trash.circle"
        case .reminder:     return "bell.badge"
        case .safety:       return "exclamationmark.shield"
        case .drift:        return "safari"
        case .weeklyReport: return "chart.bar.doc.horizontal"
        case .progress:     return "gauge.with.dots.needle.33percent"
        case .upcomingEcho: return "bell.badge"
        }
    }

    var label: String {
        switch self {
        case .cleanup:      return "Clean Up"
        case .reminder:     return "Reminders"
        case .safety:       return "Safety"
        case .drift:        return "Drift"
        case .weeklyReport: return "Weekly"
        case .progress:     return "Progress"
        case .upcomingEcho: return "Echo"
        }
    }

    var tint: InsightTint {
        switch self {
        case .cleanup:      return .gray
        case .reminder:     return .orange
        case .safety:       return .red
        case .drift:        return .blue
        case .weeklyReport: return .purple
        case .progress:     return .green
        case .upcomingEcho: return .orange
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
    /// Reminders (task/question) dedup per-note (consolidated), others include sectionId.
    var dedupKey: String {
        switch insightType {
        case .reminder:
            // One insight per note per subtype
            return "\(insightType.rawValue)|\(sourceNoteId ?? "")|\(sourceSectionId ?? "")"
        default:
            return "\(insightType.rawValue)|\(sourceNoteId ?? "")|\(sourceSectionId ?? "")"
        }
    }
}

// MARK: - Display (subtype-aware)

extension Insight {
    /// Icon that reflects the subtype stored in sourceSectionId.
    var displayIcon: String {
        guard let subtype = sourceSectionId else { return insightType.icon }

        switch insightType {
        case .cleanup:
            switch subtype {
            case "stale":        return "clock.arrow.circlepath"
            case "dormant_loop": return "moon.zzz"
            case "lonely_loop":  return "link"
            case "nonsense":     return "trash.circle"
            default:             return insightType.icon
            }
        case .reminder:
            switch subtype {
            case "task":           return "checkmark.circle"
            case "question":       return "questionmark.bubble"
            case "suggested_echo": return "bell.and.waves.left.and.right"
            default:               return insightType.icon
            }
        case .safety:
            switch subtype {
            case "api_key":       return "key"
            case "password":      return "lock.shield"
            case "personal_data": return "person.badge.shield.checkmark"
            default:              return insightType.icon
            }
        default:
            return insightType.icon
        }
    }

    /// Label that reflects the subtype.
    var displayLabel: String {
        guard let subtype = sourceSectionId else { return insightType.label }

        switch insightType {
        case .cleanup:
            switch subtype {
            case "stale":        return "Stale"
            case "dormant_loop": return "Dormant"
            case "lonely_loop":  return "Lonely Loop"
            case "nonsense":     return "Nonsense"
            default:             return insightType.label
            }
        case .reminder:
            switch subtype {
            case "task":           return "Task"
            case "question":       return "Question"
            case "suggested_echo": return "Echo"
            default:               return insightType.label
            }
        case .safety:
            switch subtype {
            case "api_key":       return "API Key"
            case "password":      return "Password"
            case "personal_data": return "Personal Data"
            default:              return insightType.label
            }
        default:
            return insightType.label
        }
    }

    /// Tint that reflects the subtype.
    var displayTint: InsightTint {
        guard let subtype = sourceSectionId else { return insightType.tint }

        switch insightType {
        case .cleanup:
            switch subtype {
            case "nonsense": return .red
            default:         return .gray
            }
        case .reminder:
            switch subtype {
            case "task":     return .green
            case "question": return .yellow
            default:         return .orange
            }
        case .safety:
            return .red
        default:
            return insightType.tint
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
