import SwiftUI

// MARK: - Action Status

enum ActionStatus: Equatable {
    case pending
    case accepted
    case dismissed
    case failed(String)
}

// MARK: - Suggested Action

struct SuggestedAction: Identifiable {
    let id: String
    let actionType: ActionType
    var status: ActionStatus = .pending

    // MARK: - Action Types

    enum ActionType {
        case scheduleEcho(ScheduleEchoParams)
        case setNoteIntent(SetNoteIntentParams)
        case promoteToHandle(PromoteToHandleParams)
    }

    struct ScheduleEchoParams {
        let handleId: String
        let handleName: String
        let isRecurring: Bool
        let intervalValue: Int
        let intervalUnit: String
        let fireDate: String // ISO-8601
    }

    struct SetNoteIntentParams {
        let noteId: String
        let noteTitle: String
        let intent: String
    }

    struct PromoteToHandleParams {
        let sectionId: String
        let sectionPreview: String
        let handleName: String
    }

    // MARK: - Display Properties

    var icon: String {
        switch actionType {
        case .scheduleEcho:     return "bell.badge"
        case .setNoteIntent:    return "tag"
        case .promoteToHandle:  return "arrow.up.right.circle"
        }
    }

    var title: String {
        switch actionType {
        case .scheduleEcho(let p):
            return "Schedule Echo on @\(p.handleName)"
        case .setNoteIntent(let p):
            let display = p.noteTitle.isEmpty ? "Untitled" : p.noteTitle
            return "Set \(display) intent to \(p.intent)"
        case .promoteToHandle(let p):
            return "Promote to @\(p.handleName)"
        }
    }

    var description: String {
        switch actionType {
        case .scheduleEcho(let p):
            let recurring = p.isRecurring ? "Recurring every \(p.intervalValue) \(p.intervalUnit)" : "One-time"
            let dateStr = Self.formatFireDate(p.fireDate)
            return "\(recurring), starting \(dateStr)"
        case .setNoteIntent(let p):
            return "Change intent to \(p.intent)"
        case .promoteToHandle(let p):
            let preview = p.sectionPreview.prefix(60)
            return "Create handle from: \(preview)"
        }
    }

    var toolName: String {
        switch actionType {
        case .scheduleEcho:     return "schedule_echo"
        case .setNoteIntent:    return "set_note_intent"
        case .promoteToHandle:  return "promote_to_handle"
        }
    }

    var tintColor: Color {
        switch actionType {
        case .scheduleEcho:     return .orange
        case .setNoteIntent:    return .blue
        case .promoteToHandle:  return .purple
        }
    }

    // MARK: - Factory

    static func from(toolUseBlock: [String: Any]) -> SuggestedAction? {
        guard let id = toolUseBlock["id"] as? String,
              let name = toolUseBlock["name"] as? String,
              let input = toolUseBlock["input"] as? [String: Any] else {
            return nil
        }

        let actionType: ActionType?

        switch name {
        case "schedule_echo":
            guard let handleId = input["handle_id"] as? String,
                  let handleName = input["handle_name"] as? String,
                  let isRecurring = input["is_recurring"] as? Bool,
                  let intervalValue = input["interval_value"] as? Int,
                  let intervalUnit = input["interval_unit"] as? String,
                  let fireDate = input["fire_date"] as? String else {
                return nil
            }
            actionType = .scheduleEcho(ScheduleEchoParams(
                handleId: handleId,
                handleName: handleName,
                isRecurring: isRecurring,
                intervalValue: intervalValue,
                intervalUnit: intervalUnit,
                fireDate: fireDate
            ))

        case "set_note_intent":
            guard let noteId = input["note_id"] as? String,
                  let noteTitle = input["note_title"] as? String,
                  let intent = input["intent"] as? String else {
                return nil
            }
            actionType = .setNoteIntent(SetNoteIntentParams(
                noteId: noteId,
                noteTitle: noteTitle,
                intent: intent
            ))

        case "promote_to_handle":
            guard let sectionId = input["section_id"] as? String,
                  let sectionPreview = input["section_preview"] as? String,
                  let handleName = input["handle_name"] as? String else {
                return nil
            }
            actionType = .promoteToHandle(PromoteToHandleParams(
                sectionId: sectionId,
                sectionPreview: sectionPreview,
                handleName: handleName
            ))

        default:
            return nil
        }

        guard let type = actionType else { return nil }
        return SuggestedAction(id: id, actionType: type)
    }

    // MARK: - Execute

    @MainActor
    func execute(appState: AppState) async throws {
        switch actionType {
        case .scheduleEcho(let p):
            guard let date = ISO8601DateFormatter().date(from: p.fireDate) else {
                throw ActionError.invalidParameters("Invalid fire date format")
            }
            let unit: EchoIntervalUnit
            switch p.intervalUnit.lowercased() {
            case "minutes": unit = .minutes
            case "hours":   unit = .hours
            case "days":    unit = .days
            case "weeks":   unit = .weeks
            case "months":  unit = .months
            default:        unit = .days
            }
            let intervals = p.isRecurring
                ? [EchoInterval(id: UUID().uuidString, value: p.intervalValue, unit: unit)]
                : []
            _ = try await EchoManager.shared.createEcho(
                handleId: p.handleId,
                isRecurring: p.isRecurring,
                intervals: intervals,
                fireDate: date
            )

        case .setNoteIntent(let p):
            guard let intent = IntentType(rawValue: p.intent.lowercased()) else {
                throw ActionError.invalidParameters("Unknown intent: \(p.intent)")
            }
            try await appState.noteRepository.setIntent(p.noteId, intent: intent)

        case .promoteToHandle(let p):
            _ = try await appState.sectionRepository.promoteToHandle(
                sectionId: p.sectionId,
                handleName: p.handleName,
                handleRepository: appState.handleRepository
            )
        }
    }

    // MARK: - Status Update

    func withStatus(_ newStatus: ActionStatus) -> SuggestedAction {
        var copy = self
        copy.status = newStatus
        return copy
    }

    // MARK: - Helpers

    private static func formatFireDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.dateFormat = "MMM d"
        return display.string(from: date)
    }

    enum ActionError: LocalizedError {
        case invalidParameters(String)

        var errorDescription: String? {
            switch self {
            case .invalidParameters(let detail): return detail
            }
        }
    }
}
