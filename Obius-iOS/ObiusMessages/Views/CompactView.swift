import SwiftUI
import Messages

/// Compact view shown in the iMessage app drawer — "The Searcher".
/// Provides search across handles, commits, and notes from the local database.
struct CompactView: View {
    @StateObject private var viewModel = CompactSearchViewModel()

    /// Callback to insert an MSMessage into the active conversation
    var onSendMessage: ((MSMessage) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isDatabaseAvailable {
                searchContent
            } else {
                fallbackView
            }
        }
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Search Content

    @ViewBuilder
    private var searchContent: some View {
        // Search bar
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            TextField("Search notes, handles, commits...", text: $viewModel.query)
                .font(.system(size: 15))
                .autocorrectionDisabled()

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 8)

        // Error banner
        if let error = viewModel.error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.top, 4)
        }

        // Results or recent notes
        ScrollView {
            LazyVStack(spacing: 2) {
                if viewModel.query.isEmpty {
                    // Show recent notes
                    if !viewModel.recentNotes.isEmpty {
                        Text("Recent")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        ForEach(viewModel.recentNotes) { note in
                            noteRow(note)
                        }
                    }
                } else if viewModel.results.isEmpty {
                    Text("No results")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                } else {
                    ForEach(viewModel.results) { result in
                        resultRow(result)
                    }
                }
            }
            .padding(.top, 4)
        }

        // Loading overlay
        if viewModel.isCreatingShare {
            HStack(spacing: 8) {
                ProgressView()
                Text("Creating share...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Result Rows

    @ViewBuilder
    private func resultRow(_ result: SearchResult) -> some View {
        Button {
            Task {
                if let message = await viewModel.createShareAndBuildMessage(for: result) {
                    onSendMessage?(message)
                }
            }
        } label: {
            switch result {
            case .handle(let handle):
                handleRow(handle)
            case .commit(let commit):
                commitRow(commit)
            case .note(let note):
                noteRow(note)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func handleRow(_ handle: Handle) -> some View {
        HStack(spacing: 10) {
            // Intent-colored circle
            Circle()
                .fill(uiColorForIntent(handle.intent.rawValue).opacity(0.3))
                .frame(width: 28, height: 28)
                .overlay(
                    Text("@")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(uiColorForIntent(handle.intent.rawValue))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("@\(handle.displayName)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !handle.content.isEmpty {
                    Text(handle.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "paperplane.fill")
                .font(.system(size: 12))
                .foregroundStyle(.blue.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func commitRow(_ commit: Commit) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.purple.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "number")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.purple)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(commit.name ?? "Snapshot")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("#\(commit.shortId)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "paperplane.fill")
                .font(.system(size: 12))
                .foregroundStyle(.blue.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        Button {
            Task {
                if let message = await viewModel.createShareAndBuildMessage(for: .note(note)) {
                    onSendMessage?(message)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(uiColorForIntent(note.intent.rawValue).opacity(0.2))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(uiColorForIntent(note.intent.rawValue))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(note.displayTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !note.body.isEmpty {
                        Text(String(note.body.prefix(60)))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fallback

    @ViewBuilder
    private var fallbackView: some View {
        VStack(spacing: 8) {
            Text("O")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)

            Text("obius")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Open Obius to get started")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func uiColorForIntent(_ intent: String) -> Color {
        switch intent {
        case "question": return .yellow
        case "task": return .green
        case "evidence": return .purple
        default: return .blue
        }
    }
}
