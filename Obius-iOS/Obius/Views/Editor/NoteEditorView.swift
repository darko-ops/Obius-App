import SwiftUI

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

// MARK: - Inner Content View
private struct NoteEditorContent: View {
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
    @FocusState private var focusedSectionId: String?
    @FocusState private var bodyFocused: Bool

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
            .navigationTitle(viewModel.displayTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .onChange(of: viewModel.focusedSectionId) { _, newValue in
                focusedSectionId = newValue
            }
            .onChange(of: focusedSectionId) { _, newValue in
                if viewModel.focusedSectionId != newValue {
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
                    onCreateNew: { name in
                        guard let sectionId = handleSheetSectionId else { return }
                        Task {
                            do {
                                _ = try await viewModel.promoteToHandle(sectionId: sectionId, handleName: name)
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

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerContent(currentParent: currentParent, nonEmptySectionsEmpty: nonEmptySections.isEmpty)

                sectionListView(nonEmptySections: nonEmptySections, visibleSections: visibleSections)
                    .padding(.horizontal)

                addSectionButton(visibleSections: visibleSections)

                Spacer(minLength: 150)
            }
            .padding(.vertical)
        }
    }

    private func filterNonEmptySections(_ sections: [Section]) -> [Section] {
        sections.filter { section in
            let isEmpty = section.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isFocused = viewModel.focusedSectionId == section.id
            return !isEmpty || isFocused
        }
    }

    @ViewBuilder
    private func headerContent(currentParent: Section?, nonEmptySectionsEmpty: Bool) -> some View {
        if möbiusNavigation.isAtRoot {
            titleView
                .padding(.horizontal)

            noteBodyEditor
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, nonEmptySectionsEmpty ? 0 : 16)
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
            onContentChange: { id, content in
                Task { try? await viewModel.updateDisplayContent(id, content: content) }
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
                Task { _ = await biometricManager.authenticate(for: id) }
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
            getInterstitialContent: { viewModel.getInterstitialContent(afterSectionId: $0) },
            onInterstitialContentChange: { afterSectionId, content in
                Task { try? await viewModel.updateInterstitialContent(afterSectionId: afterSectionId, content: content) }
            }
        )
    }

    @ViewBuilder
    private func addSectionButton(visibleSections: [Section]) -> some View {
        Button {
            Task {
                let parentId = möbiusNavigation.currentParentId
                let lastSection = visibleSections.last
                try? await viewModel.addSection(after: lastSection?.id)

                if let parentId = parentId,
                   let newSection = viewModel.sections.last {
                    try? await viewModel.setParentSection(newSection.id, parentId: parentId)
                }
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
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
            Label("Intent", systemImage: "paintpalette")
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
            focusedSectionId = nil
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
        }
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentSectionIntent() -> IntentType {
        guard let id = focusedSectionId,
              let section = viewModel.sections.first(where: { $0.id == id }) else {
            return .idea
        }
        return section.intent
    }

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
                    .onSubmit {
                        Task {
                            try? await viewModel.updateTitle(titleText)
                            editingTitle = false
                        }
                    }
                    .onAppear {
                        titleText = viewModel.note?.title ?? ""
                    }
            } else {
                Text(viewModel.displayTitle)
                    .font(.title.bold())
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
    }

    @ViewBuilder
    private var noteBodyEditor: some View {
        let isPageEmpty = bodyText.isEmpty && viewModel.sections.isEmpty

        TextEditor(text: $bodyText)
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: isPageEmpty ? 100 : 40)
            .fixedSize(horizontal: false, vertical: true)
            .focused($bodyFocused)
            .overlay(alignment: .topLeading) {
                // Only show placeholder when page is completely empty
                if isPageEmpty && !bodyFocused {
                    Text("Start typing...")
                        .font(.body)
                        .foregroundStyle(.tertiary)
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
    }
}

#Preview {
    NavigationStack {
        NoteEditorView(noteId: "preview")
    }
    .environmentObject(AppState())
}
