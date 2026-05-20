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

/// The semantic intent of a section, determining its visual styling and behavior.
/// Raw values intentionally preserve the original names ("idea", "question",
/// "task", "evidence") so existing persisted rows and server payloads keep
/// decoding after the user-facing language changed to Open / Waiting / Active
/// / Issue / Done. The new `issue` case (Red) is a fresh raw value.
enum IntentType: String, Codable, DatabaseValueConvertible, CaseIterable {
    case idea       // Blue   - "Open"
    case question   // Yellow - "Waiting"
    case evidence   // Purple - "Active"
    case issue      // Red    - "Issue"
    case task       // Green  - "Done"

    /// The primary color for this intent type
    var color: Color {
        switch self {
        case .idea:     return .blue
        case .task:     return .green
        case .question: return .yellow
        case .issue:    return .red
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
        case .task:
            return adaptiveColor(
                light: (0.92, 1.0, 0.95),
                dark: (0.10, 0.20, 0.15)
            )
        case .question:
            return adaptiveColor(
                light: (1.0, 0.98, 0.90),
                dark: (0.20, 0.18, 0.10)
            )
        case .issue:
            return adaptiveColor(
                light: (1.0, 0.92, 0.92),
                dark: (0.26, 0.12, 0.12)
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
        case .task:
            return adaptiveColor(
                light: (0.80, 0.94, 0.85),
                dark: (0.14, 0.30, 0.20)
            )
        case .question:
            return adaptiveColor(
                light: (0.96, 0.92, 0.74),
                dark: (0.30, 0.26, 0.14)
            )
        case .issue:
            return adaptiveColor(
                light: (0.96, 0.78, 0.78),
                dark: (0.40, 0.18, 0.18)
            )
        case .evidence:
            return adaptiveColor(
                light: (0.88, 0.84, 0.96),
                dark: (0.26, 0.18, 0.32)
            )
        }
    }

    /// Human-readable label (the status the user sees)
    var label: String {
        switch self {
        case .idea:     return "Open"
        case .question: return "Waiting"
        case .evidence: return "Active"
        case .issue:    return "Issue"
        case .task:     return "Done"
        }
    }

    /// SF Symbol icon for this intent type
    var icon: String {
        switch self {
        case .idea:     return "circle"
        case .question: return "hourglass"
        case .evidence: return "bolt.fill"
        case .issue:    return "exclamationmark.triangle.fill"
        case .task:     return "checkmark.seal.fill"
        }
    }

    /// Color name (used in some pickers/menus where the chip needs a label)
    var displayName: String {
        switch self {
        case .idea:     return "Blue"
        case .task:     return "Green"
        case .question: return "Yellow"
        case .issue:    return "Red"
        case .evidence: return "Purple"
        }
    }

    /// Keyboard shortcut hint
    var shortcutHint: String {
        switch self {
        case .idea:     return "⌘1"
        case .task:     return "⌘2"
        case .question: return "⌘3"
        case .issue:    return "⌘4"
        case .evidence: return "⌘5"
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
    /// Converts legacy ColorIntent values to IntentType.
    /// Accepts the old semantic names (idea/question/task/evidence) AND the new
    /// status names (open/waiting/active/issue/done) so the server can be
    /// renamed independently from this client. Note that "active" now maps to
    /// Purple (evidence) and "done" maps to Green (task) after the latest
    /// label swap — the raw value stays paired with its color.
    static func fromLegacy(_ colorIntent: String?) -> IntentType {
        guard let colorIntent = colorIntent else { return .idea }
        switch colorIntent.lowercased() {
        case "idea", "open", "default":     return .idea
        case "question", "waiting":         return .question
        case "evidence", "active", "reference": return .evidence
        case "issue":                       return .issue
        case "task", "done", "important":   return .task
        default:                            return .idea
        }
    }

    /// Convert to legacy string for server sync (backwards compatibility).
    /// Keeps the original case names so older servers/clients still decode it.
    var legacyValue: String {
        switch self {
        case .idea:     return "idea"
        case .task:     return "task"
        case .question: return "question"
        case .issue:    return "issue"
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
