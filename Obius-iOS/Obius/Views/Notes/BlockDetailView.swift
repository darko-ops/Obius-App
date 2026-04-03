import SwiftUI

struct BlockDetailView: View {
    let blockName: String
    let notes: [Note]
    let sectionPreviews: [String: String]
    let autoTitles: [String: String]
    @ObservedObject var noteRepository: NoteRepository
    let sectionRepository: SectionRepository
    let syncLogger: SyncOperationLogger
    let commitModule: CommitModule
    @ObservedObject var moduleRepository: ModuleRepository

    @State private var selectedNote: Note?
    @State private var pageCommitItem: PageCommitItem?

    var body: some View {
        List {
            ForEach(notes) { note in
                NoteRowView(note: note, sectionContent: sectionPreviews[note.id], autoTitle: autoTitles[note.id])
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedNote = note
                    }
                    .contextMenu {
                        Button {
                            Task {
                                try? await noteRepository.setGroupName(noteId: note.id, groupName: nil)
                            }
                        } label: {
                            Label("Remove from Block", systemImage: "cube.transparent")
                        }

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

                        Divider()

                        Button {
                            guard TierManager.shared.requireFeature(.commits) else { return }
                            pageCommitItem = PageCommitItem(noteId: note.id, pageTitle: note.title ?? "")
                        } label: {
                            Label("Save Version", systemImage: "arrow.down.doc")
                        }

                        if moduleRepository.modules.count > 1 {
                            Menu {
                                ForEach(moduleRepository.modules.filter { $0.id != note.moduleId }) { module in
                                    Button {
                                        Task {
                                            try? await noteRepository.setModuleId(noteId: note.id, moduleId: module.id)
                                        }
                                    } label: {
                                        Label(module.name, systemImage: module.icon)
                                    }
                                }
                            } label: {
                                Label("Move to Project", systemImage: "folder")
                            }
                        }

                        Divider()

                        Button(role: .destructive) {
                            Task {
                                try? await noteRepository.deleteNote(note.id)
                                syncLogger.logNoteDelete(note.id)
                            }
                        } label: {
                            Label("Delete Page", systemImage: "trash")
                        }
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
                                try? await noteRepository.setGroupName(noteId: note.id, groupName: nil)
                            }
                        } label: {
                            Label("Remove", systemImage: "cube.transparent")
                        }
                        .tint(.orange)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.systemBackground)
        .navigationTitle(blockName)
        .inlineNavigationTitle()
        .navigationDestination(item: $selectedNote) { note in
            NoteEditorView(noteId: note.id)
        }
        .sheet(item: $pageCommitItem) { item in
            PageCommitSheet(
                noteId: item.noteId,
                pageTitle: item.pageTitle,
                onCommit: { name, title, comment in
                    Task {
                        do {
                            _ = try await commitModule.createCommit(
                                noteId: item.noteId,
                                name: name,
                                titleOverride: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title
                            )
                        } catch {
                            print("Failed to create page commit: \(error)")
                        }
                    }
                }
            )
        }
    }
}
