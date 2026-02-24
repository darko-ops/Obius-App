import SwiftUI

struct NoteRowView: View {
    let note: Note
    var sectionContent: String?
    var autoTitle: String?

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: note.updatedDate, relativeTo: Date())
    }

    private var contentPreview: String? {
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = body.isEmpty ? (sectionContent ?? "") : body

        guard !content.isEmpty else { return nil }

        return truncatePreview(content)
    }

    private func truncatePreview(_ text: String) -> String {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 80

        if let sentenceEnd = content.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            let sentence = String(content[...sentenceEnd])
            if sentence.count <= maxLength {
                return sentence
            }
        }

        if content.count <= maxLength {
            return content
        }

        let truncated = String(content.prefix(maxLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }

        return truncated + "…"
    }

    /// Tags to display: user tags first, falling back to aiTags
    private var displayTags: [String] {
        if !note.tags.isEmpty {
            return Array(note.tags.prefix(2))
        } else if !note.aiTags.isEmpty {
            return Array(note.aiTags.prefix(1))
        }
        return []
    }

    private var isAiTagFallback: Bool {
        note.tags.isEmpty && !note.aiTags.isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            // Spine: 4px wide rounded rect, intent-colored
            RoundedRectangle(cornerRadius: 2)
                .fill(note.intent.color)
                .frame(width: 4)

            // Content area
            VStack(alignment: .leading, spacing: 3) {
                // Row 1: Title + pin + tags + time
                HStack(spacing: 6) {
                    Text(autoTitle ?? note.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if note.isPinned && note.groupName == nil {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    ForEach(displayTags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10))
                            .foregroundStyle(isAiTagFallback ? note.intent.color.opacity(0.6) : note.intent.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(note.intent.color.opacity(isAiTagFallback ? 0.06 : 0.12))
                            .clipShape(Capsule())
                    }

                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Row 2: Content preview
                if let preview = contentPreview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 10)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    List {
        NoteRowView(note: Note(
            title: "Sample Note",
            body: "This is the first sentence. And here is more content that follows.",
            isPinned: true,
            intent: .task,
            tags: ["work", "urgent"]
        ))

        NoteRowView(note: Note(
            title: "Another Note",
            body: "A quick idea about something interesting that came to mind while working on the project.",
            intent: .idea,
            tags: ["ui"]
        ))

        NoteRowView(note: Note(
            aiTitle: "AI Generated Title",
            body: "What if we tried a different approach?",
            intent: .question,
            aiTags: ["brainstorm"]
        ))

        NoteRowView(note: Note(
            title: "Evidence Note",
            intent: .evidence
        ))
    }
}
