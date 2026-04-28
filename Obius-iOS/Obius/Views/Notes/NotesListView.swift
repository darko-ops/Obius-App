import SwiftUI

struct NotesListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NotesListContent(
            noteRepository: appState.noteRepository,
            moduleRepository: appState.moduleRepository,
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
    @ObservedObject var moduleRepository: ModuleRepository
    let sectionRepository: SectionRepository
    let syncLogger: SyncOperationLogger
    let syncEngine: SyncEngine
    let commitModule: CommitModule

    @AppStorage("selectedModuleId") private var selectedModuleId: String?
    #if os(macOS)
    @AppStorage("macIsInEditor") private var macIsInEditor = false
    @AppStorage("macSelectedNoteId") private var macSelectedNoteId: String?
    #endif
    @State private var showingModulePicker = false
    @State private var searchQuery = ""
    @State private var selectedNote: Note?
    @State private var sectionPreviews: [String: String] = [:]
    @State private var sectionSearchContent: [String: String] = [:]
    @State private var autoTitles: [String: String] = [:]
    @State private var showingCommitConfirmation = false
    @State private var lastCommitName: String?
    @State private var pageCommitItem: PageCommitItem?
    @State private var showingNativeShare = false
    @State private var shareItems: [Any] = []
    @State private var shareURL: URL?
    @State private var shareTitle: String = ""
    @State private var sharePreview: String = ""
    @State private var shareError: String?
    @State private var pendingShare = false
    @State private var isSelectionMode = false
    @State private var selectedNoteIds: Set<String> = []
    @State private var showingDeleteConfirmation = false
    @State private var showingGroupDialog = false
    @State private var newGroupName = ""
    @State private var selectedBlockName: String?
    // longPressedBlockName removed — blocks use contextMenu now
    @State private var blockToDelete: String?
    @State private var blockToRename: String?
    @State private var renameBlockText: String = ""
    @AppStorage("trackedBlockNames") private var trackedBlockNamesData: String = "[]"

    private var trackedBlockNames: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(trackedBlockNamesData.utf8))) ?? []
    }

    private func setTrackedBlockNames(_ names: [String]) {
        if let data = try? JSONEncoder().encode(names), let str = String(data: data, encoding: .utf8) {
            trackedBlockNamesData = str
        }
    }

    private var selectedModule: Module? {
        moduleRepository.modules.first { $0.id == selectedModuleId }
    }

    private var selectedModuleName: String {
        selectedModule?.name ?? "Artifacts"
    }

    private var notes: [Note] {
        noteRepository.notes.filter { $0.moduleId == selectedModuleId }
    }

    private var filteredNotes: [Note] {
        if searchQuery.isEmpty {
            return notes
        }
        let query = searchQuery
        return notes.filter { note in
            let title = autoTitles[note.id] ?? note.displayTitle
            if title.localizedCaseInsensitiveContains(query) { return true }

            // Search note body
            if note.body.localizedCaseInsensitiveContains(query) { return true }

            // Search tags (#handles)
            if note.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return true }
            if note.aiTags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return true }

            // Search section/node content
            if let content = sectionSearchContent[note.id],
               content.localizedCaseInsensitiveContains(query) { return true }

            return false
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
            RoundedSearchBar(text: $searchQuery, placeholder: "Search")
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.systemBackground)

            notesList
        }
        .background(Color.systemBackground)
        .navigationTitle("")
        .inlineNavigationTitle()
        .platformToolbarBackground(.black)
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Delete \(selectedNoteIds.count) pages?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteSelectedNotes() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Name this block", isPresented: $showingGroupDialog) {
            TextField("Block name", text: $newGroupName)
            Button("Create Block") {
                Task {
                    await groupSelectedNotes(groupName: newGroupName)
                    newGroupName = ""
                    isSelectionMode = false
                    selectedNoteIds.removeAll()
                }
            }
            Button("Cancel", role: .cancel) { newGroupName = "" }
        } message: {
            Text("Enter a name for the block")
        }
        .alert("Unable to Share", isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        #if os(iOS)
        .navigationDestination(item: $selectedNote) { note in
            NoteEditorView(noteId: note.id)
        }
        #endif
        .navigationDestination(isPresented: Binding(
            get: { selectedBlockName != nil },
            set: { if !$0 { selectedBlockName = nil } }
        )) {
            if let blockName = selectedBlockName {
                BlockDetailView(
                    blockName: blockName,
                    notes: groupedNotes[blockName] ?? [],
                    sectionPreviews: sectionPreviews,
                    autoTitles: autoTitles,
                    noteRepository: noteRepository,
                    sectionRepository: sectionRepository,
                    syncLogger: syncLogger,
                    commitModule: commitModule,
                    moduleRepository: moduleRepository
                )
            }
        }
        .syncRefreshable()
        .overlay { emptyStateOverlay }
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

                    // Block button
                    Button {
                        showingGroupDialog = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "cube.transparent")
                                .font(.subheadline)
                            Text("Block")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .disabled(selectedNoteIds.isEmpty)

                    Spacer()
                        .frame(width: 16)

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
        .sheet(item: $pageCommitItem) { item in
            PageCommitSheet(
                noteId: item.noteId,
                pageTitle: item.pageTitle,
                onCommit: { name, title, comment in
                    Task {
                        await commitPage(noteId: item.noteId, name: name, title: title, comment: comment)
                    }
                }
            )
        }
        .sheet(isPresented: $showingNativeShare) {
            if let url = shareURL {
                NodeShareSheet(url: url, title: shareTitle, preview: sharePreview)
            }
        }
        .sheet(isPresented: $showingModulePicker) {
            ModulePickerSheet(
                moduleRepository: moduleRepository,
                selectedModuleId: $selectedModuleId
            )
        }
        .onAppear {
            DispatchQueue.main.async {
                if selectedModuleId == nil, let local = moduleRepository.getLocalModule() {
                    selectedModuleId = local.id
                }
            }
        }
        .onChange(of: moduleRepository.modules) { _ in
            DispatchQueue.main.async {
                if let id = selectedModuleId,
                   !moduleRepository.modules.contains(where: { $0.id == id }) {
                    selectedModuleId = moduleRepository.getLocalModule()?.id
                }
            }
        }
        #if os(macOS)
        .onChange(of: selectedNote) { _, newValue in
            let newId = newValue?.id
            guard macSelectedNoteId != newId else { return }
            print("[DEBUG] NotesListView .onChange(selectedNote): \(newId?.prefix(8) ?? "nil")")
            DispatchQueue.main.async {
                macIsInEditor = newValue != nil
                macSelectedNoteId = newId
            }
        }
        #endif
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .principal) {
            Button {
                showingModulePicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(selectedModuleName)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
        #else
        ToolbarItem(placement: .principal) {
            Button {
                showingModulePicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(selectedModuleName)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
        #endif

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button {
                    withAnimation {
                        isSelectionMode.toggle()
                        if !isSelectionMode { selectedNoteIds.removeAll() }
                    }
                } label: {
                    Label(isSelectionMode ? "Cancel Selection" : "Select Pages", systemImage: isSelectionMode ? "xmark" : "checkmark.circle")
                }

                if isSelectionMode && !selectedNoteIds.isEmpty {
                    Button { showingGroupDialog = true } label: {
                        Label("Block (\(selectedNoteIds.count))", systemImage: "cube.transparent")
                    }
                    Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                        Label("Delete Selected (\(selectedNoteIds.count))", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.gray)
            }

            if !isSelectionMode {
                Button {
                    guard TierManager.shared.requireNoteCreation(currentCount: noteRepository.notes.count) else { return }
                    Task {
                        do {
                            let note = try await noteRepository.createNote(moduleId: selectedModuleId)
                            // Don't logNoteCreate here — the editor's onDisappear handles sync
                            // so we don't push an empty note to other devices
                            selectedNote = note
                        } catch {
                            print("Failed to create note: \(error)")
                        }
                    }
                } label: {
                    Image(systemName: "plus").foregroundStyle(.gray)
                }
            }
        }

        #if os(iOS)
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button {
                KeyboardHelper.dismiss()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
        }
        #endif
    }

    @ViewBuilder
    private var emptyStateOverlay: some View {
        if notes.isEmpty && searchQuery.isEmpty {
            ContentUnavailableView {
                Label("No Notes", systemImage: "note.text")
            } description: {
                Text("Tap + to create your first note")
            } actions: {
                Button {
                    guard TierManager.shared.requireNoteCreation(currentCount: noteRepository.notes.count) else { return }
                    Task {
                        if let note = try? await noteRepository.createNote(moduleId: selectedModuleId) {
                            selectedNote = note
                        }
                    }
                } label: {
                    Text("Create Note")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(white: 0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        } else if !searchQuery.isEmpty && filteredNotes.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
        }
    }

    private var activeTrackedBlocks: [String] {
        trackedBlockNames.filter { groupNames.contains($0) }
    }

    private var notesList: some View {
        List {
            if !pinnedNotes.isEmpty || !activeTrackedBlocks.isEmpty {
                SwiftUI.Section {
                    ForEach(activeTrackedBlocks, id: \.self) { blockName in
                        TrackedBlockRow(
                            blockName: blockName,
                            onTap: { selectedBlockName = blockName },
                            onUntrack: {
                                var names = trackedBlockNames
                                names.removeAll { $0 == blockName }
                                setTrackedBlockNames(names)
                            }
                        )
                    }

                    ForEach(pinnedNotes) { note in
                        TrackedPageRow(
                            title: autoTitles[note.id] ?? note.displayTitle,
                            preview: pagePreviewText(for: note),
                            intent: note.intent,
                            onTap: { selectedNote = note }
                        )
                        .contextMenu {
                            Button {
                                Task {
                                    try? await noteRepository.togglePinned(note.id)
                                    if let updated = try? await noteRepository.getNote(id: note.id) {
                                        syncLogger.logNoteUpdate(updated)
                                    }
                                }
                            } label: {
                                Label("Untrack", systemImage: "location.slash")
                            }

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

                            Button {
                                guard TierManager.shared.requireFeature(.commits) else { return }
                                pageCommitItem = PageCommitItem(noteId: note.id, pageTitle: note.title ?? "")
                            } label: {
                                Label("Save Version", systemImage: "arrow.down.doc")
                            }

                            Button {
                                Task {
                                    await createPageShareLink(for: note)
                                }
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }

                            if moduleRepository.modules.count > 1 {
                                Menu {
                                    ForEach(moduleRepository.modules.filter { $0.id != note.moduleId }) { module in
                                        Button {
                                            Task {
                                                try? await noteRepository.setModuleId(noteId: note.id, moduleId: module.id)
                                                if let updated = try? await noteRepository.getNote(id: note.id) {
                                                    syncLogger.logNoteUpdate(updated)
                                                }
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
                    }
                } header: {
                    Text("TRACKING")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                        #if os(macOS)
                        .listRowBackground(Color(white: 0.06))
                        .listSectionSeparator(.hidden)
                        #endif
                }
            }

            SwiftUI.Section {
                ForEach(unpinnedNotes) { note in
                    noteRow(note)
                }
            } header: {
                Text("RECENTS")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(nil)
                    #if os(macOS)
                    .listRowBackground(Color(white: 0.06))
                    .listSectionSeparator(.hidden)
                    #endif
            }

            blocksSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Block options now handled by contextMenu on BlockCellView
        .alert(
            "Delete \"\(blockToDelete ?? "")\"?",
            isPresented: Binding(
                get: { blockToDelete != nil },
                set: { if !$0 { blockToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let name = blockToDelete {
                    Task { await deleteBlock(name: name) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = groupedNotes[blockToDelete ?? ""]?.count ?? 0
            Text("This will permanently delete the block and all \(count) page\(count == 1 ? "" : "s") inside it.")
        }
        .alert("Rename Block", isPresented: Binding(
            get: { blockToRename != nil },
            set: { if !$0 { blockToRename = nil } }
        )) {
            TextField("Block name", text: $renameBlockText)
            Button("Rename") {
                if let oldName = blockToRename {
                    Task { await renameBlock(from: oldName, to: renameBlockText) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }



    private func pagePreviewText(for note: Note) -> String? {
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { return body }
        if let content = sectionPreviews[note.id], !content.isEmpty { return content }
        return nil
    }

    @ViewBuilder
    private var blocksSection: some View {
        if !groupNames.isEmpty {
            SwiftUI.Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                    ForEach(groupNames, id: \.self) { groupName in
                        BlockCellView(
                            groupName: groupName,
                            count: groupedNotes[groupName]?.count ?? 0,
                            isTracked: trackedBlockNames.contains(groupName),
                            onTap: { selectedBlockName = groupName },
                            onTrackToggle: {
                                var names = trackedBlockNames
                                if names.contains(groupName) {
                                    names.removeAll { $0 == groupName }
                                } else {
                                    names.append(groupName)
                                }
                                setTrackedBlockNames(names)
                            },
                            onRename: {
                                renameBlockText = groupName
                                blockToRename = groupName
                            },
                            onUnblock: {
                                Task { await unblockNotes(blockName: groupName) }
                            },
                            onDelete: {
                                blockToDelete = groupName
                            }
                        )
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                Text("BLOCKS")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(nil)
                    #if os(macOS)
                    .listRowBackground(Color(white: 0.06))
                    .listSectionSeparator(.hidden)
                    #endif
            }
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
        .onAppear {
            Task { await loadSectionPreview(for: note) }
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
                    Label(note.isPinned ? "Untrack" : "Track", systemImage: note.isPinned ? "location.slash" : "location")
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

                // Commit Page
                Button {
                    pageCommitItem = PageCommitItem(noteId: note.id, pageTitle: note.title ?? "")
                } label: {
                    Label("Save Version", systemImage: "arrow.down.doc")
                }

                // Share
                Button {
                    Task {
                        await createPageShareLink(for: note)
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                // Move to Module
                if moduleRepository.modules.count > 1 {
                    Menu {
                        ForEach(moduleRepository.modules.filter { $0.id != note.moduleId }) { module in
                            Button {
                                Task {
                                    try? await noteRepository.setModuleId(noteId: note.id, moduleId: module.id)
                                    if let updated = try? await noteRepository.getNote(id: note.id) {
                                        syncLogger.logNoteUpdate(updated)
                                    }
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
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    Task {
                        try? await noteRepository.deleteNote(note.id)
                        syncLogger.logNoteDelete(note.id)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    Task {
                        try? await noteRepository.togglePinned(note.id)
                        if let updated = try? await noteRepository.getNote(id: note.id) {
                            syncLogger.logNoteUpdate(updated)
                        }
                    }
                } label: {
                    Label(note.isPinned ? "Untrack" : "Track", systemImage: note.isPinned ? "location.slash" : "location")
                }
                .tint(.orange)
            }
    }

    private func commitPage(noteId: String, name: String, title: String, comment: String) async {
        do {
            let titleOverride = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let commit = try await commitModule.createCommit(
                noteId: noteId,
                name: name,
                titleOverride: titleOverride.isEmpty ? nil : titleOverride
            )
            lastCommitName = name
            showingCommitConfirmation = true
            pageCommitItem = nil

            // Post comment if provided
            let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedComment.isEmpty {
                Task {
                    await postCommitComment(commit: commit, comment: trimmedComment)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showingCommitConfirmation = false
            }
        } catch {
            print("Failed to create page commit: \(error)")
        }
    }

    private func postCommitComment(commit: Commit, comment: String) async {
        do {
            let content = try commitModule.getCommitContent(hash: commit.hash)
            let data = try JSONEncoder().encode(content)
            guard let jsonString = String(data: data, encoding: .utf8) else { return }

            let shareLink = try await ShareManager.shared.createCommitShare(
                commitHash: commit.hash,
                commitName: commit.name,
                commitShortId: commit.shortId,
                commitContent: jsonString
            )

            _ = try await ShareManager.shared.addComment(
                shareLinkId: shareLink.id,
                body: comment
            )
        } catch {
            print("Failed to post commit comment: \(error)")
        }
    }

    private func loadSectionPreview(for note: Note) async {
        do {
            let sections = try await sectionRepository.getSections(noteId: note.id)
            let sorted = sections.sorted(by: { $0.orderKey < $1.orderKey })

            // Always compute auto-title with full section context (matches editor behavior)
            let hasUserTitle = note.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let hasAiTitle = note.aiTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            if !hasUserTitle && !hasAiTitle {
                autoTitles[note.id] = note.displayTitle(sections: sorted)
            } else {
                autoTitles.removeValue(forKey: note.id)
            }

            // Find preview subtitle: use note body if present, otherwise first section content
            let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                sectionPreviews.removeValue(forKey: note.id)
            } else if let firstContent = sorted
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

            // Build searchable content from all text sections
            let searchText = sorted
                .filter { $0.contentType == .text }
                .map { $0.content }
                .joined(separator: " ")
            if !searchText.isEmpty {
                sectionSearchContent[note.id] = searchText
            } else {
                sectionSearchContent.removeValue(forKey: note.id)
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

    private func deleteBlock(name: String) async {
        // Remove from tracked list if tracked
        if trackedBlockNames.contains(name) {
            var names = trackedBlockNames
            names.removeAll { $0 == name }
            setTrackedBlockNames(names)
        }
        // Delete all notes in the block
        let notes = groupedNotes[name] ?? []
        for note in notes {
            do {
                try await noteRepository.deleteNote(note.id)
                syncLogger.logNoteDelete(note.id)
            } catch {
                print("Failed to delete note \(note.id): \(error)")
            }
        }
    }

    private func unblockNotes(blockName: String) async {
        // Remove from tracked list if tracked
        if trackedBlockNames.contains(blockName) {
            var names = trackedBlockNames
            names.removeAll { $0 == blockName }
            setTrackedBlockNames(names)
        }
        // Clear group name from all notes — they return to the main list
        let notes = groupedNotes[blockName] ?? []
        for note in notes {
            do {
                try await noteRepository.setGroupName(noteId: note.id, groupName: nil)
            } catch {
                print("Failed to unblock note \(note.id): \(error)")
            }
        }
    }

    private func renameBlock(from oldName: String, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldName else { return }

        // Update group name on all notes in the block
        let notes = groupedNotes[oldName] ?? []
        for note in notes {
            do {
                try await noteRepository.setGroupName(noteId: note.id, groupName: trimmed)
            } catch {
                print("Failed to rename note \(note.id) block: \(error)")
            }
        }

        // Update tracked list if tracked
        if trackedBlockNames.contains(oldName) {
            var names = trackedBlockNames
            if let index = names.firstIndex(of: oldName) {
                names[index] = trimmed
            }
            setTrackedBlockNames(names)
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

    private func createPageShareLink(for note: Note) async {
        pendingShare = true
        defer { pendingShare = false }

        // Gather page title
        let title = autoTitles[note.id] ?? note.displayTitle

        // Gather all section content
        var sections: [Section] = []
        var contentParts: [String] = []
        do {
            sections = try await sectionRepository.getSections(noteId: note.id)
            sections.sort(by: { $0.orderKey < $1.orderKey })
            for section in sections {
                let text = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && section.contentType != .image && section.contentType != .audio {
                    contentParts.append(text)
                }
            }
        } catch {
            shareError = "Failed to load page content"
            return
        }

        // Also include note body if present
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            contentParts.insert(body, at: 0)
        }

        let preview = contentParts.joined(separator: "\n")

        do {
            let shareLink = try await ShareManager.shared.createLiveShare(noteId: note.id, note: note, sections: sections)
            guard let url = URL(string: shareLink.url) else {
                shareError = "Failed to generate share URL"
                return
            }

            // Build and write message payload for iMessage extension
            let handles = sections.compactMap { section in
                HandleManager.shared.handles.first(where: { $0.id == section.handleId })
            }
            let payload = ShareManager.shared.buildMessagePayload(
                shareLink: shareLink,
                title: title,
                sections: sections,
                handles: handles
            )
            payload.writeToSharedDefaults()

            shareURL = url
            shareTitle = title
            sharePreview = String(preview.prefix(200))
            showingNativeShare = true
        } catch {
            shareError = error.localizedDescription
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
                #else
                .textFieldStyle(.plain)
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

// MARK: - Block Cell (separate struct for independent context menus)

private struct BlockCellView: View {
    let groupName: String
    let count: Int
    let isTracked: Bool
    let onTap: () -> Void
    let onTrackToggle: () -> Void
    let onRename: () -> Void
    let onUnblock: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 32))
                .foregroundStyle(Color.white.opacity(0.85))

            Text(groupName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onTap() }
        .contextMenu {
            Button {
                onTrackToggle()
            } label: {
                Label(isTracked ? "Untrack" : "Track", systemImage: isTracked ? "location.slash" : "location")
            }

            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                onUnblock()
            } label: {
                Label("Unblock", systemImage: "arrow.uturn.backward")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Block", systemImage: "trash")
            }
        }
    }
}

// MARK: - Tracked Block Row (separate struct for independent context menus)

private struct TrackedBlockRow: View {
    let blockName: String
    let onTap: () -> Void
    let onUntrack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 20))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 28)

            Text(blockName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color(red: 0.06, green: 0.06, blue: 0.06))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            Button {
                onUntrack()
            } label: {
                Label("Untrack", systemImage: "location.slash")
            }
        }
    }
}

// MARK: - Tracked Page Row (separate struct for independent context menus)

private struct TrackedPageRow: View {
    let title: String
    let preview: String?
    let intent: IntentType
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(intent.color)
                .frame(width: 4, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let preview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 10)

            Spacer()

            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color(red: 0.06, green: 0.06, blue: 0.06))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

#Preview {
    NavigationStack {
        NotesListView()
    }
    .environmentObject(AppState())
    .environmentObject(AuthManager.shared)
}
