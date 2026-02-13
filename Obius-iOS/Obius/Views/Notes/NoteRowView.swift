import SwiftUI

struct NoteRowView: View {
    let note: Note
    var sectionContent: String?
    var autoTitle: String?

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M.d.yy"
        return formatter.string(from: note.updatedDate)
    }

    private var contentPreview: String? {
        // Try note body first, then fall back to section content
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = body.isEmpty ? (sectionContent ?? "") : body

        guard !content.isEmpty else { return nil }

        return truncatePreview(content)
    }

    private func truncatePreview(_ text: String) -> String {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 80

        // Find first sentence ending
        if let sentenceEnd = content.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            let sentence = String(content[...sentenceEnd])
            if sentence.count <= maxLength {
                return sentence
            }
        }

        // Truncate to max length
        if content.count <= maxLength {
            return content
        }

        // Find last space before max length for clean break
        let truncated = String(content.prefix(maxLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }

        return truncated + "…"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Intent indicator (using the new IntentType)
            Circle()
                .fill(note.intent.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(autoTitle ?? note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                if let preview = contentPreview {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Only show pin icon for pinned notes that aren't in a group
            if note.isPinned && note.groupName == nil {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        NoteRowView(note: Note(
            title: "Sample Note",
            body: "This is the first sentence. And here is more content that follows.",
            isPinned: true,
            intent: .task
        ))

        NoteRowView(note: Note(
            title: "Another Note",
            body: "A quick idea about something interesting that came to mind while working on the project.",
            intent: .idea
        ))

        NoteRowView(note: Note(
            aiTitle: "AI Generated Title",
            body: "What if we tried a different approach?",
            intent: .question
        ))

        NoteRowView(note: Note(
            title: "Evidence Note",
            intent: .evidence
        ))
    }
}
