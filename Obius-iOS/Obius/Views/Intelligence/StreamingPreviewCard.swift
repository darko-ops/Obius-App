import SwiftUI

/// Non-interactive "template page being built" card shown below the rotating
/// loading words while the AI is streaming. Mirrors ActionCardView styling so
/// the transition to the real accept/dismiss card feels seamless. The
/// underlying content is whatever has streamed in so far — partial text from
/// Claude plus any in-flight tool_use input JSON.
struct StreamingPreviewCard: View {
    /// Free-text Claude has emitted so far (may be empty if the AI jumped
    /// straight to a tool call).
    let partialText: String
    /// The currently-building tool's name (e.g. "rewrite_page") if any.
    let currentToolName: String?
    /// Raw accumulated input JSON for the building tool (used to pull
    /// progressive text values out via ClaudeService.extractStreamingText).
    let currentToolPartialJSON: String
    /// Actions that have already completed mid-stream — shown as locked
    /// previews so users see them snap into place.
    let completedActions: [SuggestedAction]
    /// Sections for the focused page (passed through to ActionCardView when
    /// rendering completed rewrite/update previews).
    var previewSections: [Section] = []
    var mediaRepository: MediaRepository? = nil

    @State private var pulseOn: Bool = false

    private var streamingValue: String? {
        guard let name = currentToolName else { return nil }
        return ClaudeService.extractStreamingText(
            partialJSON: currentToolPartialJSON,
            toolName: name
        )
    }

    private var prettyToolLabel: String {
        guard let name = currentToolName else { return "Building" }
        return name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var toolIcon: String {
        switch currentToolName {
        case "rewrite_page", "update_page_body": return "doc.text.fill"
        case "update_section_content":           return "pencil.line"
        case "update_loop_content":              return "pencil.and.outline"
        case "create_section", "add_section", "create_node": return "plus.rectangle"
        case "update_interstitial_content":      return "text.insert"
        case "delete_section":                   return "trash"
        case "move_section":                     return "arrow.up.arrow.down"
        case "set_section_intent":               return "paintbrush"
        case "set_note_intent":                  return "tag"
        case "promote_to_handle":                return "arrow.up.right.circle"
        case "schedule_echo":                    return "bell.badge"
        default:                                 return "sparkles"
        }
    }

    private var toolTint: Color {
        switch currentToolName {
        case "rewrite_page", "update_page_body", "update_interstitial_content": return .cyan
        case "update_section_content", "update_loop_content": return .green
        case "create_section", "add_section", "create_node": return .mint
        case "delete_section":                  return .red
        case "move_section":                    return .indigo
        case "set_section_intent", "set_note_intent": return .blue
        case "promote_to_handle":               return .purple
        case "schedule_echo":                   return .orange
        default:                                return .cyan
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Already-completed action cards stack first.
            ForEach(completedActions) { action in
                ActionCardView(
                    action: action.withStatus(.pending),
                    onAccept: {},
                    onDismiss: {},
                    previewSections: previewSections,
                    mediaRepository: mediaRepository
                )
                .disabled(true)
                .opacity(0.85)
            }

            // The currently-building draft.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: toolIcon)
                            .font(.caption2)
                        Text(prettyToolLabel)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(toolTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(toolTint.opacity(0.15))
                    .clipShape(Capsule())

                    Circle()
                        .fill(toolTint)
                        .frame(width: 6, height: 6)
                        .opacity(pulseOn ? 1.0 : 0.25)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulseOn)

                    Text("Building…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                if !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(partialText)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let streamingValue, !streamingValue.isEmpty {
                    Text(streamingValue)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(toolTint.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .onAppear { pulseOn = true }
    }
}
