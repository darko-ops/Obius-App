import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var handleManager = HandleManager.shared
    @StateObject private var echoManager = EchoManager.shared
    @State private var selectedSection: LibrarySection = .commits
    @State private var searchQuery = ""
    @State private var showingSettings = false
    @State private var showingEditProfile = false
    @State private var selectedEcho: Echo?
    @StateObject private var profileImages = ProfileImageManager.shared

    enum LibrarySection: String, CaseIterable {
        case loops = "Loops"
        case commits = "Commits"
        case templates = "Templates"

        var icon: String {
            switch self {
            case .loops: return "link"
            case .templates: return "doc.on.doc"
            case .commits: return "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // User Profile Section
                userProfileSection

                // Active Echoes
                if !echoManager.activeEchoes.isEmpty {
                    activeEchoesSection
                }

                Divider()
                    .padding(.horizontal)

                // Search bar
                RoundedSearchBar(text: $searchQuery, placeholder: "Search \(selectedSection.rawValue.lowercased())")
                    .padding(.horizontal)

                // Section picker
                Picker("Section", selection: $selectedSection) {
                    ForEach(LibrarySection.allCases, id: \.self) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Content
                switch selectedSection {
                case .loops:
                    LoopsListView(searchQuery: searchQuery)
                case .templates:
                    TemplatesListView(searchQuery: searchQuery)
                case .commits:
                    CommitsListView(searchQuery: searchQuery)
                }
            }
            .padding(.bottom)
        }
        .background(Color.black)
        .ignoresSafeArea(.container, edges: .top)
        .navigationBarHidden(true)
        .onChange(of: selectedSection) { _, _ in
            searchQuery = ""
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
            .environmentObject(AppearanceManager.shared)
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
                .environmentObject(authManager)
        }
        .sheet(item: $selectedEcho) { echo in
            EchoDetailSheet(echo: echo)
        }
    }

    // MARK: - Active Echoes Section

    private var activeEchoesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Active Echoes")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(echoManager.activeEchoes.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)

            ForEach(echoManager.activeEchoes) { echo in
                EchoRowView(echo: echo)
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if echo.isAlerted {
                            Task {
                                try? await echoManager.acknowledgeEcho(id: echo.id)
                            }
                        }
                        selectedEcho = echo
                    }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - User Profile Section

    private var userProfileSection: some View {
        VStack(spacing: 0) {
            // Banner — extends to very top of screen
            ZStack(alignment: .bottom) {
                // Settings button at bottom-right of banner
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 16)
                .padding(.bottom, 8)
                .zIndex(1)
                GeometryReader { geo in
                    let minY = geo.frame(in: .global).minY
                    let extraHeight = max(minY, 0)

                    if let banner = profileImages.bannerImage {
                        Image(uiImage: banner)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: 160 + extraHeight)
                            .clipped()
                            .offset(y: -extraHeight)
                    } else {
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: geo.size.width, height: 160 + extraHeight)
                        .offset(y: -extraHeight)
                    }
                }
                .frame(height: 160)

                // Profile avatar overlapping the banner
                profileAvatar
                    .offset(y: 40)
            }

            // User info
            VStack(spacing: 4) {
                if authManager.isAuthenticated, let user = authManager.currentUser {
                    Text(user.displayName ?? "User")
                        .font(.title3.weight(.semibold))

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Text(user.email ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not Signed In")
                        .font(.title3.weight(.semibold))

                    Text("Sign in to sync your notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 48)
        }
        .frame(maxWidth: .infinity)
    }

    private var profileAvatar: some View {
        ZStack {
            if let avatar = profileImages.profileImage {
                Image(uiImage: avatar)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                    .overlay {
                        if authManager.isAuthenticated {
                            Text(userInitials)
                                .font(.title.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Image(systemName: "person.fill")
                                .font(.title)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
            }
        }
        .contentShape(Circle())
        .onTapGesture {
            showingEditProfile = true
        }
    }

    private var userInitials: String {
        guard let name = authManager.currentUser?.displayName else { return "?" }
        let components = name.components(separatedBy: " ")
        let initials = components.compactMap { $0.first }.prefix(2)
        return String(initials).uppercased()
    }
}

// MARK: - Loops List View

struct LoopsListView: View {
    @StateObject private var handleManager = HandleManager.shared
    @State private var showingCreateSheet = false
    @State private var selectedHandle: Handle?
    var searchQuery: String = ""

    private var filteredHandles: [Handle] {
        if searchQuery.isEmpty {
            return handleManager.handles
        }
        return handleManager.handles.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery) ||
            $0.preview.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header with add button
            HStack {
                Image(systemName: "infinity")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.gray)
                }
            }
            .padding(.horizontal)

            if handleManager.handles.isEmpty {
                emptyState
            } else if filteredHandles.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                loopsList
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateLoopSheet()
        }
        .sheet(item: $selectedHandle) { handle in
            LoopDetailSheet(handle: handle)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "link")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Loops")
                .font(.headline)
            Text("Loops sync content across sections")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var loopsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredHandles) { handle in
                LoopRowView(handle: handle)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.06))
                    .cornerRadius(12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedHandle = handle
                    }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Loop Row View

struct LoopRowView: View {
    let handle: Handle

    private static let handleColor = Color(red: 0.72, green: 0.32, blue: 0.82)

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(handle.formattedName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Self.handleColor)

                if !handle.preview.isEmpty {
                    Text(handle.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Loop Sheet

struct CreateLoopSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var handleManager = HandleManager.shared
    @State private var name = ""
    @State private var content = ""
    @State private var intent: IntentType = .idea
    @State private var errorMessage: String?

    private var isValid: Bool {
        Handle.validateName(name) == nil && !handleManager.handleExists(name: name)
    }

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section("Name") {
                    HStack {
                        Text("@")
                            .foregroundStyle(.secondary)
                        TextField("LoopName", text: $name)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                    }

                    if let error = Handle.validateName(name), !name.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if handleManager.handleExists(name: name) {
                        Text("This name is already taken")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                SwiftUI.Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 100)
                }

                SwiftUI.Section("Intent") {
                    Picker("Intent", selection: $intent) {
                        ForEach(IntentType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("Create Loop")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createLoop()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func createLoop() {
        Task {
            do {
                _ = try await handleManager.createHandle(name: name, content: content, intent: intent)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Loop Detail Sheet

struct LoopDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let handle: Handle

    @StateObject private var handleManager = HandleManager.shared
    @State private var content: String
    @State private var intent: IntentType

    init(handle: Handle) {
        self.handle = handle
        _content = State(initialValue: handle.content)
        _intent = State(initialValue: handle.intent)
    }

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section("Loop") {
                    Text(handle.formattedName)
                        .font(.headline)
                }

                SwiftUI.Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                }

                SwiftUI.Section("Intent") {
                    Picker("Intent", selection: $intent) {
                        ForEach(IntentType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                SwiftUI.Section("Actions") {
                    Button(role: .destructive) {
                        deleteLoop()
                    } label: {
                        Label("Delete Loop", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit Loop")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
        }
    }

    private func saveChanges() {
        Task {
            try? await handleManager.updateContent(handleId: handle.id, content: content)
            dismiss()
        }
    }

    private func deleteLoop() {
        Task {
            try? await handleManager.deleteHandle(id: handle.id)
            dismiss()
        }
    }
}

// MARK: - Templates List View

struct TemplatesListView: View {
    @StateObject private var templateManager = TemplateManager.shared
    @State private var showingNodeCreator = false
    @State private var showingPageCreator = false
    @State private var selectedTemplate: SectionTemplate?
    @State private var nodeTemplatesCollapsed = false
    @State private var pageTemplatesCollapsed = false
    var searchQuery: String = ""

    private var filteredNodeTemplates: [SectionTemplate] {
        if searchQuery.isEmpty {
            return templateManager.nodeTemplates
        }
        return templateManager.nodeTemplates.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var filteredPageTemplates: [SectionTemplate] {
        if searchQuery.isEmpty {
            return templateManager.pageTemplates
        }
        return templateManager.pageTemplates.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var hasAnyResults: Bool {
        !filteredNodeTemplates.isEmpty || !filteredPageTemplates.isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header with add button
            HStack {
                Image(systemName: "doc.on.doc")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button {
                        showingNodeCreator = true
                    } label: {
                        Label("Node Template", systemImage: TemplateType.node.icon)
                    }

                    Button {
                        showingPageCreator = true
                    } label: {
                        Label("Page Template", systemImage: TemplateType.page.icon)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.gray)
                }
            }
            .padding(.horizontal)

            if templateManager.templates.isEmpty {
                emptyState
            } else if !hasAnyResults {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                templatesList
            }
        }
        .sheet(isPresented: $showingNodeCreator) {
            CreateNodeTemplateSheet()
        }
        .sheet(isPresented: $showingPageCreator) {
            CreatePageTemplateSheet()
        }
        .sheet(item: $selectedTemplate) { template in
            EditTemplateSheet(template: template)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.doc")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Templates")
                .font(.headline)
            Text("Create structured nodes or pages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var templatesList: some View {
        LazyVStack(spacing: 16) {
            // Node Templates
            if !filteredNodeTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    CollapsibleTemplateHeader(
                        title: "Node Templates",
                        icon: TemplateType.node.icon,
                        count: filteredNodeTemplates.count,
                        isCollapsed: $nodeTemplatesCollapsed
                    )
                    .padding(.horizontal)

                    if !nodeTemplatesCollapsed {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredNodeTemplates) { template in
                                TemplateRowView(template: template)
                                    .padding(.horizontal)
                                    .padding(.vertical, 12)
                                    .background(Color(white: 0.06))
                                    .cornerRadius(12)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedTemplate = template
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }

            // Page Templates
            if !filteredPageTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    CollapsibleTemplateHeader(
                        title: "Page Templates",
                        icon: TemplateType.page.icon,
                        count: filteredPageTemplates.count,
                        isCollapsed: $pageTemplatesCollapsed
                    )
                    .padding(.horizontal)

                    if !pageTemplatesCollapsed {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredPageTemplates) { template in
                                TemplateRowView(template: template)
                                    .padding(.horizontal)
                                    .padding(.vertical, 12)
                                    .background(Color(white: 0.06))
                                    .cornerRadius(12)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedTemplate = template
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }
}

// MARK: - Collapsible Template Header

struct CollapsibleTemplateHeader: View {
    let title: String
    let icon: String
    let count: Int
    @Binding var isCollapsed: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed.toggle()
            }
        } label: {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text("(\(count))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Template Row View

struct TemplateRowView: View {
    let template: SectionTemplate

    private var previewText: String {
        if template.templateType == .node {
            // Show content preview for node templates
            return template.sections.first?.content ?? ""
        } else {
            // Show node count for page templates
            let count = template.sections.count
            return "\(count) \(count == 1 ? "node" : "nodes")"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: template.templateType.icon)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.headline)

                if !previewText.isEmpty {
                    Text(previewText)
                        .font(.caption)
                        .fontWeight(template.templateType == .node ? .bold : .regular)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Template Sheet

struct CreateTemplateSheet: View {
    let templateType: TemplateType

    var body: some View {
        if templateType == .node {
            CreateNodeTemplateSheet()
        } else {
            CreatePageTemplateSheet()
        }
    }
}

// MARK: - Create Node Template Sheet

struct CreateNodeTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateManager = TemplateManager.shared

    @State private var name = ""
    @State private var content = ""
    @State private var intent: IntentType = .idea

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section("Title") {
                    TextField("Template Name", text: $name)
                }

                SwiftUI.Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                        .fontWeight(.bold)
                }

                SwiftUI.Section("Intent") {
                    Picker("Intent", selection: $intent) {
                        ForEach(IntentType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("Create Node Template")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTemplate()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func createTemplate() {
        let node = TemplateSectionItem(itemType: .node, content: content, intent: intent)
        let template = SectionTemplate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            templateType: .node,
            sections: [node]
        )
        templateManager.addTemplate(template)
        dismiss()
    }
}

// MARK: - Create Page Template Sheet

struct CreatePageTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateManager = TemplateManager.shared

    @State private var name = ""
    @State private var items: [TemplateSectionItem] = []
    @State private var editingItemId: String?

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Title field
                HStack {
                    TextField("Page Template Name", text: $name)
                        .font(.title2.weight(.semibold))
                        .padding()
                }
                .background(Color(white: 0.06))

                Divider()

                // Page editor area
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Insert point at the beginning
                        InsertItemButton { itemType in
                            insertItem(at: 0, type: itemType)
                        }

                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            // Item row
                            PageTemplateItemRow(
                                item: bindingForItem(item),
                                isEditing: editingItemId == item.id,
                                onTap: { editingItemId = item.id },
                                onDelete: { deleteItem(item) }
                            )

                            // Insert point after each item
                            InsertItemButton { itemType in
                                insertItem(at: index + 1, type: itemType)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Create Page Template")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTemplate()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func bindingForItem(_ item: TemplateSectionItem) -> Binding<TemplateSectionItem> {
        Binding(
            get: { items.first { $0.id == item.id } ?? item },
            set: { newValue in
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = newValue
                }
            }
        )
    }

    private func insertItem(at index: Int, type: TemplateItemType) {
        let newItem = TemplateSectionItem(itemType: type, content: "", intent: .idea)
        items.insert(newItem, at: index)
        editingItemId = newItem.id
    }

    private func deleteItem(_ item: TemplateSectionItem) {
        items.removeAll { $0.id == item.id }
    }

    private func createTemplate() {
        let template = SectionTemplate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            templateType: .page,
            sections: items
        )
        templateManager.addTemplate(template)
        dismiss()
    }
}

// MARK: - Insert Item Button

struct InsertItemButton: View {
    let onInsert: (TemplateItemType) -> Void
    @State private var isExpanded = false

    var body: some View {
        HStack {
            Spacer()

            if isExpanded {
                HStack(spacing: 12) {
                    Button {
                        onInsert(.node)
                        isExpanded = false
                    } label: {
                        Label("Node", systemImage: TemplateItemType.node.icon)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(16)
                    }

                    Button {
                        onInsert(.line)
                        isExpanded = false
                    } label: {
                        Label("Line", systemImage: TemplateItemType.line.icon)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16)
                    }

                    Button {
                        isExpanded = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }

            Spacer()
        }
        .frame(height: 32)
        .padding(.horizontal)
    }
}

// MARK: - Page Template Item Row

struct PageTemplateItemRow: View {
    @Binding var item: TemplateSectionItem
    let isEditing: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Item type indicator
            Image(systemName: item.itemType.icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                if isEditing {
                    // Editable content
                    TextEditor(text: $item.content)
                        .frame(minHeight: item.itemType == .node ? 60 : 32)
                        .fontWeight(.bold)
                        .scrollContentBackground(.hidden)

                    // Intent picker (only for nodes)
                    if item.itemType == .node {
                        Picker("Intent", selection: $item.intent) {
                            ForEach(IntentType.allCases, id: \.self) { type in
                                Label(type.displayName, systemImage: type.icon)
                                    .tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } else {
                    // Display content
                    Text(item.content.isEmpty ? "Tap to edit..." : item.content)
                        .fontWeight(.bold)
                        .foregroundStyle(item.content.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()

            // Delete button
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(item.itemType == .node ? Color.gray.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .padding(.horizontal)
    }
}

// MARK: - Edit Template Sheet

struct EditTemplateSheet: View {
    let template: SectionTemplate

    var body: some View {
        if template.templateType == .node {
            EditNodeTemplateSheet(template: template)
        } else {
            EditPageTemplateSheet(template: template)
        }
    }
}

// MARK: - Edit Node Template Sheet

struct EditNodeTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateManager = TemplateManager.shared
    let template: SectionTemplate

    @State private var name: String
    @State private var content: String
    @State private var intent: IntentType

    init(template: SectionTemplate) {
        self.template = template
        _name = State(initialValue: template.name)
        _content = State(initialValue: template.sections.first?.content ?? "")
        _intent = State(initialValue: template.sections.first?.intent ?? .idea)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section("Title") {
                    TextField("Template Name", text: $name)
                }

                SwiftUI.Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                        .fontWeight(.bold)
                }

                SwiftUI.Section("Intent") {
                    Picker("Intent", selection: $intent) {
                        ForEach(IntentType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                SwiftUI.Section {
                    Button(role: .destructive) {
                        deleteTemplate()
                    } label: {
                        Label("Delete Template", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit Node Template")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTemplate()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func saveTemplate() {
        let node = TemplateSectionItem(
            id: template.sections.first?.id ?? UUID().uuidString,
            itemType: .node,
            content: content,
            intent: intent
        )
        var updated = template
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.sections = [node]
        templateManager.updateTemplate(updated)
        dismiss()
    }

    private func deleteTemplate() {
        templateManager.deleteTemplate(template.id)
        dismiss()
    }
}

// MARK: - Edit Page Template Sheet

struct EditPageTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateManager = TemplateManager.shared
    let template: SectionTemplate

    @State private var name: String
    @State private var items: [TemplateSectionItem]
    @State private var editingItemId: String?

    init(template: SectionTemplate) {
        self.template = template
        _name = State(initialValue: template.name)
        _items = State(initialValue: template.sections)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Title field
                HStack {
                    TextField("Page Template Name", text: $name)
                        .font(.title2.weight(.semibold))
                        .padding()
                }
                .background(Color(white: 0.06))

                Divider()

                // Page editor area
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Insert point at the beginning
                        InsertItemButton { itemType in
                            insertItem(at: 0, type: itemType)
                        }

                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            // Item row
                            PageTemplateItemRow(
                                item: bindingForItem(item),
                                isEditing: editingItemId == item.id,
                                onTap: { editingItemId = item.id },
                                onDelete: { deleteItem(item) }
                            )

                            // Insert point after each item
                            InsertItemButton { itemType in
                                insertItem(at: index + 1, type: itemType)
                            }
                        }

                        // Delete template button
                        Button(role: .destructive) {
                            deleteTemplate()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Template")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .padding(.horizontal)
                        .padding(.top, 20)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Edit Page Template")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTemplate()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func bindingForItem(_ item: TemplateSectionItem) -> Binding<TemplateSectionItem> {
        Binding(
            get: { items.first { $0.id == item.id } ?? item },
            set: { newValue in
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = newValue
                }
            }
        )
    }

    private func insertItem(at index: Int, type: TemplateItemType) {
        let newItem = TemplateSectionItem(itemType: type, content: "", intent: .idea)
        items.insert(newItem, at: index)
        editingItemId = newItem.id
    }

    private func deleteItem(_ item: TemplateSectionItem) {
        items.removeAll { $0.id == item.id }
    }

    private func saveTemplate() {
        var updated = template
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.sections = items
        templateManager.updateTemplate(updated)
        dismiss()
    }

    private func deleteTemplate() {
        templateManager.deleteTemplate(template.id)
        dismiss()
    }
}

// MARK: - Template Section Row

struct TemplateSectionRow: View {
    let section: TemplateSectionItem

    var body: some View {
        HStack(spacing: 12) {
            // Item type icon
            Image(systemName: section.itemType.icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.content.isEmpty ? (section.itemType == .node ? "Empty node" : "Empty line") : section.content)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(section.content.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                if section.itemType == .node {
                    Text(section.intent.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if section.indentLevel > 0 {
                Text("Indent: \(section.indentLevel)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Commits List View

/// A unified commit item that can be either a node or page commit, sorted together by date.
enum CommitListItem: Identifiable {
    case node(NodeCommitDisplay)
    case page(Commit, noteName: String)

    var id: String {
        switch self {
        case .node(let n): return "node_\(n.id)"
        case .page(let c, _): return "page_\(c.id)"
        }
    }

    var createdAt: Int64 {
        switch self {
        case .node(let n): return n.content.createdAt
        case .page(let c, _): return c.createdAt
        }
    }
}

struct CommitsListView: View {
    @EnvironmentObject var appState: AppState
    @State private var commits: [Commit] = []
    @State private var nodeCommits: [NodeCommitDisplay] = []
    @State private var noteNames: [String: String] = [:]
    @State private var isLoading = true
    @State private var selectedCommit: Commit?
    @State private var selectedNode: NodeCommitDisplay?
    @State private var storageStats: StorageStats?
    @State private var shareSheetLink: ShareLink?
    @State private var sharePreview: String = ""
    @State private var shareError: String?
    @State private var isSharing = false
    var searchQuery: String = ""

    private var allItems: [CommitListItem] {
        var items: [CommitListItem] = []
        items += nodeCommits.map { .node($0) }
        items += commits.map { .page($0, noteName: noteNames[$0.noteId] ?? $0.name ?? "Archived Commit") }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredItems: [CommitListItem] {
        if searchQuery.isEmpty { return allItems }
        return allItems.filter { item in
            switch item {
            case .node(let n):
                return n.name.localizedCaseInsensitiveContains(searchQuery) ||
                    (n.content.sourceNoteTitle ?? "").localizedCaseInsensitiveContains(searchQuery) ||
                    (n.content.shortId ?? "").localizedCaseInsensitiveContains(searchQuery)
            case .page(let c, let noteName):
                return (c.name ?? "").localizedCaseInsensitiveContains(searchQuery) ||
                    noteName.localizedCaseInsensitiveContains(searchQuery) ||
                    c.shortId.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header with stats
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let stats = storageStats {
                    Text(stats.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else if allItems.isEmpty {
                emptyState
            } else if filteredItems.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                commitsList
            }
        }
        .task {
            await loadCommits()
        }
        .sheet(item: $selectedCommit) { commit in
            CommitDetailSheet(commit: commit, noteName: noteNames[commit.noteId])
        }
        .sheet(item: $selectedNode) { node in
            NodeCommitDetailSheet(node: node)
        }
        .sheet(item: $shareSheetLink) { link in
            NodeShareSheet(
                url: URL(string: link.url)!,
                title: link.commitName ?? "Commit Snapshot",
                preview: sharePreview
            )
        }
        .overlay {
            if isSharing {
                ProgressView("Sharing...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Commits")
                .font(.headline)
            Text("Commits save snapshots of your notes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var commitsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredItems) { item in
                switch item {
                case .node(let node):
                    NodeCommitRowView(node: node)
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color(white: 0.06))
                        .cornerRadius(12)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedNode = node
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = node.content.shortId ?? node.name
                            } label: {
                                Label("Copy ID", systemImage: "doc.on.doc")
                            }
                        }
                case .page(let commit, let noteName):
                    CommitRowView(commit: commit, noteName: noteName)
                        .padding(.leading, commit.isAutoCommit ? 0 : 16)
                        .padding(.trailing, 16)
                        .padding(.vertical, commit.isAutoCommit ? 10 : 12)
                        .background(Color(white: 0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCommit = commit
                        }
                        .contextMenu {
                            Button {
                                Task { await shareCommit(commit) }
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }

                            Button {
                                UIPasteboard.general.string = commit.shortId
                            } label: {
                                Label("Copy ID", systemImage: "doc.on.doc")
                            }

                            Button {
                                UIPasteboard.general.string = commit.hash
                            } label: {
                                Label("Copy Hash", systemImage: "number")
                            }

                            Divider()

                            Button(role: .destructive) {
                                Task { await hideCommit(commit) }
                            } label: {
                                Label("Hide", systemImage: "eye.slash")
                            }
                        }
                }
            }
        }
        .padding(.horizontal)
    }

    private func loadCommits() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load page commits
            commits = try await appState.commitRepository.getVisibleCommits()

            // Load node commits with content
            let nodeNames = appState.commitModule.getAllNodeCommits()
            nodeCommits = nodeNames.compactMap { name in
                if let content = try? appState.commitModule.getNodeCommit(name: name) {
                    return NodeCommitDisplay(name: name, content: content)
                }
                return nil
            }.sorted(by: { $0.content.createdAt > $1.content.createdAt })

            // Load note names for display
            for commit in commits {
                if noteNames[commit.noteId] == nil {
                    if let note = try await appState.noteRepository.getNote(id: commit.noteId) {
                        noteNames[commit.noteId] = note.displayTitle
                    }
                }
            }

            // Load storage stats
            storageStats = try await appState.profileScanner.getStorageStats()
        } catch {
            print("Failed to load commits: \(error)")
        }
    }

    private func hideCommit(_ commit: Commit) async {
        do {
            try await appState.commitRepository.setHidden(true, id: commit.id)
            commits.removeAll { $0.id == commit.id }
        } catch {
            print("Failed to hide commit: \(error)")
        }
    }

    private func shareCommit(_ commit: Commit) async {
        isSharing = true
        defer { isSharing = false }

        do {
            let content = try appState.coldStore.readCommit(hash: commit.hash)
            let data = try JSONEncoder().encode(content)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw ShareError.encodingError
            }

            let link = try await ShareManager.shared.createCommitShare(
                commitHash: commit.hash,
                commitName: commit.name ?? noteNames[commit.noteId],
                commitShortId: commit.shortId,
                commitContent: jsonString
            )

            // Build iMessage payload from commit section snapshots
            let sectionPreviews = content.sections.prefix(3).map { snapshot in
                MessageSharePayload.SectionPreview(
                    content: String(snapshot.content.prefix(100)),
                    contentType: snapshot.contentType,
                    intent: snapshot.intent
                )
            }

            let payload = MessageSharePayload(
                slug: link.slug,
                shareType: "commit",
                title: commit.name ?? noteNames[commit.noteId] ?? "Commit Snapshot",
                creatorName: SupabaseManager.shared.currentUser?.displayName,
                commitShortId: commit.shortId,
                sectionPreviews: Array(sectionPreviews),
                handleNames: [],
                noteId: commit.noteId
            )
            payload.writeToSharedDefaults()

            // Set preview text for the share sheet
            let preview = content.sections.first.map { String($0.content.prefix(200)) } ?? ""
            sharePreview = preview
            shareSheetLink = link
        } catch {
            shareError = error.localizedDescription
            print("Failed to share commit: \(error)")
        }
    }
}

// MARK: - Node Commit Display

struct NodeCommitDisplay: Identifiable {
    let id = UUID()
    let name: String
    let content: NodeCommitContent
}

// MARK: - Node Commit Row View

struct NodeCommitRowView: View {
    let node: NodeCommitDisplay

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(node.content.createdAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "M.dd.yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Node indicator
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(node.name)
                    .font(.headline)
                    .lineLimit(1)

                if let shortId = node.content.shortId {
                    Text("#\(shortId)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let sourceTitle = node.content.sourceNoteTitle {
                    Text("from \(sourceTitle)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Node Commit Detail Sheet

struct NodeCommitDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    let node: NodeCommitDisplay
    @State private var copiedField: String?
    @State private var showingShareSheet = false
    @State private var shareURL: URL?
    @State private var shareTitle: String = ""
    @State private var sharePreview: String = ""

    private var creatorName: String {
        authManager.currentUser?.email ?? "Local User"
    }

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(node.content.createdAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Commit badge
                    commitBadge

                    // Metadata card
                    metadataCard

                    // Dot divider
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color.gray.opacity(0.4))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                    // Section content
                    CommitNodePreview(
                        content: node.content.section.content,
                        contentType: node.content.section.contentType,
                        indentLevel: 0,
                        sectionType: node.content.section.sectionType,
                        mediaRepository: appState.mediaRepository
                    )

                    // Copy all button
                    if node.content.section.contentType != "image" && node.content.section.contentType != "audio" {
                        HStack {
                            Spacer()
                            Button {
                                UIPasteboard.general.string = node.content.section.content
                                copiedField = "copy_all"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    if copiedField == "copy_all" { copiedField = nil }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedField == "copy_all" ? "checkmark" : "doc.on.doc")
                                        .font(.caption)
                                    Text(copiedField == "copy_all" ? "" : "")
                                        .font(.caption.weight(.medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.2))
                                .foregroundStyle(copiedField == "copy_all" ? .green : .secondary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        UIPasteboard.general.string = node.content.shortId ?? node.name
                        copiedField = "nav_title"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedField == "nav_title" { copiedField = nil }
                        }
                    } label: {
                        Text(copiedField == "nav_title" ? "Copied" : "#\(node.content.shortId ?? node.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(copiedField == "nav_title" ? .white : .green)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.2), in: Capsule())
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await shareNodeFromDetail() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .fullScreenCover(isPresented: $showingShareSheet) {
                if let url = shareURL {
                    NodeShareSheet(
                        url: url,
                        title: shareTitle,
                        preview: sharePreview
                    )
                }
            }
        }
    }

    private var commitBadge: some View {
        ZStack {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.zipper")
                        .font(.caption2)
                    Text("Commit")
                        .font(.caption2.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.15), in: Capsule())
                .foregroundStyle(.purple)
                Spacer()
            }

            if let title = node.content.sourceNoteTitle, !title.isEmpty {
                Button {
                    UIPasteboard.general.string = title
                    copiedField = "badge_title"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedField == "badge_title" { copiedField = nil }
                    }
                } label: {
                    Text(copiedField == "badge_title" ? "Copied" : title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(copiedField == "badge_title" ? .green : .primary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // .obx filename
            copyableRow(
                label: "File",
                value: "\(node.name).obx",
                field: "file",
                valueFont: .subheadline.weight(.medium),
                valueColor: .primary
            )

            // Creator
            copyableRow(
                label: "By",
                value: creatorName,
                field: "creator",
                valueFont: .subheadline,
                valueColor: .secondary
            )

            // Created date
            copyableRow(
                label: "Date",
                value: formattedDate,
                field: "date",
                valueFont: .subheadline,
                valueColor: .secondary
            )

            // Hash
            if let hash = node.content.hash {
                let bareHash = hash.replacingOccurrences(of: "sha256:", with: "")
                copyableRow(
                    label: "Hash",
                    value: bareHash,
                    field: "hash",
                    valueFont: .system(.caption2, design: .monospaced),
                    valueColor: .tertiary
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func copyableRow<S: ShapeStyle>(label: String, value: String, field: String, valueFont: Font, valueColor: S) -> some View {
        Button {
            UIPasteboard.general.string = value
            copiedField = field
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedField == field { copiedField = nil }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if copiedField == field {
                    Text("Copied")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Text(value)
                        .font(valueFont)
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func shareNodeFromDetail() async {
        do {
            let content = node.content
            let data = try JSONEncoder().encode(content)
            guard let jsonString = String(data: data, encoding: .utf8) else { return }

            let hash = content.hash ?? "node_\(node.name)"
            let link = try await ShareManager.shared.createCommitShare(
                commitHash: hash,
                commitName: node.name,
                commitShortId: content.shortId,
                commitContent: jsonString
            )

            shareURL = URL(string: link.url)
            shareTitle = node.name
            sharePreview = String(content.section.content.prefix(200))
            showingShareSheet = true
        } catch {
            print("Failed to share node commit: \(error)")
        }
    }
}

// MARK: - Commit Row View

struct CommitRowView: View {
    let commit: Commit
    let noteName: String

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(commit.createdAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "M.dd.yyyy"
        return formatter.string(from: date)
    }

    private var shortHash: String {
        let hash = commit.hash.replacingOccurrences(of: "sha256:", with: "")
        return String(hash.prefix(8))
    }

    var body: some View {
        if commit.isAutoCommit {
            autoCommitRow
        } else {
            manualCommitRow
        }
    }

    private var manualCommitRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(commit.name ?? noteName)
                    .font(.headline)
                    .lineLimit(1)

                Text("#\(commit.shortId)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if commit.name != nil {
                    Text("from \(noteName)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var autoCommitRow: some View {
        HStack(spacing: 0) {
            // Gradient lip with sideways "Auto" label
            ZStack {
                LinearGradient(
                    colors: [Color.orange.opacity(0.2), Color.orange.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                Text("Auto")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 40)
            .padding(.vertical, -10)

            HStack {
                Text(commit.name ?? noteName)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 6)
        }
    }
}

// MARK: - Commit Detail Sheet

struct CommitDetailSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    let commit: Commit
    let noteName: String?

    @State private var content: CommitContent?
    @State private var isLoading = true
    @State private var copiedField: String?
    @State private var comments: [SharedComment] = []
    @State private var isLoadingComments = false
    @State private var showingShareSheet = false
    @State private var shareURL: URL?
    @State private var shareTitle: String = ""
    @State private var sharePreview: String = ""
    @FocusState private var isCommentFocused: Bool

    private var creatorName: String {
        authManager.currentUser?.email ?? "Local User"
    }

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(commit.createdAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let content = content {
                    commitContentView(content)
                } else {
                    Text("Failed to load commit")
                        .foregroundStyle(.secondary)
                }
            }
            .background(Color.black)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        UIPasteboard.general.string = commit.shortId
                        copiedField = "nav_title"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedField == "nav_title" { copiedField = nil }
                        }
                    } label: {
                        Text(copiedField == "nav_title" ? "Copied" : "#\(commit.shortId)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(copiedField == "nav_title" ? .white : .green)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.2), in: Capsule())
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await shareFromDetail() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .task {
                await loadContent()
                await loadComments()
            }
            .fullScreenCover(isPresented: $showingShareSheet) {
                if let url = shareURL {
                    NodeShareSheet(
                        url: url,
                        title: shareTitle,
                        preview: sharePreview
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func commitContentView(_ content: CommitContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Commit badge + title
                ZStack {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.zipper")
                                .font(.caption2)
                            Text("Commit")
                                .font(.caption2.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.15), in: Capsule())
                        .foregroundStyle(.purple)
                        Spacer()
                    }

                    if let title = content.note.title, !title.isEmpty {
                        Button {
                            UIPasteboard.general.string = title
                            copiedField = "badge_title"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedField == "badge_title" { copiedField = nil }
                            }
                        } label: {
                            Text(copiedField == "badge_title" ? "Copied" : title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(copiedField == "badge_title" ? .green : .primary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Metadata card
                VStack(alignment: .leading, spacing: 6) {
                    // .obx filename
                    copyableRow(
                        label: "File",
                        value: "\(commit.name ?? "Untitled").obx",
                        field: "file",
                        valueFont: .subheadline.weight(.medium),
                        valueColor: .primary
                    )

                    // Creator
                    copyableRow(
                        label: "By",
                        value: creatorName,
                        field: "creator",
                        valueFont: .subheadline,
                        valueColor: .secondary
                    )

                    // Created date
                    copyableRow(
                        label: "Date",
                        value: formattedDate,
                        field: "date",
                        valueFont: .subheadline,
                        valueColor: .secondary
                    )

                    // Hash
                    let bareHash = commit.hash.replacingOccurrences(of: "sha256:", with: "")
                    copyableRow(
                        label: "Hash",
                        value: bareHash,
                        field: "hash",
                        valueFont: .system(.caption2, design: .monospaced),
                        valueColor: .tertiary
                    )
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Dot divider
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                // Section content
                if !content.note.body.isEmpty {
                    Text(content.note.body)
                        .font(.body)
                }

                ForEach(content.sections, id: \.id) { section in
                    CommitNodePreview(
                        content: section.content,
                        contentType: section.contentType,
                        indentLevel: section.indentLevel,
                        sectionType: section.sectionType,
                        mediaRepository: appState.mediaRepository
                    )

                    // Interstitial line after this section
                    let interstitialKey = "after_\(section.id)"
                    if let text = content.note.interstitialContent[interstitialKey],
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if content.note.interstitialContent[interstitialKey] != nil {
                        Color.clear.frame(height: 16)
                    }
                }

                // End interstitial
                if let endText = content.note.interstitialContent["end"],
                   !endText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(endText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Copy all button
                HStack {
                    Spacer()
                    Button {
                        let allText = buildFullContentText(content)
                        UIPasteboard.general.string = allText
                        copiedField = "copy_all"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedField == "copy_all" { copiedField = nil }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedField == "copy_all" ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                            Text(copiedField == "copy_all" ? "" : "")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(copiedField == "copy_all" ? .green : .secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .padding(.vertical, 8)

                // Comments
                CommentThreadView(
                    comments: comments,
                    isAuthenticated: SupabaseManager.shared.isAuthenticated,
                    isCommitShare: true,
                    onAddComment: { body in
                        await addComment(body: body)
                    }
                )

                Spacer(minLength: 40)
            }
            .padding()
        }
    }

    private func copyableRow<S: ShapeStyle>(label: String, value: String, field: String, valueFont: Font, valueColor: S) -> some View {
        Button {
            UIPasteboard.general.string = value
            copiedField = field
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedField == field { copiedField = nil }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if copiedField == field {
                    Text("Copied")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Text(value)
                        .font(valueFont)
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            content = try appState.coldStore.readCommit(hash: commit.hash)
        } catch {
            print("Failed to load commit content: \(error)")
        }
    }

    private func loadComments() async {
        // Find share links for this commit and load their comments
        do {
            let links = try await ShareManager.shared.getShareLinks(commitHash: commit.hash)
            guard let link = links.first else { return }

            let response = try await SupabaseManager.shared.client
                .from("comments")
                .select()
                .eq("share_link_id", value: link.id)
                .is("deleted_at", value: nil)
                .execute()

            let decoded = try JSONDecoder().decode([SharedComment].self, from: response.data)

            // Enrich comments with email — current user's email for their own comments,
            // look up others from user_profiles
            let currentUser = SupabaseManager.shared.currentUser
            var userEmails: [String: String] = [:]
            if let user = currentUser {
                userEmails[user.id.uuidString] = user.email
            }

            comments = decoded.map { comment in
                SharedComment(
                    id: comment.id,
                    userId: comment.userId,
                    userDisplayName: comment.userDisplayName,
                    userEmail: userEmails[comment.userId],
                    body: comment.body,
                    createdAt: comment.createdAt,
                    sealedCommitHash: comment.sealedCommitHash
                )
            }
        } catch {
            print("Failed to load comments: \(error)")
        }
    }

    private func addComment(body: String) async {
        do {
            // Find or create share link for this commit
            var links = try await ShareManager.shared.getShareLinks(commitHash: commit.hash)
            let link: ShareLink
            if let existing = links.first {
                link = existing
            } else {
                // Create a share link so we can attach comments
                let content = try appState.coldStore.readCommit(hash: commit.hash)
                let data = try JSONEncoder().encode(content)
                guard let jsonString = String(data: data, encoding: .utf8) else { return }
                link = try await ShareManager.shared.createCommitShare(
                    commitHash: commit.hash,
                    commitName: commit.name ?? noteName,
                    commitShortId: commit.shortId,
                    commitContent: jsonString
                )
            }

            let comment = try await ShareManager.shared.addComment(
                shareLinkId: link.id,
                body: body
            )
            comments.append(comment)
        } catch {
            print("Failed to add comment: \(error)")
        }
    }

    private func shareFromDetail() async {
        guard let content = content else { return }
        do {
            let data = try JSONEncoder().encode(content)
            guard let jsonString = String(data: data, encoding: .utf8) else { return }

            let link = try await ShareManager.shared.createCommitShare(
                commitHash: commit.hash,
                commitName: commit.name ?? noteName,
                commitShortId: commit.shortId,
                commitContent: jsonString
            )

            let sectionPreviews = content.sections.prefix(3).map { snapshot in
                MessageSharePayload.SectionPreview(
                    content: String(snapshot.content.prefix(100)),
                    contentType: snapshot.contentType,
                    intent: snapshot.intent
                )
            }

            let payload = MessageSharePayload(
                slug: link.slug,
                shareType: "commit",
                title: commit.name ?? noteName ?? "Commit Snapshot",
                creatorName: SupabaseManager.shared.currentUser?.displayName,
                commitShortId: commit.shortId,
                sectionPreviews: Array(sectionPreviews),
                handleNames: [],
                noteId: commit.noteId
            )
            payload.writeToSharedDefaults()

            shareURL = URL(string: link.url)
            shareTitle = commit.name ?? noteName ?? "Commit Snapshot"
            sharePreview = content.sections.first.map { String($0.content.prefix(200)) } ?? ""
            showingShareSheet = true
        } catch {
            print("Failed to share commit: \(error)")
        }
    }

    private func buildFullContentText(_ content: CommitContent) -> String {
        var parts: [String] = []
        if !content.note.body.isEmpty {
            parts.append(content.note.body)
        }
        for section in content.sections {
            if section.contentType != "image" && section.contentType != "audio" {
                parts.append(section.content)
            }
            let interstitialKey = "after_\(section.id)"
            if let text = content.note.interstitialContent[interstitialKey],
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(text)
            }
        }
        if let endText = content.note.interstitialContent["end"],
           !endText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(endText)
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Commit Node Preview

/// A read-only grey/white preview of a section, mirroring the editor layout.
struct CommitNodePreview: View {
    let content: String
    let contentType: String
    let indentLevel: Int
    let sectionType: String
    let mediaRepository: MediaRepository?

    @State private var loadedImages: [String: UIImage] = [:]

    /// Parse image hashes from "hash|assetId,hash|assetId,..." format
    private var imageHashes: [String] {
        content
            .split(separator: ",")
            .map { entry in
                let parts = entry.split(separator: "|", maxSplits: 1)
                return String(parts[0]).trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    /// Parse audio hash and duration from "hash|duration" format
    private var audioHash: String {
        let parts = content.split(separator: "|", maxSplits: 1)
        return parts.count > 0 ? String(parts[0]).trimmingCharacters(in: .whitespaces) : ""
    }

    private var audioDuration: TimeInterval {
        let parts = content.split(separator: "|", maxSplits: 1)
        return parts.count > 1 ? (Double(parts[1]) ?? 0) : 0
    }

    var body: some View {
        if contentType == "image" {
            // Image: display all photos stacked vertically
            VStack(spacing: 8) {
                ForEach(imageHashes, id: \.self) { hash in
                    if let image = loadedImages[hash] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(height: 160)
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.gray)
                            }
                    }
                }
            }
            .padding(.leading, CGFloat(indentLevel) * 20)
            .onAppear { loadImages() }
        } else if contentType == "audio", !audioHash.isEmpty, let mediaRepo = mediaRepository {
            // Audio: playable audio node
            AudioNodeView(
                audioHash: audioHash,
                duration: audioDuration,
                mediaRepository: mediaRepo
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.15))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.leading, CGFloat(indentLevel) * 20)
        } else if sectionType == "line" {
            // Interstitial line: plain text without node styling
            Text(content.isEmpty ? " " : content)
                .font(.subheadline)
                .foregroundStyle(content.isEmpty ? .clear : .primary)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .padding(.leading, CGFloat(indentLevel) * 20)
        } else {
            // Fold/Node: simple rounded box matching metadata card background
            Text(content.isEmpty ? "(empty)" : content)
                .font(.subheadline)
                .foregroundStyle(content.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.leading, CGFloat(indentLevel) * 20)
        }
    }

    private func loadImages() {
        guard let mediaRepository else { return }
        for hash in imageHashes where loadedImages[hash] == nil {
            if let data = try? mediaRepository.getMediaData(hash: hash),
               let image = UIImage(data: data) {
                loadedImages[hash] = image
            }
        }
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .environmentObject(AppState())
    .environmentObject(AuthManager.shared)
}
