import Foundation
import Combine

@MainActor
final class NotesListViewModel: ObservableObject {
    private let noteRepository: NoteRepository
    private var cancellables = Set<AnyCancellable>()

    @Published var notes: [Note] = []
    @Published var searchQuery: String = ""
    @Published var searchResults: [Note] = []
    @Published var isSearching: Bool = false

    var displayedNotes: [Note] {
        isSearching ? searchResults : notes
    }

    var pinnedNotes: [Note] {
        displayedNotes.filter { $0.isPinned }
    }

    var unpinnedNotes: [Note] {
        displayedNotes.filter { !$0.isPinned }
    }

    init(noteRepository: NoteRepository) {
        self.noteRepository = noteRepository

        // Observe notes from repository
        noteRepository.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notes in
                self?.notes = notes
            }
            .store(in: &cancellables)

        // Handle search with debounce
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] query in
                Task {
                    await self?.performSearch(query: query)
                }
            }
            .store(in: &cancellables)
    }

    func createNote() async throws -> Note {
        try await noteRepository.createNote()
    }

    func deleteNote(_ note: Note) async throws {
        try await noteRepository.deleteNote(note.id)
    }

    func togglePinned(_ note: Note) async throws {
        try await noteRepository.togglePinned(note.id)
    }

    func setIntent(_ note: Note, intent: IntentType) async throws {
        try await noteRepository.setIntent(note.id, intent: intent)
    }

    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            isSearching = false
            searchResults = []
            return
        }

        isSearching = true
        do {
            searchResults = try await noteRepository.searchNotes(query: trimmed)
        } catch {
            print("Search error: \(error)")
            searchResults = []
        }
    }

    func clearSearch() {
        searchQuery = ""
        isSearching = false
        searchResults = []
    }
}
