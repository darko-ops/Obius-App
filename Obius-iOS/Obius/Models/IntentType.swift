import Foundation
import GRDB
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Helper to create adaptive colors that work on both iOS and macOS
private func adaptiveColor(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
    #if os(iOS)
    return Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1.0)
            : UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1.0)
    })
    #else
    return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1.0)
            : NSColor(red: light.0, green: light.1, blue: light.2, alpha: 1.0)
    }))
    #endif
}

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
            return adaptiveColor(
                light: (0.92, 0.95, 1.0),
                dark: (0.10, 0.15, 0.25)
            )
        case .question:
            return adaptiveColor(
                light: (1.0, 0.98, 0.90),
                dark: (0.20, 0.18, 0.10)
            )
        case .task:
            return adaptiveColor(
                light: (0.92, 1.0, 0.95),
                dark: (0.10, 0.20, 0.15)
            )
        case .evidence:
            return adaptiveColor(
                light: (0.96, 0.94, 1.0),
                dark: (0.18, 0.12, 0.22)
            )
        }
    }

    /// A darker tint for the collapse lip tab on the right edge of nodes
    var lipTint: Color {
        switch self {
        case .idea:
            return adaptiveColor(
                light: (0.78, 0.85, 0.98),
                dark: (0.14, 0.22, 0.38)
            )
        case .question:
            return adaptiveColor(
                light: (0.96, 0.92, 0.74),
                dark: (0.30, 0.26, 0.14)
            )
        case .task:
            return adaptiveColor(
                light: (0.80, 0.94, 0.85),
                dark: (0.14, 0.30, 0.20)
            )
        case .evidence:
            return adaptiveColor(
                light: (0.88, 0.84, 0.96),
                dark: (0.26, 0.18, 0.32)
            )
        }
    }

    /// Human-readable label
    var label: String {
        switch self {
        case .idea:     return "Idea"
        case .question: return "Question"
        case .task:     return "Task"
        case .evidence: return "Evidence"
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
        adaptiveColor(
            light: (0.90, 0.94, 1.0),
            dark: (0.15, 0.20, 0.30)
        )
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
        case .question: return "question"
        case .task:     return "task"
        case .evidence: return "evidence"
        }
    }
}

// MARK: - SectionType

/// The type of section - fold (structured) or line (plain text)
enum SectionType: String, Codable, DatabaseValueConvertible {
    case fold = "fold"   // Structured section with background and intent
    case line = "line"   // Plain text line without fold styling
}

// MARK: - ContentType

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
