import Foundation
import GRDB
import SwiftUI

/// The semantic intent of a section, determining its visual styling and behavior
enum IntentType: String, Codable, DatabaseValueConvertible, CaseIterable {
    case idea       // Blue - Creative thoughts and brainstorms
    case question   // Yellow - Questions to explore or answer
    case task       // Green - Actionable items
    case evidence   // Purple - Supporting facts, quotes, references
    
    /// The primary color for this intent type
    var color: Color {
        switch self {
        case .idea:     return .blue
        case .question: return .yellow
        case .task:     return .green
        case .evidence: return .purple
        }
    }
    
    /// A lighter background tint for section backgrounds
    var backgroundTint: Color {
        switch self {
        case .idea:     return Color.blue.opacity(0.08)
        case .question: return Color.yellow.opacity(0.08)
        case .task:     return Color.green.opacity(0.08)
        case .evidence: return Color.purple.opacity(0.08)
        }
    }
    
    /// SF Symbol icon for this intent type
    var icon: String {
        switch self {
        case .idea:     return "lightbulb.fill"
        case .question: return "questionmark.circle.fill"
        case .task:     return "checkmark.circle.fill"
        case .evidence: return "quote.bubble.fill"
        }
    }
    
    /// Human-readable display name
    var displayName: String {
        switch self {
        case .idea:     return "Idea"
        case .question: return "Question"
        case .task:     return "Task"
        case .evidence: return "Evidence"
        }
    }
    
    /// Keyboard shortcut hint
    var shortcutHint: String {
        switch self {
        case .idea:     return "⌘1"
        case .question: return "⌘2"
        case .task:     return "⌘3"
        case .evidence: return "⌘4"
        }
    }
}

// MARK: - Legacy Migration Support

extension IntentType {
    /// Converts legacy ColorIntent values to IntentType
    static func fromLegacy(_ colorIntent: String?) -> IntentType {
        guard let colorIntent = colorIntent else { return .idea }
        switch colorIntent.lowercased() {
        case "idea", "default":     return .idea
        case "question":            return .question
        case "important", "task":   return .task
        case "reference", "evidence": return .evidence
        default:                    return .idea
        }
    }
    
    /// Convert to legacy string for server sync (backwards compatibility)
    var legacyValue: String {
        switch self {
        case .idea:     return "idea"
        case .question: return "idea"  // Server doesn't know about question yet
        case .task:     return "task"
        case .evidence: return "reference"
        }
    }
}

// MARK: - SectionType

/// The type of section - fold (structured) or line (plain text)
enum SectionType: String, Codable, DatabaseValueConvertible {
    case fold = "fold"   // Structured section with background and intent
    case line = "line"   // Plain text line without fold styling
}

// MARK: - ContentType (moved here for organization)

enum ContentType: String, Codable, DatabaseValueConvertible {
    case text
    case checklist
    case code
    case quote
}

// MARK: - SyncStatus

enum SyncStatus: String, Codable, DatabaseValueConvertible {
    case pending
    case synced
    case conflict
}
