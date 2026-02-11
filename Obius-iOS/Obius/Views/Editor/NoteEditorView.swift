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
    @FocusState private var focusedSectionId: String?
    @FocusState private var bodyFocused: Bool
    @FocusState private var titleFocused: Bool

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
                    onCommit: { name in
                        Task {
                            await commitPage(name: name)
                        }
                    }
                )
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
                // When focus changes, scroll to show the top of the focused section
                if let sectionId = newId {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(sectionId, anchor: .top)
                    }
                }
            }
            .onChange(of: viewModel.sections.count) { _, _ in
                // When a new section appears, scroll to it if it's the focus target
                if let sectionId = viewModel.focusedSectionId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(sectionId, anchor: .top)
                        }
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
            titleView
                .padding(.horizontal)

            noteBodyEditor
                .padding(.horizontal)
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
            getInterstitialContent: { viewModel.getInterstitialContent(afterSectionId: $0) },
            onInterstitialContentChange: { afterSectionId, content in
                Task { try? await viewModel.updateInterstitialContent(afterSectionId: afterSectionId, content: content) }
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
        .padding(.vertical, 4)
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
                pageCommitItem = PageCommitItem(noteId: noteId)
            } label: {
                Label("Commit Page", systemImage: "arrow.down.doc")
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

    private func commitPage(name: String) async {
        do {
            _ = try await appState.commitModule.createCommit(noteId: noteId, name: name)
            lastCommitName = name
            showingCommitConfirmation = true
            pageCommitItem = nil

            // Auto-hide after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showingCommitConfirmation = false
            }
        } catch {
            print("Failed to create page commit: \(error)")
        }
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
            minHeight: isPageEmpty ? 100 : 22,
            onContentChange: { newValue in
                Task {
                    try? await viewModel.updateBody(newValue)
                }
            }
        )
        .padding(.horizontal, 10)
        .overlay(alignment: .topLeading) {
            if isPageEmpty && !bodyFocused {
                Text("Start typing...")
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
                    Text("Start typing...")
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

    @objc private func dismissTapped() {
        onDismiss?()
    }
}

/// UITextView wrapper for the note body with formatting toolbar
struct BodyTextView: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let minHeight: CGFloat
    let onContentChange: (String) -> Void

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

        return textView
    }

    func updateUIView(_ textView: SelfSizingTextView, context: Context) {
        if textView.text != text {
            textView.text = text
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
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Sync toolbar button states when cursor moves
            if let toolbar = textView.inputAccessoryView as? BodyKeyboardToolbar {
                toolbar.syncWithTypingAttributes()
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            // Only update binding if text actually changed (prevents loop when only formatting changes)
            if parent.text != newText {
                parent.text = newText
                parent.onContentChange(newText)
            }
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
}

// MARK: - PageCommitSheet

/// Sheet for naming a page commit before saving.
struct PageCommitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    let noteId: String
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

            // Name input
            VStack(alignment: .leading, spacing: 8) {
                Text("Commit Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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

        onCommit(trimmedName)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        NoteEditorView(noteId: "preview")
    }
    .environmentObject(AppState())
}
