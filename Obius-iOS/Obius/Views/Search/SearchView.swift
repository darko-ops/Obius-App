import SwiftUI

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var searchResults: [Section] = []
    @State private var isSearching = false
    @State private var selectedNote: Note?

    var body: some View {
        List {
            if searchResults.isEmpty && isSearching {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(searchResults) { section in
                    SearchResultRow(section: section)
                        .onTapGesture {
                            Task {
                                // Navigate to the note containing this section
                                if let note = try? await appState.noteRepository.getNote(id: section.noteId) {
                                    selectedNote = note
                                }
                            }
                        }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search all sections")
        .navigationTitle("Search")
        .onChange(of: searchText) { _, newValue in
            performSearch(query: newValue)
        }
        .navigationDestination(item: $selectedNote) { note in
            NoteEditorView(noteId: note.id)
        }
    }

    private func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        Task {
            do {
                searchResults = try await appState.sectionRepository.searchSections(query: trimmed)
            } catch {
                print("Search error: \(error)")
                searchResults = []
            }
        }
    }
}

struct SearchResultRow: View {
    let section: Section

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.content)
                .lineLimit(3)
                .font(.body)

            HStack {
                // Intent indicator
                Circle()
                    .fill(section.intent.color)
                    .frame(width: 6, height: 6)

                Text("Updated \(Date(timeIntervalSince1970: Double(section.updatedAt) / 1000), style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
    .environmentObject(AppState())
}
