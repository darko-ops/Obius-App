import SwiftUI

struct CommitPickerForShare: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    let noteId: String
    let onSelect: (Commit) -> Void

    @State private var commits: [Commit] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if commits.isEmpty {
                    ContentUnavailableView(
                        "No Versions",
                        systemImage: "doc.zipper",
                        description: Text("Save a version first to create a permanent shareable link.")
                    )
                } else {
                    List(commits) { commit in
                        Button {
                            onSelect(commit)
                            dismiss()
                        } label: {
                            commitRow(commit)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Pick a Version")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadCommits() }
        }
    }

    @ViewBuilder
    private func commitRow(_ commit: Commit) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let name = commit.name, !name.isEmpty {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                }

                Text(commit.shortId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Text(formatDate(commit.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func loadCommits() async {
        do {
            commits = try await appState.commitRepository.getCommits(noteId: noteId)
        } catch {
            print("CommitPickerForShare: Error loading commits: \(error)")
        }
        isLoading = false
    }

    private func formatDate(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
