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
    @State private var showingModulePicker = false
    @State private var searchQuery = ""
    @State private var selectedNote: Note?
    @State private var sectionPreviews: [String: String] = [:]
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
            RoundedSearchBar(text: $searchQuery, placeholder: "Search")
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))

            notesList
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
        .navigationDestination(item: $selectedNote) { note in
            NoteEditorView(noteId: note.id)
        }
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
            // Set initial module to Local if none selected
            if selectedModuleId == nil, let local = moduleRepository.getLocalModule() {
                selectedModuleId = local.id
            }
        }
        .onChange(of: moduleRepository.modules) { _ in
            // If selected module was deleted, fall back to Local
            if let id = selectedModuleId,
               !moduleRepository.modules.contains(where: { $0.id == id }) {
                selectedModuleId = moduleRepository.getLocalModule()?.id
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if let module = selectedModule {
                StorageTypeBadge(storageType: module.storageType)
            }
        }

        ToolbarItem(placement: .principal) {
            Button {
                showingModulePicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(selectedModuleName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
        }

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
                    Task {
                        do {
                            let note = try await noteRepository.createNote(moduleId: selectedModuleId)
                            syncLogger.logNoteCreate(note)
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

        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
        }
    }

    @ViewBuilder
    private var emptyStateOverlay: some View {
        if notes.isEmpty && searchQuery.isEmpty {
            ContentUnavailableView {
                Label("No Notes", systemImage: "note.text")
            } description: {
                Text("Tap + to create your first note")
            } actions: {
                Button("Create Note") {
                    Task {
                        if let note = try? await noteRepository.createNote(moduleId: selectedModuleId) {
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

    private var activeTrackedBlocks: [String] {
        trackedBlockNames.filter { groupNames.contains($0) }
    }

    private var notesList: some View {
        List {
            if !pinnedNotes.isEmpty || !activeTrackedBlocks.isEmpty {
                SwiftUI.Section {
                    trackingRow
                } header: {
                    Text("TRACKING")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(.secondaryLabel))
                        .textCase(nil)
                }
            }

            SwiftUI.Section {
                ForEach(unpinnedNotes) { note in
                    noteRow(note)
                }
            } header: {
                Text("RECENTS")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.secondaryLabel))
                    .textCase(nil)
            }

            blocksSection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #endif
    }

    private var trackingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(activeTrackedBlocks, id: \.self) { blockName in
                    Button {
                        selectedBlockName = blockName
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.white.opacity(0.85))

                            Text(blockName)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .frame(width: 64, height: 80)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(pinnedNotes) { note in
                    Button {
                        selectedNote = note
                    } label: {
                        trackedPageCard(note: note)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func trackedPageCard(note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(autoTitles[note.id] ?? note.displayTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let preview = pagePreviewText(for: note) {
                Text(preview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(10)
        .frame(width: 140, height: 80, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
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
                            onTrack: {
                                var names = trackedBlockNames
                                names.append(groupName)
                                setTrackedBlockNames(names)
                            },
                            onUntrack: {
                                var names = trackedBlockNames
                                names.removeAll { $0 == groupName }
                                setTrackedBlockNames(names)
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
                    .foregroundColor(Color(.secondaryLabel))
                    .textCase(nil)
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
        .listRowBackground(Color(.systemBackground))
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

                // Commit Page
                Button {
                    pageCommitItem = PageCommitItem(noteId: note.id, pageTitle: note.title ?? "")
                } label: {
                    Label("Commit Page", systemImage: "arrow.down.doc")
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
    let onTrack: () -> Void
    let onUntrack: () -> Void

    var body: some View {
        Button(action: onTap) {
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
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isTracked {
                Button(action: onUntrack) {
                    Label("Untrack", systemImage: "eye.slash")
                }
            } else {
                Button(action: onTrack) {
                    Label("Track", systemImage: "eye")
                }
            }
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
