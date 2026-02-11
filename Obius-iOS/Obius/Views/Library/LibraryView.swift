import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var handleManager = HandleManager.shared
    @StateObject private var echoManager = EchoManager.shared
    @State private var selectedSection: LibrarySection = .commits
    @State private var searchQuery = ""
    @State private var showingSettings = false
    @State private var selectedEcho: Echo?

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
            .padding(.vertical)
        }
        .navigationTitle("Library")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
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
        VStack(spacing: 16) {
            // Profile avatar
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)

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

            // User info
            VStack(spacing: 4) {
                if authManager.isAuthenticated, let user = authManager.currentUser {
                    Text(user.displayName ?? "User")
                        .font(.title3.weight(.semibold))

                    Text(user.email ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not Signed In")
                        .font(.title3.weight(.semibold))

                    Text("Sign in to sync your notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
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
                Text("Loops")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
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
                    .background(Color.gray.opacity(0.05))
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

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(handle.formattedName)
                    .font(.headline)

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
                Text("Templates")
                    .font(.headline)
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
                        .foregroundStyle(Color.accentColor)
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
                                    .background(Color.gray.opacity(0.05))
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
                                    .background(Color.gray.opacity(0.05))
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
                .background(Color.gray.opacity(0.05))

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
                .background(Color.gray.opacity(0.05))

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
    var searchQuery: String = ""

    private var allItems: [CommitListItem] {
        var items: [CommitListItem] = []
        items += nodeCommits.map { .node($0) }
        items += commits.map { .page($0, noteName: noteNames[$0.noteId] ?? "Unknown Note") }
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
                Text("Version History")
                    .font(.headline)
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
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(12)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedNode = node
                        }
                case .page(let commit, let noteName):
                    CommitRowView(commit: commit, noteName: noteName)
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(12)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCommit = commit
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
            commits = try await appState.commitRepository.getAllCommits()

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
    @EnvironmentObject var authManager: AuthManager
    let node: NodeCommitDisplay
    @State private var copiedField: String?

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(node.content.createdAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var creatorName: String {
        authManager.currentUser?.displayName ?? authManager.currentUser?.email ?? "Local User"
    }

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section("Ticket") {
                    CopyableRow(label: "File Name", value: "\(node.name).obx", copiedField: $copiedField)
                    if let shortId = node.content.shortId {
                        CopyableRow(label: "Ref", value: "#\(shortId)", copiedField: $copiedField)
                    }
                    if let hash = node.content.hash {
                        CopyableRow(label: "Hash", value: hash.replacingOccurrences(of: "sha256:", with: ""), copiedField: $copiedField)
                    }
                    CopyableRow(label: "Created", value: formattedDate, copiedField: $copiedField)
                    CopyableRow(label: "Created By", value: creatorName, copiedField: $copiedField)
                }

                SwiftUI.Section("Context") {
                    // Source note row (like artifacts page)
                    if let sourceTitle = node.content.sourceNoteTitle {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(sourceTitle)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(node.content.section.intent.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }

                    // Node preview (like editor node)
                    CommitNodePreview(
                        content: node.content.section.content,
                        indentLevel: node.content.section.indentLevel,
                        sectionType: node.content.section.sectionType
                    )
                }
            }
            .navigationTitle(node.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
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
        HStack(spacing: 12) {
            // Commit indicator
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
    @State private var showingRestoreConfirm = false
    @State private var copiedField: String?

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(commit.createdAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var shortHash: String {
        commit.hash.replacingOccurrences(of: "sha256:", with: "")
    }

    private var creatorName: String {
        authManager.currentUser?.displayName ?? authManager.currentUser?.email ?? "Local User"
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
            .navigationTitle(commit.name ?? "Commit Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadContent()
            }
            .confirmationDialog(
                "Restore this commit?",
                isPresented: $showingRestoreConfirm,
                titleVisibility: .visible
            ) {
                Button("Restore", role: .destructive) {
                    restoreCommit()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will overwrite the current note with this snapshot. This action cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private func commitContentView(_ content: CommitContent) -> some View {
        List {
            SwiftUI.Section("Ticket") {
                CopyableRow(
                    label: "File Name",
                    value: commit.name != nil ? "\(commit.name!).obx" : commit.filePath,
                    copiedField: $copiedField
                )
                CopyableRow(label: "Ref", value: "#\(commit.shortId)", copiedField: $copiedField)
                CopyableRow(label: "Hash", value: shortHash, copiedField: $copiedField)
                CopyableRow(label: "Created", value: formattedDate, copiedField: $copiedField)
                CopyableRow(label: "Created By", value: creatorName, copiedField: $copiedField)
            }

            SwiftUI.Section("Context") {
                // Note row (like artifacts page)
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(content.note.title ?? "Untitled")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if !content.note.body.isEmpty {
                            Text(content.note.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Text(content.note.intent.capitalized)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)

                // Sections (like editor nodes)
                if !content.sections.isEmpty {
                    ForEach(content.sections, id: \.id) { section in
                        CommitNodePreview(
                            content: section.content,
                            indentLevel: section.indentLevel,
                            sectionType: section.sectionType
                        )
                    }
                }
            }

            // Actions
            SwiftUI.Section {
                Button {
                    showingRestoreConfirm = true
                } label: {
                    Label("Restore This Commit", systemImage: "arrow.counterclockwise")
                }
            }
        }
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

    private func restoreCommit() {
        Task {
            do {
                try await appState.commitModule.restoreCommit(hash: commit.hash)
                dismiss()
            } catch {
                print("Failed to restore commit: \(error)")
            }
        }
    }
}

// MARK: - Commit Node Preview

/// A read-only grey/white preview of a section, mirroring the editor layout.
struct CommitNodePreview: View {
    let content: String
    let indentLevel: Int
    let sectionType: String

    var body: some View {
        if sectionType == "line" {
            // Line: plain text, no background box
            Text(content.isEmpty ? "(empty)" : content)
                .font(.subheadline)
                .foregroundStyle(content.isEmpty ? .tertiary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, CGFloat(indentLevel) * 20)
                .padding(.vertical, 2)
        } else {
            // Fold/Node: simple rounded box
            Text(content.isEmpty ? "(empty)" : content)
                .font(.subheadline)
                .foregroundStyle(content.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.leading, CGFloat(indentLevel) * 20)
        }
    }
}

// MARK: - Copyable Row

struct CopyableRow: View {
    let label: String
    let value: String
    @Binding var copiedField: String?

    private var fieldKey: String { "\(label):\(value)" }

    var body: some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = value
            #endif
            copiedField = fieldKey
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedField == fieldKey {
                    copiedField = nil
                }
            }
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if copiedField == fieldKey {
                    Text("Copied")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .environmentObject(AppState())
    .environmentObject(AuthManager.shared)
}
