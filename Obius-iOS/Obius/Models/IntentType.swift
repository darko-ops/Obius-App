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
    
    /// A lighter background tint for section backgrounds (opaque, adapts to light/dark mode)
    var backgroundTint: Color {
        switch self {
        case .idea:
            return Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.10, green: 0.15, blue: 0.25, alpha: 1.0)  // Dark blue-gray
                    : UIColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1.0)   // Light blue
            })
        case .question:
            return Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.20, green: 0.18, blue: 0.10, alpha: 1.0)  // Dark yellow-brown
                    : UIColor(red: 1.0, green: 0.98, blue: 0.90, alpha: 1.0)   // Light yellow
            })
        case .task:
            return Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.10, green: 0.20, blue: 0.15, alpha: 1.0)  // Dark green
                    : UIColor(red: 0.92, green: 1.0, blue: 0.95, alpha: 1.0)   // Light green
            })
        case .evidence:
            return Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.18, green: 0.12, blue: 0.22, alpha: 1.0)  // Dark purple
                    : UIColor(red: 0.96, green: 0.94, blue: 1.0, alpha: 1.0)   // Light purple
            })
        }
    }
    
    /// A darker tint for the collapse lip tab on the right edge of nodes
    var lipTint: Color {
        switch self {
        case .idea:
            return Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.14, green: 0.22, blue: 0.38, alpha: 1.0)
                    : UIColor(red: 0.78, green: 0.85, blue: 0.98, alpha: 1.0)
            })
        case .question:
            return Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.30, green: 0.26, blue: 0.14, alpha: 1.0)
                    : UIColor(red: 0.96, green: 0.92, blue: 0.74, alpha: 1.0)
            })
        case .task:
            return Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.14, green: 0.30, blue: 0.20, alpha: 1.0)
                    : UIColor(red: 0.80, green: 0.94, blue: 0.85, alpha: 1.0)
            })
        case .evidence:
            return Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.26, green: 0.18, blue: 0.32, alpha: 1.0)
                    : UIColor(red: 0.88, green: 0.84, blue: 0.96, alpha: 1.0)
            })
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
        case .idea:     return "Blue"
        case .question: return "Yellow"
        case .task:     return "Green"
        case .evidence: return "Purple"
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

// MARK: - Color Extensions

extension Color {
    /// Opaque focused background color that adapts to light/dark mode
    static var focusedBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.15, green: 0.20, blue: 0.30, alpha: 1.0)  // Dark accent blue
                : UIColor(red: 0.90, green: 0.94, blue: 1.0, alpha: 1.0)   // Light accent blue
        })
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
    case image
    case audio
}

// MARK: - SyncStatus

enum SyncStatus: String, Codable, DatabaseValueConvertible {
    case pending
    case synced
    case conflict
}
