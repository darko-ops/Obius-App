import SwiftUI

struct CommentRow: View {
    let comment: SharedComment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Author + timestamp
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    // Show email as primary when available, otherwise fall back to display name
                    Text(comment.userEmail ?? comment.userDisplayName ?? "Anonymous")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                }

                Spacer()

                Text(formatDate(comment.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Body
            Text(comment.body)
                .font(.subheadline)
                .textSelection(.enabled)

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.blue.opacity(0.15))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatDate(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = isoFormatter.date(from: dateString)
            ?? ISO8601DateFormatter().date(from: dateString)
            ?? Date()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
