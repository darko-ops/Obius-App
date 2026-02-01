import SwiftUI

struct NoteRowView: View {
    let note: Note

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M.d.yy"
        return formatter.string(from: note.updatedDate)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Intent indicator (using the new IntentType)
            Circle()
                .fill(note.intent.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if note.syncStatus == .pending {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if note.isPinned {
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
            isPinned: true,
            intent: .task
        ))

        NoteRowView(note: Note(
            title: "Another Note",
            intent: .idea
        ))

        NoteRowView(note: Note(
            aiTitle: "AI Generated Title",
            intent: .question
        ))
        
        NoteRowView(note: Note(
            title: "Evidence Note",
            intent: .evidence
        ))
    }
}
