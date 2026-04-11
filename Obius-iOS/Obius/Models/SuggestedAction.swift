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
        case updateLoopContent(UpdateLoopContentParams)
        case updatePageBody(UpdatePageBodyParams)
        case deleteSection(DeleteSectionParams)
        case updateSectionContent(UpdateSectionContentParams)
        case addSection(AddSectionParams)
        case moveSection(MoveSectionParams)
        case setSectionIntent(SetSectionIntentParams)
        case rewritePage(RewritePageParams)
        case updateInterstitialContent(UpdateInterstitialContentParams)
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

    struct UpdateLoopContentParams {
        let handleId: String
        let handleName: String
        let newContent: String
    }

    struct UpdatePageBodyParams {
        let noteId: String
        let noteTitle: String
        let newBody: String
    }

    struct DeleteSectionParams {
        let sectionId: String
        let sectionPreview: String
    }

    struct UpdateSectionContentParams {
        let sectionId: String
        let sectionPreview: String
        let newContent: String
    }

    struct AddSectionParams {
        let noteId: String
        let noteTitle: String
        let content: String
        let sectionType: String    // "fold" or "line"
        let contentType: String?   // "text", "checklist", "code", "quote"
        let afterSectionId: String?
        let intent: String?
    }

    struct MoveSectionParams {
        let sectionId: String
        let sectionPreview: String
        let afterSectionId: String?
    }

    struct SetSectionIntentParams {
        let sectionId: String
        let sectionPreview: String
        let intent: String
    }

    struct RewritePageParams {
        let noteId: String
        let noteTitle: String
        let newBody: String
        let keepSections: [KeepSection]
        let interstitialContent: [String: String]
        let summary: String
        /// Pre-built preview showing what the page will look like after the edit.
        let pagePreview: String
    }

    struct KeepSection {
        let sectionId: String
        let newContent: String? // nil = keep existing content
    }

    struct UpdateInterstitialContentParams {
        let noteId: String
        let noteTitle: String
        let afterSectionId: String? // nil = text after all sections ("end")
        let newContent: String
    }

    // MARK: - Display Properties

    var icon: String {
        switch actionType {
        case .scheduleEcho:         return "bell.badge"
        case .setNoteIntent:        return "tag"
        case .promoteToHandle:      return "arrow.up.right.circle"
        case .updateLoopContent:    return "pencil.and.outline"
        case .updatePageBody:       return "doc.text"
        case .deleteSection:        return "trash"
        case .updateSectionContent: return "pencil.line"
        case .addSection:           return "plus.rectangle"
        case .moveSection:          return "arrow.up.arrow.down"
        case .setSectionIntent:     return "paintbrush"
        case .rewritePage:          return "doc.text.fill"
        case .updateInterstitialContent: return "text.insert"
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
        case .updateLoopContent(let p):
            return "Update @\(p.handleName)"
        case .updatePageBody(let p):
            let display = p.noteTitle.isEmpty ? "Untitled" : p.noteTitle
            return "Update \(display)"
        case .deleteSection(let p):
            return "Delete: \(p.sectionPreview.prefix(40))"
        case .updateSectionContent(let p):
            return "Edit: \(p.sectionPreview.prefix(40))"
        case .addSection(let p):
            let type = p.sectionType == "fold" ? "node" : "line"
            return "Create \(type) on \(p.noteTitle.isEmpty ? "Untitled" : p.noteTitle)"
        case .moveSection(let p):
            return "Move: \(p.sectionPreview.prefix(40))"
        case .setSectionIntent(let p):
            return "Set intent to \(p.intent)"
        case .rewritePage(let p):
            let display = p.noteTitle.isEmpty ? "Untitled" : p.noteTitle
            return "Rewrite \(display)"
        case .updateInterstitialContent(let p):
            let display = p.noteTitle.isEmpty ? "Untitled" : p.noteTitle
            let location = p.afterSectionId != nil ? "after node" : "at end of page"
            return "Update text \(location) on \(display)"
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
            return "Create loop from: \(p.sectionPreview.prefix(60))"
        case .updateLoopContent(let p):
            return String(p.newContent.prefix(80))
        case .updatePageBody(let p):
            return String(p.newBody.prefix(80))
        case .deleteSection(let p):
            return "Remove: \(p.sectionPreview.prefix(60))"
        case .updateSectionContent(let p):
            return String(p.newContent.prefix(80))
        case .addSection(let p):
            let type = p.sectionType == "fold" ? "node" : "line"
            return "Add \(type): \(p.content.prefix(60))"
        case .moveSection(let p):
            return "Reorder: \(p.sectionPreview.prefix(60))"
        case .setSectionIntent(let p):
            return "Change \(p.sectionPreview.prefix(30)) to \(p.intent)"
        case .rewritePage(let p):
            let display = p.noteTitle.isEmpty ? "Untitled" : p.noteTitle
            return "Rewrite \(display)"
        case .updateInterstitialContent(let p):
            return String(p.newContent.prefix(80))
        }
    }

    /// Full proposed content for content-update actions, nil for others.
    var fullContent: String? {
        switch actionType {
        case .updateLoopContent(let p):    return p.newContent
        case .updatePageBody(let p):       return p.newBody
        case .updateSectionContent(let p): return p.newContent
        case .addSection(let p):           return p.content
        case .rewritePage(let p):          return p.pagePreview
        case .updateInterstitialContent(let p): return p.newContent
        default:                           return nil
        }
    }

    var toolName: String {
        switch actionType {
        case .scheduleEcho:         return "schedule_echo"
        case .setNoteIntent:        return "set_note_intent"
        case .promoteToHandle:      return "promote_to_handle"
        case .updateLoopContent:    return "update_loop_content"
        case .updatePageBody:       return "update_page_body"
        case .deleteSection:        return "delete_section"
        case .updateSectionContent: return "update_section_content"
        case .addSection:           return "create_node"
        case .moveSection:          return "move_section"
        case .setSectionIntent:     return "set_section_intent"
        case .rewritePage:          return "rewrite_page"
        case .updateInterstitialContent: return "update_interstitial_content"
        }
    }

    var tintColor: Color {
        switch actionType {
        case .scheduleEcho:         return .orange
        case .setNoteIntent:        return .blue
        case .promoteToHandle:      return .purple
        case .updateLoopContent:    return .green
        case .updatePageBody:       return .cyan
        case .deleteSection:        return .red
        case .updateSectionContent: return .green
        case .addSection:           return .mint
        case .moveSection:          return .indigo
        case .setSectionIntent:     return .blue
        case .rewritePage:          return .cyan
        case .updateInterstitialContent: return .cyan
        }
    }

    // MARK: - Factory

    static func from(toolUseBlock: [String: Any]) -> SuggestedAction? {
        guard let id = toolUseBlock["id"] as? String,
              let name = toolUseBlock["name"] as? String else {
            print("[SuggestedAction] Missing id or name in tool_use block: \(Array(toolUseBlock.keys))")
            return nil
        }
        // input might be an empty dict {} or might be missing — default to empty
        let input = (toolUseBlock["input"] as? [String: Any]) ?? [:]

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

        case "update_loop_content":
            guard let handleId = input["handle_id"] as? String,
                  let handleName = input["handle_name"] as? String,
                  let newContent = input["new_content"] as? String else {
                return nil
            }
            actionType = .updateLoopContent(UpdateLoopContentParams(
                handleId: handleId,
                handleName: handleName,
                newContent: newContent
            ))

        case "update_page_body":
            guard let noteId = input["note_id"] as? String,
                  let noteTitle = input["note_title"] as? String,
                  let newBody = input["new_body"] as? String else {
                return nil
            }
            actionType = .updatePageBody(UpdatePageBodyParams(
                noteId: noteId,
                noteTitle: noteTitle,
                newBody: newBody
            ))

        case "delete_section":
            guard let sectionId = input["section_id"] as? String,
                  let sectionPreview = input["section_preview"] as? String else {
                return nil
            }
            actionType = .deleteSection(DeleteSectionParams(
                sectionId: sectionId,
                sectionPreview: sectionPreview
            ))

        case "update_section_content":
            guard let sectionId = input["section_id"] as? String,
                  let sectionPreview = input["section_preview"] as? String,
                  let newContent = input["new_content"] as? String else {
                return nil
            }
            actionType = .updateSectionContent(UpdateSectionContentParams(
                sectionId: sectionId,
                sectionPreview: sectionPreview,
                newContent: newContent
            ))

        case "create_section", "add_section", "create_node":
            // note_id and content are required; section_type defaults to "fold" (node)
            guard let noteId = input["note_id"] as? String,
                  let content = input["content"] as? String else {
                print("[SuggestedAction] create_section parse failed — note_id: \(input["note_id"] ?? "nil"), content: \(input["content"] != nil ? "present" : "nil"), allKeys: \(Array(input.keys))")
                return nil
            }
            let sectionType = (input["section_type"] as? String) ?? "fold"
            actionType = .addSection(AddSectionParams(
                noteId: noteId,
                noteTitle: (input["note_title"] as? String) ?? "",
                content: content,
                sectionType: sectionType,
                contentType: input["content_type"] as? String,
                afterSectionId: input["after_section_id"] as? String,
                intent: input["intent"] as? String
            ))

        case "move_section":
            guard let sectionId = input["section_id"] as? String,
                  let sectionPreview = input["section_preview"] as? String else {
                return nil
            }
            actionType = .moveSection(MoveSectionParams(
                sectionId: sectionId,
                sectionPreview: sectionPreview,
                afterSectionId: input["after_section_id"] as? String
            ))

        case "set_section_intent":
            guard let sectionId = input["section_id"] as? String,
                  let sectionPreview = input["section_preview"] as? String,
                  let intent = input["intent"] as? String else {
                return nil
            }
            actionType = .setSectionIntent(SetSectionIntentParams(
                sectionId: sectionId,
                sectionPreview: sectionPreview,
                intent: intent
            ))

        case "update_interstitial_content":
            guard let noteId = input["note_id"] as? String,
                  let noteTitle = input["note_title"] as? String,
                  let newContent = input["new_content"] as? String else {
                return nil
            }
            actionType = .updateInterstitialContent(UpdateInterstitialContentParams(
                noteId: noteId,
                noteTitle: noteTitle,
                afterSectionId: input["after_section_id"] as? String,
                newContent: newContent
            ))

        case "rewrite_page":
            guard let noteId = input["note_id"] as? String,
                  let noteTitle = input["note_title"] as? String,
                  let newBody = input["new_body"] as? String,
                  let keepSectionsRaw = input["keep_sections"] as? [[String: Any]],
                  let summary = input["summary"] as? String else {
                return nil
            }
            let keepSections = keepSectionsRaw.compactMap { dict -> KeepSection? in
                guard let sId = dict["section_id"] as? String else { return nil }
                return KeepSection(sectionId: sId, newContent: dict["new_content"] as? String)
            }
            let interstitials = (input["interstitial_content"] as? [String: String]) ?? [:]
            // Build preview from body + any sections that have new_content
            var previewParts: [String] = []
            let trimmedBody = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBody.isEmpty { previewParts.append(trimmedBody) }
            for ks in keepSections {
                if let content = ks.newContent?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !content.isEmpty {
                    previewParts.append("• \(content)")
                }
                // Show interstitial text after this section in preview
                if let inter = interstitials["after_\(ks.sectionId)"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !inter.isEmpty {
                    previewParts.append(inter)
                }
            }
            if let endText = interstitials["end"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !endText.isEmpty {
                previewParts.append(endText)
            }
            let preview = previewParts.isEmpty ? summary : previewParts.joined(separator: "\n\n")
            actionType = .rewritePage(RewritePageParams(
                noteId: noteId,
                noteTitle: noteTitle,
                newBody: newBody,
                keepSections: keepSections,
                interstitialContent: interstitials,
                summary: summary,
                pagePreview: preview
            ))

        default:
            return nil
        }

        guard let type = actionType else {
            print("[SuggestedAction] actionType was nil for tool '\(name)' — input keys: \(Array(input.keys)), values: \(input)")
            return nil
        }
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

        case .updateLoopContent(let p):
            try await HandleManager.shared.updateContent(handleId: p.handleId, content: p.newContent)

        case .updatePageBody(let p):
            let hasMarkdown = p.newBody.contains("# ") || p.newBody.contains("**") || p.newBody.contains("*")
            let richText: String?
            if hasMarkdown {
                let attributed = RichTextHelper.fromMarkdown(p.newBody)
                richText = RichTextHelper.serialize(attributed)
            } else {
                richText = nil
            }
            let plainBody = Section.stripMarkdown(p.newBody)
            try await appState.noteRepository.updateNoteBody(p.noteId, body: plainBody, richText: richText, clearRichText: richText == nil)

        case .deleteSection(let p):
            try await appState.sectionRepository.deleteSection(p.sectionId)

        case .updateSectionContent(let p):
            let hasMarkdown = p.newContent.contains("# ") || p.newContent.contains("**") || p.newContent.contains("*")
            let richText: String?
            if hasMarkdown {
                let attributed = RichTextHelper.fromMarkdown(p.newContent)
                richText = RichTextHelper.serialize(attributed)
            } else {
                richText = nil
            }
            let plainContent = Section.stripMarkdown(p.newContent)
            try await appState.sectionRepository.updateContent(p.sectionId, content: plainContent, richText: richText, clearRichText: richText == nil)

        case .addSection(let p):
            let secType: SectionType = p.sectionType == "fold" ? .fold : .line
            let conType: ContentType
            switch p.contentType?.lowercased() {
            case "checklist": conType = .checklist
            case "code":      conType = .code
            case "quote":     conType = .quote
            default:          conType = .text
            }
            let hasMarkdown = p.content.contains("# ") || p.content.contains("**") || p.content.contains("*")
            let plainContent = Section.stripMarkdown(p.content)
            let section = try await appState.sectionRepository.createSection(
                noteId: p.noteId,
                content: plainContent,
                contentType: conType,
                sectionType: secType,
                afterSectionId: p.afterSectionId
            )
            if hasMarkdown {
                let attributed = RichTextHelper.fromMarkdown(p.content)
                let richText = RichTextHelper.serialize(attributed)
                try await appState.sectionRepository.updateContent(section.id, content: plainContent, richText: richText)
            }
            if let intentStr = p.intent, let intent = IntentType(rawValue: intentStr.lowercased()) {
                try await appState.sectionRepository.setIntent(section.id, intent: intent)
            }

        case .moveSection(let p):
            try await appState.sectionRepository.moveSection(p.sectionId, after: p.afterSectionId)

        case .setSectionIntent(let p):
            guard let intent = IntentType(rawValue: p.intent.lowercased()) else {
                throw ActionError.invalidParameters("Unknown intent: \(p.intent)")
            }
            try await appState.sectionRepository.setIntent(p.sectionId, intent: intent)

        case .updateInterstitialContent(let p):
            let hasMarkdown = p.newContent.contains("# ") || p.newContent.contains("**") || p.newContent.contains("*")
            let richText: String?
            if hasMarkdown {
                let attributed = RichTextHelper.fromMarkdown(p.newContent)
                richText = RichTextHelper.serialize(attributed)
            } else {
                richText = nil
            }
            let plainContent = Section.stripMarkdown(p.newContent)
            try await appState.noteRepository.updateInterstitialContent(
                p.noteId,
                afterSectionId: p.afterSectionId,
                content: plainContent,
                richText: richText
            )

        case .rewritePage(let p):
            // 1. Update body
            let hasMarkdown = p.newBody.contains("# ") || p.newBody.contains("**") || p.newBody.contains("*")
            let richText: String?
            if hasMarkdown {
                let attributed = RichTextHelper.fromMarkdown(p.newBody)
                richText = RichTextHelper.serialize(attributed)
            } else {
                richText = nil
            }
            let plainBody = Section.stripMarkdown(p.newBody)
            try await appState.noteRepository.updateNoteBody(p.noteId, body: plainBody, richText: richText, clearRichText: richText == nil)

            // 2. Build set of section IDs to keep
            let keepIds = Set(p.keepSections.map(\.sectionId))

            // 3. Get all current sections for this note and delete ones not in keepIds
            let allSections = try await appState.sectionRepository.getSections(noteId: p.noteId)
            for section in allSections {
                guard section.deletedAt == nil else { continue }
                if !keepIds.contains(section.id) {
                    try await appState.sectionRepository.deleteSection(section.id)
                }
            }

            // 4. Update content for kept sections that have new_content
            for keep in p.keepSections {
                guard let newContent = keep.newContent else { continue }
                let hasMd = newContent.contains("# ") || newContent.contains("**") || newContent.contains("*")
                let rt: String?
                if hasMd {
                    let attr = RichTextHelper.fromMarkdown(newContent)
                    rt = RichTextHelper.serialize(attr)
                } else {
                    rt = nil
                }
                let plain = Section.stripMarkdown(newContent)
                try await appState.sectionRepository.updateContent(keep.sectionId, content: plain, richText: rt, clearRichText: rt == nil)
            }

            // 5. Write interstitial content (text between/after sections)
            for (key, value) in p.interstitialContent {
                let afterId: String?
                if key == "end" {
                    afterId = nil
                } else if key.hasPrefix("after_") {
                    afterId = String(key.dropFirst(6))
                } else {
                    continue
                }
                let hasMd = value.contains("# ") || value.contains("**") || value.contains("*")
                let rt: String?
                if hasMd {
                    let attr = RichTextHelper.fromMarkdown(value)
                    rt = RichTextHelper.serialize(attr)
                } else {
                    rt = nil
                }
                let plain = Section.stripMarkdown(value)
                try await appState.noteRepository.updateInterstitialContent(
                    p.noteId, afterSectionId: afterId, content: plain, richText: rt
                )
            }
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
