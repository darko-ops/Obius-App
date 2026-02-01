import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var handleManager = HandleManager.shared
    @State private var selectedSection: LibrarySection = .loops
    @State private var showingSettings = false

    enum LibrarySection: String, CaseIterable {
        case loops = "Loops"
        case templates = "Templates"

        var icon: String {
            switch self {
            case .loops: return "link"
            case .templates: return "doc.on.doc"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // User Profile Section
                userProfileSection

                Divider()
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
                    LoopsListView()
                case .templates:
                    TemplatesListView()
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Library")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
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
            ForEach(handleManager.handles) { handle in
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
    @State private var showingCreateSheet = false
    @State private var selectedTemplate: SectionTemplate?
    @State private var createTemplateType: TemplateType = .fold

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
                        createTemplateType = .fold
                        showingCreateSheet = true
                    } label: {
                        Label("Fold Template", systemImage: TemplateType.fold.icon)
                    }

                    Button {
                        createTemplateType = .page
                        showingCreateSheet = true
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
            } else {
                templatesList
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateTemplateSheet(templateType: createTemplateType)
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
            Text("Create structured folds or pages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var templatesList: some View {
        LazyVStack(spacing: 16) {
            // Fold Templates
            if !templateManager.foldTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Fold Templates", systemImage: TemplateType.fold.icon)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    LazyVStack(spacing: 8) {
                        ForEach(templateManager.foldTemplates) { template in
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

            // Page Templates
            if !templateManager.pageTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Page Templates", systemImage: TemplateType.page.icon)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    LazyVStack(spacing: 8) {
                        ForEach(templateManager.pageTemplates) { template in
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

// MARK: - Template Row View

struct TemplateRowView: View {
    let template: SectionTemplate

    private var previewText: String {
        if template.templateType == .fold {
            // Show content preview for fold templates
            return template.sections.first?.content ?? ""
        } else {
            // Show fold count for page templates
            let count = template.sections.count
            return "\(count) \(count == 1 ? "fold" : "folds")"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: template.templateType.icon)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.headline)

                if !previewText.isEmpty {
                    Text(previewText)
                        .font(.caption)
                        .fontWeight(template.templateType == .fold ? .bold : .regular)
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
        if templateType == .fold {
            CreateFoldTemplateSheet()
        } else {
            CreatePageTemplateSheet()
        }
    }
}

// MARK: - Create Fold Template Sheet

struct CreateFoldTemplateSheet: View {
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
            .navigationTitle("Create Fold Template")
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
        let fold = TemplateSectionItem(itemType: .fold, content: content, intent: intent)
        let template = SectionTemplate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            templateType: .fold,
            sections: [fold]
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
                        onInsert(.fold)
                        isExpanded = false
                    } label: {
                        Label("Fold", systemImage: TemplateItemType.fold.icon)
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
                        .frame(minHeight: item.itemType == .fold ? 60 : 32)
                        .fontWeight(.bold)
                        .scrollContentBackground(.hidden)

                    // Intent picker (only for folds)
                    if item.itemType == .fold {
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
        .background(item.itemType == .fold ? Color.gray.opacity(0.05) : Color.clear)
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
        if template.templateType == .fold {
            EditFoldTemplateSheet(template: template)
        } else {
            EditPageTemplateSheet(template: template)
        }
    }
}

// MARK: - Edit Fold Template Sheet

struct EditFoldTemplateSheet: View {
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
            .navigationTitle("Edit Fold Template")
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
        let fold = TemplateSectionItem(
            id: template.sections.first?.id ?? UUID().uuidString,
            itemType: .fold,
            content: content,
            intent: intent
        )
        var updated = template
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.sections = [fold]
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
                Text(section.content.isEmpty ? (section.itemType == .fold ? "Empty fold" : "Empty line") : section.content)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(section.content.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                if section.itemType == .fold {
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

#Preview {
    NavigationStack {
        LibraryView()
    }
    .environmentObject(AppState())
    .environmentObject(AuthManager.shared)
}
