import SwiftUI

struct NotesListView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NotesListContent(
            noteRepository: appState.noteRepository,
            sectionRepository: appState.sectionRepository,
            syncLogger: appState.syncLogger,
            syncEngine: appState.syncEngine
        )
    }
}

// MARK: - Inner Content View

private struct NotesListContent: View {
    @ObservedObject var noteRepository: NoteRepository
    let sectionRepository: SectionRepository
    let syncLogger: SyncOperationLogger
    let syncEngine: SyncEngine

    @State private var searchQuery = ""
    @State private var selectedNote: Note?

    private var notes: [Note] {
        noteRepository.notes
    }

    private var filteredNotes: [Note] {
        if searchQuery.isEmpty {
            return notes
        }
        return notes.filter { note in
            note.displayTitle.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var pinnedNotes: [Note] {
        filteredNotes.filter { $0.isPinned }
    }

    private var unpinnedNotes: [Note] {
        filteredNotes.filter { !$0.isPinned }
    }

    var body: some View {
        List {
            if !pinnedNotes.isEmpty {
                SwiftUI.Section("Pinned") {
                    ForEach(pinnedNotes) { note in
                        noteRow(note)
                    }
                }
            }

            SwiftUI.Section(pinnedNotes.isEmpty ? "Notes" : "Other Notes") {
                ForEach(unpinnedNotes) { note in
                    noteRow(note)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .searchable(text: $searchQuery, prompt: "Search notes")
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task {
                        do {
                            let note = try await noteRepository.createNote()
                            // Log for sync
                            syncLogger.logNoteCreate(note)
                            selectedNote = note
                        } catch {
                            print("Failed to create note: \(error)")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(item: $selectedNote) { note in
            NoteEditorView(noteId: note.id)
        }
        .syncRefreshable()
        .overlay {
            if notes.isEmpty && searchQuery.isEmpty {
                ContentUnavailableView {
                    Label("No Notes", systemImage: "note.text")
                } description: {
                    Text("Tap + to create your first note")
                } actions: {
                    Button("Create Note") {
                        Task {
                            if let note = try? await noteRepository.createNote() {
                                syncLogger.logNoteCreate(note)
                                selectedNote = note
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if !searchQuery.isEmpty && filteredNotes.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            }
        }
    }

    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        NoteRowView(note: note)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedNote = note
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task {
                        try? await noteRepository.deleteNote(note.id)
                        syncLogger.logNoteDelete(note.id)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    Task {
                        try? await noteRepository.togglePinned(note.id)
                        if let updated = try? await noteRepository.getNote(id: note.id) {
                            syncLogger.logNoteUpdate(updated)
                        }
                    }
                } label: {
                    Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                .tint(.orange)

                // AI Title button
                Button {
                    Task {
                        do {
                            let (title, _) = try await syncEngine.generateSummary(noteId: note.id)
                            print("Generated title: \(title)")
                        } catch {
                            print("Failed to generate title: \(error)")
                        }
                    }
                } label: {
                    Label("AI Title", systemImage: "sparkles")
                }
                .tint(.purple)
            }
    }
}

#Preview {
    NavigationStack {
        NotesListView()
    }
    .environmentObject(AppState())
    .environmentObject(AuthManager.shared)
}
