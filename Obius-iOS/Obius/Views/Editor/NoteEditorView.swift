import SwiftUI
import PhotosUI

struct NoteEditorView: View {
    @EnvironmentObject var appState: AppState
    let noteId: String

    var body: some View {
        NoteEditorContent(
            noteId: noteId,
            noteRepository: appState.noteRepository,
            sectionRepository: appState.sectionRepository,
            handleRepository: appState.handleRepository
        )
    }
}

// MARK: - Placeholder Rotation

/// Cycles through placeholders evenly using a round-robin counter.
private enum PlaceholderProvider {
    static let options = [
        "Catch it before it escapes\u{2026}",
        "I note, therefore I am\u{2026}",
        "The mind wanders. Pages don\u{2019}t\u{2026}",
        "From chaos, clarity\u{2026}",
        "Footnote your existence\u{2026}",
        "Archive the fleeting\u{2026}",
        "To note, or not to note\u{2026}",
        "Before it becomes myth\u{2026}",
        "The labyrinth begins here\u{2026}",
        "Memory not found\u{2026}",
        "Insert profound thought\u{2026}",
        "Dream it into ink\u{2026}",
        "Brave new note\u{2026}",
        "Et tu, Brain?\u{2026}",
    ]

    private static var counter = Int.random(in: 0..<options.count)

    static func next() -> String {
        let index = counter % options.count
        counter += 1
        return options[index]
    }
}

// MARK: - Inner Content View
private struct NoteEditorContent: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: NoteEditorViewModel
    @StateObject private var biometricManager = BiometricManager.shared
    @StateObject private var handleManager = HandleManager.shared
    @StateObject private var möbiusNavigation = MöbiusNavigationState()
    @State private var editingTitle = false
    @State private var titleText = ""
    @State private var bodyText = ""
    @State private var isReordering = false
    @State private var showingTemplates = false
    @State private var templateTargetSectionId: String?
    @State private var showingHandleSheet = false
    @State private var handleSheetSectionId: String?
    @State private var showingCommitConfirmation = false
    @State private var lastCommitName: String?
    @State private var nodeCommitSectionId: NodeCommitItem?
    @State private var pageCommitItem: PageCommitItem?
    @State private var shareSectionId: String?
    @State private var shareItems: [Any] = []
    @State private var showingNativeShare = false
    @State private var pendingShare = false
    @State private var shareURL: URL?
    @State private var shareTitle: String = ""
    @State private var sharePreview: String = ""
    @State private var shareError: String?
    @State private var showingAudioRecorder = false
    @State private var audioRecorderTargetSectionId: String?
    @State private var audioRecorderID = UUID()
    @State private var showingImagePicker = false
    @State private var imagePickerTargetSectionId: String?
    @State private var imagePickerPreselectedAssetIds: [String] = []
    @State private var imagePickerID = UUID()
    @State private var fullscreenImageItem: FullscreenImageItem?
    @FocusState private var focusedSectionId: String?
    @FocusState private var bodyFocused: Bool
    @FocusState private var titleFocused: Bool
    @State private var emptyPlaceholder: String = PlaceholderProvider.next()
    @State private var titleVisible = true

    let noteId: String

    init(noteId: String, noteRepository: NoteRepository, sectionRepository: SectionRepository, handleRepository: HandleRepository) {
        self.noteId = noteId
        _viewModel = StateObject(wrappedValue: NoteEditorViewModel(
            noteId: noteId,
            noteRepository: noteRepository,
            sectionRepository: sectionRepository,
            handleRepository: handleRepository
        ))
    }

    var body: some View {
        mainContent
            .navigationTitle(titleVisible ? "" : viewModel.displayTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .animation(.easeInOut(duration: 0.2), value: titleVisible)
            .toolbar { toolbarContent }
            .onChange(of: viewModel.focusedSectionId) { _, newValue in
                focusedSectionId = newValue
            }
            .onChange(of: focusedSectionId) { oldValue, newValue in
                // Re-lock the previous section if it was locked
                if let oldId = oldValue,
                   oldId != newValue,
                   let oldSection = viewModel.sections.first(where: { $0.id == oldId }),
                   oldSection.isLocked {
                    biometricManager.revokeAuthentication(for: oldId)
                }

                // Only sync non-nil values back to ViewModel.
                // The @FocusState isn't bound to section views, so SwiftUI
                // may reset it to nil — don't let that clear the ViewModel's focus.
                if let newValue = newValue, viewModel.focusedSectionId != newValue {
                    viewModel.focusedSectionId = newValue
                }
            }
            .onDisappear {
                Task {
                    await viewModel.cleanupEmptyNoteIfNeeded()
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
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
            .sheet(item: $nodeCommitSectionId) { item in
                NodeCommitSheet(
                    sectionId: item.sectionId,
                    onCommit: { name in
                        Task {
                            await commitNode(sectionId: item.sectionId, name: name)
                        }
                    }
                )
            }
            .sheet(item: $pageCommitItem) { item in
                PageCommitSheet(
                    noteId: item.noteId,
                    pageTitle: item.pageTitle,
                    onCommit: { name, title, comment in
                        Task {
                            await commitPage(name: name, title: title, comment: comment)
                        }
                    }
                )
            }
            .sheet(isPresented: $showingNativeShare) {
                if let url = shareURL {
                    NodeShareSheet(url: url, title: shareTitle, preview: sharePreview)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                if pendingShare {
                    pendingShare = false
                    showingNativeShare = true
                }
            }
            .alert("Unable to Share", isPresented: Binding(
                get: { shareError != nil },
                set: { if !$0 { shareError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(shareError ?? "")
            }
            .sheet(isPresented: $showingTemplates) {
                TemplateListView { template in
                    Task {
                        if let sectionId = templateTargetSectionId {
                            try? await viewModel.applyTemplateToSection(template, beforeSectionId: sectionId)
                        } else {
                            try? await viewModel.applyTemplate(template)
                        }
                        templateTargetSectionId = nil
                    }
                }
            }
            .sheet(isPresented: $showingHandleSheet) {
                HandleNameSheet(
                    existingHandles: handleManager.handles,
                    onCreateNew: { name, echoConfig in
                        guard let sectionId = handleSheetSectionId else { return }
                        Task {
                            do {
                                let handle = try await viewModel.promoteToHandle(sectionId: sectionId, handleName: name)
                                if let echoConfig {
                                    _ = try await EchoManager.shared.createEcho(handleId: handle.id, config: echoConfig)
                                }
                            } catch {
                                print("Error creating handle: \(error)")
                            }
                            handleSheetSectionId = nil
                        }
                    },
                    onSelectExisting: { handle in
                        guard let sectionId = handleSheetSectionId else { return }
                        Task {
                            do {
                                try await viewModel.linkToExistingHandle(sectionId: sectionId, handleId: handle.id)
                            } catch {
                                print("Error linking to handle: \(error)")
                            }
                            handleSheetSectionId = nil
                        }
                    }
                )
            }
            #if os(iOS)
            .sheet(isPresented: $showingAudioRecorder) {
                AudioRecorderView(
                    onSave: { data, duration in
                        guard let sectionId = audioRecorderTargetSectionId else { return }
                        // Clear immediately so onChange cleanup doesn't delete the section
                        audioRecorderTargetSectionId = nil
                        Task {
                            await saveRecordedAudio(data, duration: duration, toSectionId: sectionId)
                        }
                    },
                    onDismiss: {
                        showingAudioRecorder = false
                    }
                )
                .id(audioRecorderID)
            }
            .onChange(of: showingAudioRecorder) { _, isShowing in
                if !isShowing, let sectionId = audioRecorderTargetSectionId {
                    // Clean up empty audio section if recorder was cancelled
                    if let section = viewModel.getSection(sectionId),
                       section.content.trimmingCharacters(in: .whitespaces).isEmpty {
                        Task { try? await viewModel.deleteSection(sectionId) }
                    }
                    audioRecorderTargetSectionId = nil
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePickerView(
                    preselectedAssetIdentifiers: imagePickerPreselectedAssetIds,
                    onImagesPicked: { results in
                        guard let sectionId = imagePickerTargetSectionId else { return }
                        Task {
                            await savePickedImages(results, toSectionId: sectionId)
                            imagePickerTargetSectionId = nil
                        }
                    }
                )
                .id(imagePickerID)
            }
            .fullScreenCover(item: $fullscreenImageItem) { item in
                let entries = parseImageEntries(from: viewModel.getSection(item.sectionId)?.content ?? "")
                FullscreenImageViewer(
                    imageEntries: entries,
                    mediaRepository: appState.mediaRepository,
                    onEditSave: { keptEntries, newPicks in
                        Task {
                            await saveEditedImages(keptEntries: keptEntries, newPicks: newPicks, sectionId: item.sectionId)
                        }
                    }
                )
            }
            #endif
            .onChange(of: showingImagePicker) { _, isShowing in
                if !isShowing {
                    imagePickerTargetSectionId = nil
                    imagePickerPreselectedAssetIds = []
                }
            }
            .onChange(of: showingTemplates) { _, isShowing in
                if !isShowing {
                    templateTargetSectionId = nil
                }
            }
            .onChange(of: showingHandleSheet) { _, isShowing in
                if !isShowing {
                    handleSheetSectionId = nil
                }
            }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        MöbiusContainer(
            navigationState: möbiusNavigation,
            sections: viewModel.sections
        ) { currentParent, visibleSections in
            scrollContent(currentParent: currentParent, visibleSections: visibleSections)
        }
    }

    @ViewBuilder
    private func scrollContent(currentParent: Section?, visibleSections: [Section]) -> some View {
        let nonEmptySections = filterNonEmptySections(visibleSections)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerContent(currentParent: currentParent, nonEmptySectionsEmpty: nonEmptySections.isEmpty)

                    sectionListView(nonEmptySections: nonEmptySections, visibleSections: visibleSections)
                        .padding(.horizontal)

                    addSectionButton(visibleSections: visibleSections)

                    Spacer(minLength: 150)
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.never)
            .onChange(of: viewModel.focusedSectionId) { _, newId in
                // When focus changes, scroll to show the focused section — but not for image/audio sections,
                // so the title and body stay visible and remain tappable after adding a media node.
                guard let sectionId = newId,
                      let section = viewModel.getSection(sectionId),
                      section.contentType != .image && section.contentType != .audio else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(sectionId, anchor: .top)
                }
            }
            .onChange(of: viewModel.sections.count) { _, _ in
                // When a new section appears, scroll to it if it's the focus target (text sections only).
                guard let sectionId = viewModel.focusedSectionId,
                      let section = viewModel.getSection(sectionId),
                      section.contentType != .image && section.contentType != .audio else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(sectionId, anchor: .top)
                    }
                }
            }
        }
    }

    private func filterNonEmptySections(_ sections: [Section]) -> [Section] {
        // Show all sections - allow multiple blank nodes
        sections
    }

    @ViewBuilder
    private func headerContent(currentParent: Section?, nonEmptySectionsEmpty: Bool) -> some View {
        if möbiusNavigation.isAtRoot {
            VStack(alignment: .leading, spacing: 0) {
                titleView
                noteBodyEditor
            }
            .padding(.horizontal)
            .zIndex(1)  // Keep header above section list for hit testing so title/body stay tappable when image nodes exist
        } else if let parent = currentParent {
            MöbiusSectionHeader(section: parent) {
                withAnimation(.möbiusUnfold) {
                    möbiusNavigation.popBack()
                }
            }
        }
    }

    @ViewBuilder
    private func sectionListView(nonEmptySections: [Section], visibleSections: [Section]) -> some View {
        DraggableSectionList(
            sections: .constant(nonEmptySections),
            focusedSectionId: viewModel.focusedSectionId,
            isAuthenticated: { biometricManager.isAuthenticated(sectionId: $0) },
            hasChildren: { viewModel.hasChildren($0) },
            getHandle: { sectionId in
                guard let section = viewModel.getSection(sectionId) else { return nil }
                return viewModel.getHandle(for: section)
            },
            getDisplayContent: { section in
                viewModel.getDisplayContent(for: section)
            },
            onMove: { from, to in
                Task { try? await viewModel.moveSection(visibleSections[from].id, to: to) }
            },
            onContentChange: { id, content, richText in
                Task { try? await viewModel.updateDisplayContent(id, content: content, richText: richText) }
            },
            onReturn: { id in
                Task { try? await viewModel.handleReturn(sectionId: id) }
            },
            onBackspaceEmpty: { id in
                Task { try? await viewModel.handleBackspace(sectionId: id, isEmpty: true) }
            },
            onIndent: { id in
                Task { try? await viewModel.indent(id) }
            },
            onOutdent: { id in
                Task { try? await viewModel.outdent(id) }
            },
            onSetParent: { sectionId, parentId in
                Task { try? await viewModel.setParentSection(sectionId, parentId: parentId) }
            },
            onToggleCollapse: { id in
                Task { try? await viewModel.toggleCollapse(id) }
            },
            onToggleLock: { id in
                Task { try? await viewModel.toggleSectionLock(id) }
            },
            onUnlockRequest: { id in
                Task {
                    let success = await biometricManager.authenticate(for: id)
                    if success {
                        // Focus the node after successful unlock
                        viewModel.focusedSectionId = id
                        focusedSectionId = id
                    }
                }
            },
            onIntentChange: { id, intent in
                Task { try? await viewModel.setSectionIntent(id, intent: intent) }
            },
            onDelete: { id in
                Task { try? await viewModel.deleteSection(id) }
            },
            onFocus: { id in
                viewModel.focusedSectionId = id
                focusedSectionId = id
            },
            onDrillIn: { id in
                withAnimation(.möbiusUnfold) { möbiusNavigation.drillInto(id) }
            },
            onApplyTemplate: { id in
                templateTargetSectionId = id
                showingTemplates = true
            },
            onCreateLoop: { id in
                handleSheetSectionId = id
                showingHandleSheet = true
            },
            onUnlinkHandle: { id in
                Task { try? await viewModel.unlinkFromHandle(sectionId: id) }
            },
            onCommit: { sectionId in
                nodeCommitSectionId = NodeCommitItem(sectionId: sectionId)
            },
            onShare: { sectionId in
                Task {
                    await createShareLink(for: sectionId)
                }
            },
            onImageTap: { sectionId in
                guard let section = viewModel.getSection(sectionId) else { return }

                if section.contentType == .audio {
                    // Audio section: open recorder if empty, otherwise do nothing (playback handled by AudioNodeView)
                    if section.content.trimmingCharacters(in: .whitespaces).isEmpty {
                        audioRecorderTargetSectionId = sectionId
                        audioRecorderID = UUID()
                        showingAudioRecorder = true
                    }
                } else if !section.content.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Has images — open fullscreen viewer
                    fullscreenImageItem = FullscreenImageItem(sectionId: sectionId)
                } else {
                    // Empty — open picker directly
                    imagePickerTargetSectionId = sectionId
                    prepareAndShowImagePicker(for: sectionId)
                }
            },
            mediaRepository: appState.mediaRepository,
            getInterstitialContent: { viewModel.getInterstitialContent(afterSectionId: $0) },
            getInterstitialRichContent: { viewModel.getInterstitialRichContent(afterSectionId: $0) },
            onInterstitialContentChange: { afterSectionId, content, richText in
                Task { try? await viewModel.updateInterstitialContent(afterSectionId: afterSectionId, content: content, richText: richText) }
            },
            onInterstitialBackspaceEmpty: { afterSectionId in
                // When backspace on empty interstitial, focus the section it's after
                // If afterSectionId is nil (end interstitial), focus the last section
                if let sectionId = afterSectionId {
                    viewModel.focusedSectionId = sectionId
                } else if let lastSection = viewModel.sections.last {
                    viewModel.focusedSectionId = lastSection.id
                }
            }
        )
    }

    @ViewBuilder
    private func addSectionButton(visibleSections: [Section]) -> some View {
        AddContentBar(onAddText: {
            Task {
                let parentId = möbiusNavigation.currentParentId
                let lastSection = visibleSections.last
                try? await viewModel.addSection(after: lastSection?.id)

                if let parentId = parentId,
                   let newSection = viewModel.sections.last {
                    try? await viewModel.setParentSection(newSection.id, parentId: parentId)
                }
            }
        }, onAddAudio: {
            Task {
                let parentId = möbiusNavigation.currentParentId
                let lastSection = visibleSections.last
                if let section = try? await viewModel.addAudioSection(after: lastSection?.id) {
                    if let parentId = parentId {
                        try? await viewModel.setParentSection(section.id, parentId: parentId)
                    }
                    audioRecorderTargetSectionId = section.id
                    audioRecorderID = UUID()
                    showingAudioRecorder = true
                }
            }
        }, onAddImage: {
            Task {
                let lastSection = visibleSections.last
                if let section = try? await viewModel.addImageSection(after: lastSection?.id) {
                    imagePickerTargetSectionId = section.id
                    imagePickerPreselectedAssetIds = []
                    showingImagePicker = true
                }
            }
        })
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            primaryToolbarItems
        }

        ToolbarItemGroup(placement: .keyboard) {
            keyboardToolbarItems
        }
    }

    @ViewBuilder
    private var primaryToolbarItems: some View {
        if !möbiusNavigation.isAtRoot {
            Button {
                withAnimation(.möbiusUnfold) { möbiusNavigation.popBack() }
            } label: {
                Image(systemName: "arrow.up.left")
            }
        }

        templatesButton
        mainMenu
    }

    @ViewBuilder
    private var templatesButton: some View {
        Button {
            showingTemplates = true
        } label: {
            Image(systemName: "doc.on.doc")
        }
    }

    @ViewBuilder
    private var mainMenu: some View {
        Menu {
            Button {
                Task { try? await viewModel.togglePinned() }
            } label: {
                Label(
                    viewModel.note?.isPinned == true ? "Unpin" : "Pin",
                    systemImage: viewModel.note?.isPinned == true ? "pin.slash" : "pin"
                )
            }

            Divider()

            intentPickerMenu

            Divider()

            Button {
                pageCommitItem = PageCommitItem(noteId: noteId, pageTitle: titleText)
            } label: {
                Label("Commit Page", systemImage: "arrow.down.doc")
            }

            Button {
                Task { await sharePageDirectly() }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                // Delete note with confirmation
            } label: {
                Label("Delete Note", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private var intentPickerMenu: some View {
        Menu {
            ForEach(IntentType.allCases, id: \.self) { intent in
                Button {
                    Task { try? await viewModel.setIntent(intent) }
                } label: {
                    HStack {
                        Image(systemName: intent.icon)
                            .foregroundStyle(intent.color)
                        Text(intent.displayName)
                        if viewModel.note?.intent == intent {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Status", systemImage: "paintpalette")
        }
    }

    @ViewBuilder
    private var keyboardToolbarItems: some View {
        IntentTypeMenu(
            currentIntent: getCurrentSectionIntent(),
            onSelect: { intent in
                if let id = focusedSectionId {
                    Task { try? await viewModel.setSectionIntent(id, intent: intent) }
                }
            }
        )

        Button {
            if let id = focusedSectionId {
                Task { try? await viewModel.outdent(id) }
            }
        } label: {
            Image(systemName: "decrease.indent")
        }

        Button {
            if let id = focusedSectionId {
                Task { try? await viewModel.indent(id) }
            }
        } label: {
            Image(systemName: "increase.indent")
        }

        Spacer()

        Button {
            dismissKeyboard()
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
        }
    }

    private func dismissKeyboard() {
        // Clear SwiftUI focus states
        focusedSectionId = nil
        bodyFocused = false
        titleFocused = false

        // Also dismiss using UIKit for any UITextView instances
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
    
    // MARK: - Helper Methods

    private func getCurrentSectionIntent() -> IntentType {
        guard let id = focusedSectionId,
              let section = viewModel.sections.first(where: { $0.id == id }) else {
            return .idea
        }
        return section.intent
    }

    private func commitNode(sectionId: String, name: String) async {
        do {
            _ = try await appState.commitModule.createNodeCommit(sectionId: sectionId, name: name)
            lastCommitName = name
            showingCommitConfirmation = true
            nodeCommitSectionId = nil

            // Auto-hide after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showingCommitConfirmation = false
            }
        } catch {
            print("Failed to create node commit: \(error)")
        }
    }

    private func sharePageDirectly() async {
        guard let note = viewModel.note else { return }
        let allSections = viewModel.sections

        do {
            let shareLink = try await ShareManager.shared.createLiveShare(
                noteId: noteId,
                note: note,
                sections: allSections
            )
            guard let url = URL(string: shareLink.url) else { return }

            let handles = allSections.compactMap { viewModel.getHandle(for: $0) }
            let payload = ShareManager.shared.buildMessagePayload(
                shareLink: shareLink,
                title: viewModel.displayTitle,
                sections: allSections,
                handles: handles
            )
            payload.writeToSharedDefaults()

            shareURL = url
            shareTitle = viewModel.displayTitle
            sharePreview = allSections.prefix(3).map { $0.content }.joined(separator: "\n")
        } catch {
            shareError = error.localizedDescription
            return
        }

        pendingShare = true
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if pendingShare {
                pendingShare = false
                showingNativeShare = true
            }
        }
    }

    private func createShareLink(for sectionId: String) async {
        guard let section = viewModel.getSection(sectionId) else { return }

        // For image nodes, share the actual images directly
        if section.contentType == .image {
            let hashes = section.content
                .split(separator: ",")
                .map { entry -> String in
                    let parts = entry.split(separator: "|", maxSplits: 1)
                    return String(parts[0]).trimmingCharacters(in: .whitespaces)
                }
                .filter { !$0.isEmpty }

            var images: [UIImage] = []
            for hash in hashes {
                if let data = try? appState.mediaRepository.getMediaData(hash: hash),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }

            guard !images.isEmpty else {
                shareError = "Could not load images"
                return
            }

            shareItems = images

            pendingShare = true
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if pendingShare {
                    pendingShare = false
                    showingNativeShare = true
                }
            }
            return
        }

        // For audio nodes, share the actual audio file
        if section.contentType == .audio {
            let parts = section.content.split(separator: "|", maxSplits: 1)
            let audioHash = parts.count > 0 ? String(parts[0]).trimmingCharacters(in: .whitespaces) : ""

            guard !audioHash.isEmpty,
                  let data = try? appState.mediaRepository.getMediaData(hash: audioHash) else {
                shareError = "Could not load audio"
                return
            }

            // Write to a temp file so the share sheet can attach it
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("obius_audio_\(audioHash.prefix(8)).m4a")
            do {
                try data.write(to: tempURL)
            } catch {
                shareError = "Could not prepare audio for sharing"
                return
            }

            shareItems = [tempURL]

            pendingShare = true
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if pendingShare {
                    pendingShare = false
                    showingNativeShare = true
                }
            }
            return
        }

        // For text nodes, create a share link and share via the activity sheet.
        // Also write a MessageSharePayload so the iMessage extension can render a branded card.
        do {
            guard let note = viewModel.note else { return }
            let allSections = viewModel.sections
            let shareLink = try await ShareManager.shared.createLiveShare(noteId: noteId, note: note, sections: allSections)
            guard let url = URL(string: shareLink.url) else { return }

            // Use node content as the share title, fall back to page title
            let nodePreview = String(section.content.prefix(200))
            let nodeTitleSnippet = String(section.content.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = nodeTitleSnippet.isEmpty ? viewModel.displayTitle : nodeTitleSnippet

            // Gather sections and handles for the message payload
            let sections = allSections
            let handles = sections.compactMap { viewModel.getHandle(for: $0) }

            let payload = ShareManager.shared.buildMessagePayload(
                shareLink: shareLink,
                title: displayTitle,
                sections: [section],
                handles: handles
            )
            payload.writeToSharedDefaults()

            shareURL = url
            shareTitle = displayTitle
            sharePreview = nodePreview
        } catch {
            print("[Share] Failed to create live share link: \(error)")
            shareError = error.localizedDescription
            return
        }

        // Dismiss keyboard first, then present share sheet
        pendingShare = true
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if pendingShare {
                pendingShare = false
                showingNativeShare = true
            }
        }
    }

    private func commitPage(name: String, title: String, comment: String) async {
        do {
            let titleOverride = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let commit = try await appState.commitModule.createCommit(
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

            // Auto-hide after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showingCommitConfirmation = false
            }
        } catch {
            print("Failed to create page commit: \(error)")
        }
    }

    private func postCommitComment(commit: Commit, comment: String) async {
        do {
            let content = try appState.coldStore.readCommit(hash: commit.hash)
            let data = try JSONEncoder().encode(content)
            guard let jsonString = String(data: data, encoding: .utf8) else { return }

            let shareLink = try await ShareManager.shared.createCommitShare(
                commitHash: commit.hash,
                commitName: commit.name,
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

    #if os(iOS)
    /// Compute preselected asset IDs and show the picker.
    /// PHPicker runs out-of-process and handles its own photo library access,
    /// so no app-level authorization is needed for preselection.
    private func prepareAndShowImagePicker(for sectionId: String) {
        if let section = viewModel.getSection(sectionId) {
            let ids = parseImageEntries(from: section.content)
                .compactMap { $0.assetId.isEmpty ? nil : $0.assetId }
            print("[ImagePicker] Preselecting \(ids.count) asset IDs: \(ids)")
            imagePickerPreselectedAssetIds = ids
        } else {
            imagePickerPreselectedAssetIds = []
        }

        // Force a fresh PHPickerViewController so makeUIViewController runs with new config
        imagePickerID = UUID()
        showingImagePicker = true
    }

    /// Extract just the image hashes for a section (for fullscreen viewer).
    private func parseImageHashes(forSectionId sectionId: String) -> [String] {
        guard let section = viewModel.getSection(sectionId) else { return [] }
        return section.content
            .split(separator: ",")
            .map { entry -> String in
                let parts = entry.split(separator: "|", maxSplits: 1)
                return String(parts[0]).trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    /// Parse "hash|assetId,hash|assetId,..." into structured entries.
    private func parseImageEntries(from content: String) -> [(hash: String, assetId: String)] {
        content.split(separator: ",")
            .map { entry in
                let parts = entry.split(separator: "|", maxSplits: 1)
                let hash = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let assetId = parts.count > 1 ? String(parts[1]) : ""
                return (hash: hash, assetId: assetId)
            }
            .filter { !$0.hash.isEmpty }
    }

    private func savePickedImages(_ results: [(UIImage, String?)], toSectionId sectionId: String) async {
        // Keep all existing entries, then append genuinely new picks
        let existingEntries = parseImageEntries(
            from: viewModel.getSection(sectionId)?.content ?? ""
        )

        // Build a set of existing asset IDs and hashes for dedup
        var existingAssetIds = Set<String>()
        var existingHashes = Set<String>()
        for entry in existingEntries {
            existingHashes.insert(entry.hash)
            if !entry.assetId.isEmpty {
                existingAssetIds.insert(entry.assetId)
            }
        }

        // Start with all existing entries
        var newEntries = existingEntries

        for (image, assetId) in results {
            // Skip if this asset is already in the node
            if let assetId, existingAssetIds.contains(assetId) {
                continue
            }

            // New image — store it
            guard let data = image.jpegData(compressionQuality: 0.85) else { continue }
            do {
                let media = try await appState.mediaRepository.addMedia(
                    data: data,
                    filename: "image_\(UUID().uuidString).jpg",
                    mimeType: "image/jpeg"
                )
                // Skip if this exact hash already exists (same image picked without asset ID)
                guard !existingHashes.contains(media.hash) else { continue }
                try await appState.mediaRepository.linkMediaToNote(
                    noteId: noteId,
                    mediaHash: media.hash
                )
                newEntries.append((hash: media.hash, assetId: assetId ?? ""))
                existingHashes.insert(media.hash)
                if let assetId {
                    existingAssetIds.insert(assetId)
                }
            } catch {
                print("Failed to save image: \(error)")
            }
        }

        // Build content string in "hash|assetId" format
        let content = newEntries
            .map { "\($0.hash)|\($0.assetId)" }
            .joined(separator: ",")
        print("[ImagePicker] Saving content: \(content)")
        try? await viewModel.updateSectionContent(sectionId, content: content)
    }

    /// Save after edit sheet — keeps selected existing entries and stores new picks.
    private func saveEditedImages(keptEntries: [(hash: String, assetId: String)], newPicks: [(UIImage, String?)], sectionId: String) async {
        var allEntries = keptEntries

        for (image, assetId) in newPicks {
            guard let data = image.jpegData(compressionQuality: 0.85) else { continue }
            do {
                let media = try await appState.mediaRepository.addMedia(
                    data: data,
                    filename: "image_\(UUID().uuidString).jpg",
                    mimeType: "image/jpeg"
                )
                try await appState.mediaRepository.linkMediaToNote(
                    noteId: noteId,
                    mediaHash: media.hash
                )
                allEntries.append((hash: media.hash, assetId: assetId ?? ""))
            } catch {
                print("Failed to save image: \(error)")
            }
        }

        let content = allEntries
            .map { "\($0.hash)|\($0.assetId)" }
            .joined(separator: ",")
        try? await viewModel.updateSectionContent(sectionId, content: content)
    }
    private func saveRecordedAudio(_ data: Data, duration: TimeInterval, toSectionId sectionId: String) async {
        do {
            let media = try await appState.mediaRepository.addMedia(
                data: data,
                filename: "audio_\(UUID().uuidString).m4a",
                mimeType: "audio/mp4"
            )
            try await appState.mediaRepository.linkMediaToNote(
                noteId: noteId,
                mediaHash: media.hash
            )
            // Store as "hash|duration"
            let content = "\(media.hash)|\(String(format: "%.1f", duration))"
            try await viewModel.updateSectionContent(sectionId, content: content)
        } catch {
            print("Failed to save audio: \(error)")
        }
    }
    #endif

    @ViewBuilder
    private var titleView: some View {
        HStack(spacing: 12) {
            // Intent Rail indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(viewModel.note?.intent.color ?? .blue)
                .frame(width: 4, height: 32)

            if editingTitle {
                TextField("Title", text: $titleText)
                    .font(.title.bold())
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .onSubmit {
                        saveTitle()
                    }
                    .onAppear {
                        titleText = viewModel.note?.title ?? ""
                        // Auto-focus when entering edit mode
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            titleFocused = true
                        }
                    }
                    .onChange(of: titleFocused) { _, isFocused in
                        // Save when focus is lost (user tapped elsewhere)
                        if !isFocused {
                            saveTitle()
                        }
                    }
            } else {
                Text(viewModel.displayTitle)
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        titleText = viewModel.note?.title ?? ""
                        editingTitle = true
                    }
            }

            Spacer()

            if viewModel.note?.isPinned == true {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
            }
        }
        .background {
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .onChange(of: frame.minY) { _, minY in
                        let isVisible = minY > -frame.height
                        if titleVisible != isVisible {
                            titleVisible = isVisible
                        }
                    }
            }
        }
    }

    private func saveTitle() {
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            try? await viewModel.updateTitle(trimmedTitle)
            editingTitle = false
        }
    }

    @ViewBuilder
    private var noteBodyEditor: some View {
        let isPageEmpty = bodyText.isEmpty && viewModel.sections.isEmpty

        #if os(iOS)
        BodyTextView(
            text: $bodyText,
            isFocused: $bodyFocused,
            richText: viewModel.note?.bodyRichText,
            minHeight: isPageEmpty ? 100 : 44,
            onContentChange: { newValue, richText in
                Task {
                    try? await viewModel.updateBody(newValue, richText: richText)
                }
            }
        )
        .frame(minHeight: isPageEmpty ? 100 : 44)
        .padding(.horizontal, 10)
        .overlay(alignment: .topLeading) {
            if isPageEmpty && !bodyFocused {
                Text(emptyPlaceholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            bodyText = viewModel.note?.body ?? ""
        }
        .onChange(of: viewModel.note?.body) { _, newBody in
            if let newBody = newBody, newBody != bodyText {
                bodyText = newBody
            }
        }
        #else
        TextEditor(text: $bodyText)
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: isPageEmpty ? 100 : 22)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 0)
            .focused($bodyFocused)
            .overlay(alignment: .topLeading) {
                if isPageEmpty && !bodyFocused {
                    Text(emptyPlaceholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: bodyText) { _, newValue in
                Task {
                    try? await viewModel.updateBody(newValue)
                }
            }
            .onAppear {
                bodyText = viewModel.note?.body ?? ""
            }
            .onChange(of: viewModel.note?.body) { _, newBody in
                if let newBody = newBody, newBody != bodyText {
                    bodyText = newBody
                }
            }
        #endif
    }
}

// MARK: - Body Text View (iOS)

#if os(iOS)
/// Keyboard toolbar for body text with formatting buttons
private class BodyKeyboardToolbar: UIToolbar {
    weak var textView: UITextView?
    var onDismiss: (() -> Void)?

    private var titleButton: UIBarButtonItem?
    private var boldButton: UIBarButtonItem?
    private var italicButton: UIBarButtonItem?
    private var underlineButton: UIBarButtonItem?

    // Track active formatting states for typing
    private var isTitleActive = false
    private var isBoldActive = false
    private var isItalicActive = false
    private var isUnderlineActive = false

    private var normalFontSize: CGFloat {
        UIFont.preferredFont(forTextStyle: .body).pointSize
    }

    private var titleFontSize: CGFloat {
        UIFont.preferredFont(forTextStyle: .body).pointSize * 2
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupToolbar()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupToolbar()
    }

    convenience init() {
        self.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
    }

    private func setupToolbar() {
        barStyle = .default
        isTranslucent = true
        sizeToFit()

        var items: [UIBarButtonItem] = []

        // Indent/Outdent buttons (visual consistency, disabled for body)
        let outdentButton = UIBarButtonItem(
            image: UIImage(systemName: "decrease.indent"),
            style: .plain,
            target: nil,
            action: nil
        )
        outdentButton.isEnabled = false
        items.append(outdentButton)

        let indentButton = UIBarButtonItem(
            image: UIImage(systemName: "increase.indent"),
            style: .plain,
            target: nil,
            action: nil
        )
        indentButton.isEnabled = false
        items.append(indentButton)

        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        items.append(flexSpace)

        // Title size button
        let title = UIBarButtonItem(
            image: UIImage(systemName: "textformat.size"),
            style: .plain,
            target: self,
            action: #selector(titleTapped)
        )
        titleButton = title
        items.append(title)

        // Formatting buttons
        let bold = UIBarButtonItem(
            image: UIImage(systemName: "bold"),
            style: .plain,
            target: self,
            action: #selector(boldTapped)
        )
        boldButton = bold
        items.append(bold)

        let italic = UIBarButtonItem(
            image: UIImage(systemName: "italic"),
            style: .plain,
            target: self,
            action: #selector(italicTapped)
        )
        italicButton = italic
        items.append(italic)

        let underline = UIBarButtonItem(
            image: UIImage(systemName: "underline"),
            style: .plain,
            target: self,
            action: #selector(underlineTapped)
        )
        underlineButton = underline
        items.append(underline)

        // Add spacing
        let fixedSpace = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpace.width = 12
        items.append(fixedSpace)

        // Dismiss button (far right)
        let dismissButton = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .plain,
            target: self,
            action: #selector(dismissTapped)
        )
        items.append(dismissButton)

        setItems(items, animated: false)
    }

    private func updateButtonAppearance() {
        titleButton?.tintColor = isTitleActive ? .systemPurple : nil
        boldButton?.tintColor = isBoldActive ? .systemPurple : nil
        italicButton?.tintColor = isItalicActive ? .systemPurple : nil
        underlineButton?.tintColor = isUnderlineActive ? .systemPurple : nil
    }

    /// Sync button states with the text view's current typing attributes
    func syncWithTypingAttributes() {
        guard let textView = textView else { return }
        let attrs = textView.typingAttributes
        let font = (attrs[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
        let traits = font.fontDescriptor.symbolicTraits

        isTitleActive = font.pointSize >= titleFontSize && traits.contains(.traitBold)
        // Bold button only shows active if bold was set independently (not just from title)
        isBoldActive = traits.contains(.traitBold) && !isTitleActive
        isItalicActive = traits.contains(.traitItalic)
        isUnderlineActive = (attrs[.underlineStyle] as? Int) != nil && (attrs[.underlineStyle] as? Int) != 0

        updateButtonAppearance()
    }

    @objc private func titleTapped() {
        guard let textView = textView else { return }
        isTitleActive.toggle()
        let range = textView.selectedRange

        if range.length > 0 {
            let mutableAttrString = NSMutableAttributedString(attributedString: textView.attributedText)
            mutableAttrString.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let currentFont = (value as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
                let size = isTitleActive ? titleFontSize : normalFontSize
                var traits = currentFont.fontDescriptor.symbolicTraits
                if isTitleActive { traits.insert(.traitBold) }
                if let desc = currentFont.fontDescriptor.withSymbolicTraits(traits) {
                    let newFont = UIFont(descriptor: desc, size: size)
                    mutableAttrString.addAttribute(.font, value: newFont, range: subRange)
                }
            }
            textView.attributedText = mutableAttrString
            textView.selectedRange = range
            notifyContentChanged()
        } else {
            var attrs = textView.typingAttributes
            let currentFont = (attrs[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
            let size = isTitleActive ? titleFontSize : normalFontSize
            var traits = currentFont.fontDescriptor.symbolicTraits
            if isTitleActive { traits.insert(.traitBold) } else if !isBoldActive { traits.remove(.traitBold) }
            if let desc = currentFont.fontDescriptor.withSymbolicTraits(traits) {
                attrs[.font] = UIFont(descriptor: desc, size: size)
                textView.typingAttributes = attrs
            }
        }

        updateButtonAppearance()
    }

    @objc private func boldTapped() {
        guard let textView = textView else { return }
        let range = textView.selectedRange

        if range.length > 0 {
            applyFontTraitToSelection(.traitBold, in: textView)
        } else {
            isBoldActive.toggle()
            applyFontTraitToTyping(.traitBold, isActive: isBoldActive, in: textView)
        }
        updateButtonAppearance()
    }

    @objc private func italicTapped() {
        guard let textView = textView else { return }
        let range = textView.selectedRange

        if range.length > 0 {
            applyFontTraitToSelection(.traitItalic, in: textView)
        } else {
            isItalicActive.toggle()
            applyFontTraitToTyping(.traitItalic, isActive: isItalicActive, in: textView)
        }
        updateButtonAppearance()
    }

    @objc private func underlineTapped() {
        guard let textView = textView else { return }
        let range = textView.selectedRange

        if range.length > 0 {
            let mutableAttrString = NSMutableAttributedString(attributedString: textView.attributedText)

            var isUnderlined = false
            mutableAttrString.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
                if let style = value as? Int, style != 0 {
                    isUnderlined = true
                }
            }

            if isUnderlined {
                mutableAttrString.removeAttribute(.underlineStyle, range: range)
            } else {
                mutableAttrString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }

            textView.attributedText = mutableAttrString
            textView.selectedRange = range
            notifyContentChanged()
        } else {
            isUnderlineActive.toggle()
            var attrs = textView.typingAttributes
            if isUnderlineActive {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                attrs.removeValue(forKey: .underlineStyle)
            }
            textView.typingAttributes = attrs
        }
        updateButtonAppearance()
    }

    private func applyFontTraitToSelection(_ trait: UIFontDescriptor.SymbolicTraits, in textView: UITextView) {
        let range = textView.selectedRange
        guard range.length > 0 else { return }

        let mutableAttrString = NSMutableAttributedString(attributedString: textView.attributedText)

        mutableAttrString.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let currentFont = (value as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
            var newTraits = currentFont.fontDescriptor.symbolicTraits

            if newTraits.contains(trait) {
                newTraits.remove(trait)
            } else {
                newTraits.insert(trait)
            }

            if let newDescriptor = currentFont.fontDescriptor.withSymbolicTraits(newTraits) {
                let newFont = UIFont(descriptor: newDescriptor, size: currentFont.pointSize)
                mutableAttrString.addAttribute(.font, value: newFont, range: subRange)
            }
        }

        textView.attributedText = mutableAttrString
        textView.selectedRange = range
        notifyContentChanged()
    }

    private func applyFontTraitToTyping(_ trait: UIFontDescriptor.SymbolicTraits, isActive: Bool, in textView: UITextView) {
        var attrs = textView.typingAttributes
        let currentFont = (attrs[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
        var newTraits = currentFont.fontDescriptor.symbolicTraits

        if isActive {
            newTraits.insert(trait)
        } else {
            newTraits.remove(trait)
        }

        if let newDescriptor = currentFont.fontDescriptor.withSymbolicTraits(newTraits) {
            let newFont = UIFont(descriptor: newDescriptor, size: currentFont.pointSize)
            attrs[.font] = newFont
            textView.typingAttributes = attrs
        }
    }

    /// Notify the delegate that content changed so rich text formatting is persisted.
    /// UIKit does NOT call textViewDidChange when attributedText is set programmatically,
    /// so we must trigger the save manually after formatting changes.
    private func notifyContentChanged() {
        guard let textView = textView else { return }
        textView.delegate?.textViewDidChange?(textView)
    }

    @objc private func dismissTapped() {
        onDismiss?()
    }
}

/// UITextView wrapper for the note body with formatting toolbar
struct BodyTextView: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var richText: String?
    let minHeight: CGFloat
    let onContentChange: (String, String?) -> Void

    func makeUIView(context: Context) -> SelfSizingTextView {
        // Use SelfSizingTextView which has proper single-tap handling
        let textView = SelfSizingTextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)

        // Add keyboard accessory toolbar
        let toolbar = BodyKeyboardToolbar()
        toolbar.textView = textView
        toolbar.onDismiss = { [weak textView] in
            textView?.resignFirstResponder()
        }
        textView.inputAccessoryView = toolbar

        // Load rich text if available on initial creation
        if let richText = richText,
           let attrText = RichTextHelper.deserialize(richText) {
            textView.attributedText = attrText
        }

        return textView
    }

    func updateUIView(_ textView: SelfSizingTextView, context: Context) {
        if !textView.isFirstResponder, textView.text != text {
            if let richText = richText,
               let attrText = RichTextHelper.deserialize(richText) {
                textView.attributedText = attrText
            } else {
                textView.text = text
            }
        }
        textView.invalidateIntrinsicContentSize()

        if isFocused.wrappedValue && !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: BodyTextView

        init(_ parent: BodyTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = true
            // Sync toolbar button states with current typing attributes
            if let toolbar = textView.inputAccessoryView as? BodyKeyboardToolbar {
                toolbar.syncWithTypingAttributes()
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = false
            // Save rich text formatting when focus leaves
            let richText = RichTextHelper.serialize(textView.attributedText)
            parent.onContentChange(textView.text ?? "", richText)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Sync toolbar button states when cursor moves
            if let toolbar = textView.inputAccessoryView as? BodyKeyboardToolbar {
                toolbar.syncWithTypingAttributes()
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            let richText = RichTextHelper.serialize(textView.attributedText)
            if parent.text != newText {
                parent.text = newText
            }
            parent.onContentChange(newText, richText)
            textView.invalidateIntrinsicContentSize()
        }
    }
}
#endif

// MARK: - NodeCommitItem

/// Identifiable wrapper for presenting node commit sheet.
struct NodeCommitItem: Identifiable {
    let id = UUID()
    let sectionId: String
}

// MARK: - NodeCommitSheet

/// Sheet for naming a node commit before saving.
struct NodeCommitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    let sectionId: String
    let onCommit: (String) -> Void

    @State private var commitName = ""
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(.secondary)

                Spacer()

                Text("Commit Node")
                    .font(.headline)

                Spacer()

                Button("Save") {
                    saveCommit()
                }
                .fontWeight(.semibold)
                .disabled(commitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.top, 16)

            // Name input
            VStack(alignment: .leading, spacing: 8) {
                Text("Node Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Enter name", text: $commitName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFocused)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit {
                            saveCommit()
                        }

                    Text(".obx")
                        .foregroundStyle(.secondary)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .presentationDetents([.height(180)])
        .onAppear {
            isNameFocused = true
        }
    }

    private func saveCommit() {
        let trimmedName = commitName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a name"
            return
        }

        // Check if name is available
        if !appState.commitModule.isNodeNameAvailable(trimmedName) {
            errorMessage = "A node with this name already exists"
            return
        }

        onCommit(trimmedName)
        dismiss()
    }
}

// MARK: - PageCommitItem

/// Identifiable wrapper for presenting page commit sheet.
struct PageCommitItem: Identifiable {
    let id = UUID()
    let noteId: String
    let pageTitle: String
}

// MARK: - PageCommitSheet

/// Sheet for naming a page commit before saving.
struct PageCommitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    let noteId: String
    let pageTitle: String
    let onCommit: (String, String, String) -> Void

    @State private var commitTitle = ""
    @State private var commitName = ""
    @State private var commitComment = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case title, name, comment }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(.secondary)

                Spacer()

                Text("Commit Page")
                    .font(.headline)

                Spacer()

                Button("Save") {
                    saveCommit()
                }
                .fontWeight(.semibold)
                .disabled(commitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.top, 16)

            // Title input
            VStack(alignment: .leading, spacing: 4) {
                Text("Commit Title")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Enter title", text: $commitTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .title)
                    .onSubmit {
                        focusedField = .name
                    }
            }
            .padding(.horizontal)

            // File name input
            VStack(alignment: .leading, spacing: 4) {
                Text("File Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Enter name", text: $commitName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit {
                            focusedField = .comment
                        }

                    Text(".obx")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            // Comment input
            VStack(alignment: .leading, spacing: 4) {
                Text("Comment")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Add a comment (optional)", text: $commitComment)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .comment)
                    .onSubmit {
                        saveCommit()
                    }
            }
            .padding(.horizontal)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .presentationDetents([.height(340)])
        .onAppear {
            commitTitle = pageTitle
            focusedField = .title
        }
    }

    private func saveCommit() {
        let trimmedName = commitName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a file name"
            return
        }

        onCommit(trimmedName, commitTitle, commitComment)
        dismiss()
    }
}

// MARK: - Add Content Bar

struct AddContentBar: View {
    let onAddText: () -> Void
    let onAddAudio: () -> Void
    let onAddImage: () -> Void

    @State private var isExpanded = false

    var body: some View {
        Group {
            if isExpanded {
                HStack(spacing: 24) {
                    Button {
                        onAddAudio()
                        withAnimation(.easeOut(duration: 0.2)) { isExpanded = false }
                    } label: {
                        Image(systemName: "waveform")
                            .font(.title3)
                            .foregroundStyle(Color(.systemBackground))
                            .frame(width: 44, height: 44)
                            .background(Color.gray.opacity(0.5))
                            .clipShape(Circle())
                    }

                    Button {
                        onAddText()
                        withAnimation(.easeOut(duration: 0.2)) { isExpanded = false }
                    } label: {
                        Image(systemName: "character.textbox")
                            .font(.title3)
                            .foregroundStyle(Color(.systemBackground))
                            .frame(width: 44, height: 44)
                            .background(Color.gray.opacity(0.5))
                            .clipShape(Circle())
                    }

                    Button {
                        onAddImage()
                        withAnimation(.easeOut(duration: 0.2)) { isExpanded = false }
                    } label: {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(Color(.systemBackground))
                            .frame(width: 44, height: 44)
                            .background(Color.gray.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { isExpanded = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(width: 28, height: 28)
                        .background(Color.gray.opacity(0.5))
                        .clipShape(Circle())
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            if isExpanded {
                withAnimation(.easeOut(duration: 0.2)) { isExpanded = false }
            }
        }
    }
}

#Preview {
    NavigationStack {
        NoteEditorView(noteId: "preview")
    }
    .environmentObject(AppState())
}
