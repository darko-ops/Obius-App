import SwiftUI

struct NotesListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NotesListContent(
            noteRepository: appState.noteRepository,
            sectionRepository: appState.sectionRepository,
            syncLogger: appState.syncLogger,
            syncEngine: appState.syncEngine,
            commitModule: appState.commitModule
        )
    }
}

// MARK: - Inner Content View

private struct NotesListContent: View {
    @ObservedObject var noteRepository: NoteRepository
    let sectionRepository: SectionRepository
    let syncLogger: SyncOperationLogger
    let syncEngine: SyncEngine
    let commitModule: CommitModule

    @State private var searchQuery = ""
    @State private var selectedNote: Note?
    @State private var sectionPreviews: [String: String] = [:]
    @State private var autoTitles: [String: String] = [:]
    @State private var showingTemplates = false
    @State private var templateTargetNoteId: String?
    @State private var showingCommitConfirmation = false
    @State private var lastCommitName: String?
    @State private var pageCommitItem: PageCommitItem?
    @State private var isSelectionMode = false
    @State private var selectedNoteIds: Set<String> = []
    @State private var showingDeleteConfirmation = false
    @State private var showingGroupDialog = false
    @State private var newGroupName = ""
    @State private var collapsedGroups: Set<String> = []

    private var notes: [Note] {
        noteRepository.notes
    }

    private var filteredNotes: [Note] {
        if searchQuery.isEmpty {
            return notes
        }
        return notes.filter { note in
            let title = autoTitles[note.id] ?? note.displayTitle
            return title.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    // Get unique group names (excluding nil)
    private var groupNames: [String] {
        Array(Set(filteredNotes.compactMap { $0.groupName })).sorted()
    }

    // Notes that belong to a group (pinned groups)
    private var groupedNotes: [String: [Note]] {
        Dictionary(grouping: filteredNotes.filter { $0.groupName != nil }, by: { $0.groupName! })
    }

    // Ungrouped pinned notes
    private var pinnedNotes: [Note] {
        filteredNotes.filter { $0.isPinned && $0.groupName == nil }
    }

    // Ungrouped unpinned notes
    private var unpinnedNotes: [Note] {
        filteredNotes.filter { !$0.isPinned && $0.groupName == nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom rounded search bar
            RoundedSearchBar(text: $searchQuery, placeholder: "Search notes")
                .padding(.horizontal)
                .padding(.vertical, 8)

            List {
                // Grouped notes (pinned groups) - collapsible
                ForEach(groupNames, id: \.self) { groupName in
                SwiftUI.Section {
                    if !collapsedGroups.contains(groupName) {
                        ForEach(groupedNotes[groupName] ?? []) { note in
                            noteRow(note)
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if collapsedGroups.contains(groupName) {
                                collapsedGroups.remove(groupName)
                            } else {
                                collapsedGroups.insert(groupName)
                            }
                        }
                    } label: {
                        HStack {
                            Text(groupName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("\(groupedNotes[groupName]?.count ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Image(systemName: collapsedGroups.contains(groupName) ? "chevron.right" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Ungrouped pinned notes
            if !pinnedNotes.isEmpty {
                SwiftUI.Section("Pinned") {
                    ForEach(pinnedNotes) { note in
                        noteRow(note)
                    }
                }
            }

            // Ungrouped unpinned notes
            SwiftUI.Section(pinnedNotes.isEmpty && groupNames.isEmpty ? "Recently" : "Other Notes") {
                ForEach(unpinnedNotes) { note in
                    noteRow(note)
                }
            }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
        .navigationTitle("Artifacts")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // More options menu
                Menu {
                    Button {
                        withAnimation {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedNoteIds.removeAll()
                            }
                        }
                    } label: {
                        Label(isSelectionMode ? "Cancel Selection" : "Select Pages", systemImage: isSelectionMode ? "xmark" : "checkmark.circle")
                    }

                    if isSelectionMode && !selectedNoteIds.isEmpty {
                        Button {
                            showingGroupDialog = true
                        } label: {
                            Label("Group (\(selectedNoteIds.count))", systemImage: "folder.badge.plus")
                        }

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Selected (\(selectedNoteIds.count))", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }

                // Add note button (hidden in selection mode)
                if !isSelectionMode {
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
        }
        .confirmationDialog(
            "Delete \(selectedNoteIds.count) pages?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteSelectedNotes()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Name this group", isPresented: $showingGroupDialog) {
            TextField("Group name", text: $newGroupName)
            Button("Create Group") {
                Task {
                    await groupSelectedNotes(groupName: newGroupName)
                    newGroupName = ""
                    isSelectionMode = false
                    selectedNoteIds.removeAll()
                }
            }
            Button("Cancel", role: .cancel) {
                newGroupName = ""
            }
        } message: {
            Text("Enter a name for the group")
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
        .overlay(alignment: .bottom) {
            if showingCommitConfirmation, let name = lastCommitName {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Saved: \(name).obx")
                        .font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(radius: 4)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: showingCommitConfirmation)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode {
                HStack {
                    // Select All / Deselect All
                    Button {
                        withAnimation {
                            if selectedNoteIds.count == filteredNotes.count {
                                selectedNoteIds.removeAll()
                            } else {
                                selectedNoteIds = Set(filteredNotes.map { $0.id })
                            }
                        }
                    } label: {
                        Text(selectedNoteIds.count == filteredNotes.count ? "Deselect All" : "Select All")
                            .font(.subheadline.weight(.medium))
                    }

                    Spacer()

                    // Selection count
                    Text("\(selectedNoteIds.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Delete button
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.title3)
                    }
                    .disabled(selectedNoteIds.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelectionMode)
        .sheet(isPresented: $showingTemplates) {
            TemplateListView { template in
                Task {
                    if let noteId = templateTargetNoteId {
                        // Apply template to the note by adding sections
                        // Template content appears as bold prefix, user can type after it
                        for item in template.sections {
                            let sectionType: SectionType = item.itemType == .node ? .fold : .line
                            try? await sectionRepository.createSection(
                                noteId: noteId,
                                content: item.content,  // Template text is in content
                                sectionType: sectionType,
                                isTemplateContent: true,
                                templatePrefix: item.content  // Tracks protected text
                            )
                        }
                    }
                    templateTargetNoteId = nil
                }
            }
        }
        .sheet(item: $pageCommitItem) { item in
            PageCommitSheet(
                noteId: item.noteId,
                onCommit: { name in
                    Task {
                        await commitPage(noteId: item.noteId, name: name)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        HStack(spacing: 12) {
            // Selection indicator
            if isSelectionMode {
                Image(systemName: selectedNoteIds.contains(note.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selectedNoteIds.contains(note.id) ? Color.accentColor : .secondary)
            }

            NoteRowView(note: note, sectionContent: sectionPreviews[note.id], autoTitle: autoTitles[note.id])
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if selectedNoteIds.contains(note.id) {
                        selectedNoteIds.remove(note.id)
                    } else {
                        selectedNoteIds.insert(note.id)
                    }
                }
            } else {
                selectedNote = note
            }
        }
        .task(id: note.updatedAt) {
            await loadSectionPreview(for: note)
        }
        .contextMenu {
                // Pin/Unpin
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

                // Intent submenu
                Menu {
                    ForEach(IntentType.allCases, id: \.self) { intent in
                        Button {
                            Task {
                                try? await noteRepository.setIntent(note.id, intent: intent)
                                if let updated = try? await noteRepository.getNote(id: note.id) {
                                    syncLogger.logNoteUpdate(updated)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: intent.icon)
                                Text(intent.displayName)
                                if note.intent == intent {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Status", systemImage: "paintpalette")
                }

                Divider()

                // Apply Template
                Button {
                    templateTargetNoteId = note.id
                    showingTemplates = true
                } label: {
                    Label("Apply Template", systemImage: "doc.on.doc")
                }

                // Commit Page
                Button {
                    pageCommitItem = PageCommitItem(noteId: note.id)
                } label: {
                    Label("Commit Page", systemImage: "arrow.down.doc")
                }

                Divider()

                // Delete
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
                        try? await noteRepository.togglePinned(note.id)
                        if let updated = try? await noteRepository.getNote(id: note.id) {
                            syncLogger.logNoteUpdate(updated)
                        }
                    }
                } label: {
                    Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                .tint(.orange)
            }
    }

    private func commitPage(noteId: String, name: String) async {
        do {
            _ = try await commitModule.createCommit(noteId: noteId, name: name)
            lastCommitName = name
            showingCommitConfirmation = true
            pageCommitItem = nil

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showingCommitConfirmation = false
            }
        } catch {
            print("Failed to create page commit: \(error)")
        }
    }

    private func loadSectionPreview(for note: Note) async {
        // Skip if body already has content (body is observed directly, no caching needed)
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.isEmpty else {
            sectionPreviews.removeValue(forKey: note.id)
            autoTitles.removeValue(forKey: note.id)
            return
        }

        do {
            let sections = try await sectionRepository.getSections(noteId: note.id)
            let sorted = sections.sorted(by: { $0.orderKey < $1.orderKey })

            // Compute auto-title with full section context
            let computed = note.displayTitle(sections: sorted)
            let hasUserTitle = note.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let hasAiTitle = note.aiTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            if !hasUserTitle && !hasAiTitle {
                autoTitles[note.id] = computed
            } else {
                autoTitles.removeValue(forKey: note.id)
            }

            // Find first section with content for the preview subtitle
            if let firstContent = sorted
                .first(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                if firstContent.contentType == .audio {
                    // Parse "hash|duration" format
                    let parts = firstContent.content.split(separator: "|", maxSplits: 1)
                    if parts.count > 1, let seconds = Double(parts[1]) {
                        let mins = Int(seconds) / 60
                        let secs = Int(seconds) % 60
                        sectionPreviews[note.id] = String(format: "Audio %d:%02d", mins, secs)
                    } else {
                        sectionPreviews[note.id] = "Audio recording"
                    }
                } else if firstContent.contentType == .image {
                    // Count photos from "hash|assetId,hash|assetId,..." format
                    let count = firstContent.content
                        .split(separator: ",")
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        .count
                    sectionPreviews[note.id] = count == 1 ? "1 photo" : "\(count) photos"
                } else {
                    sectionPreviews[note.id] = firstContent.content
                }
            } else {
                sectionPreviews.removeValue(forKey: note.id)
            }
        } catch {
            print("Failed to load sections for preview: \(error)")
        }
    }

    private func deleteSelectedNotes() async {
        for noteId in selectedNoteIds {
            do {
                try await noteRepository.deleteNote(noteId)
                syncLogger.logNoteDelete(noteId)
            } catch {
                print("Failed to delete note \(noteId): \(error)")
            }
        }
        // Exit selection mode and clear selection
        withAnimation {
            selectedNoteIds.removeAll()
            isSelectionMode = false
        }
    }

    private func groupSelectedNotes(groupName: String) async {
        guard !groupName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        for noteId in selectedNoteIds {
            do {
                try await noteRepository.setGroupName(noteId: noteId, groupName: groupName)
            } catch {
                print("Failed to group note \(noteId): \(error)")
            }
        }
    }
}

// MARK: - Rounded Search Bar

struct RoundedSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.body)

            TextField(placeholder, text: $text)
                .focused($isFocused)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.gray.opacity(0.12))
        )
    }
}

#Preview {
    NavigationStack {
        NotesListView()
    }
    .environmentObject(AppState())
    .environmentObject(AuthManager.shared)
}
