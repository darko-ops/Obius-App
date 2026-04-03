import SwiftUI

#if os(macOS)
/// Sidebar that shows the selected project, its pages, and nav tabs on macOS.
struct MacSidebarProjectList: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var moduleRepository: ModuleRepository
    @Binding var selectedTab: Int
    @AppStorage("selectedModuleId") private var selectedModuleId: String?

    @State private var showingProjectPicker = false
    @State private var showingAddModule = false
    @State private var newModuleName = ""
    @State private var moduleToDelete: Module?
    @State private var showingDeleteConfirmation = false
    @State private var moduleToRename: Module?
    @State private var renameText = ""
    @State private var showingSettings = false
    @State private var selectedNote: Note?
    @AppStorage("macIsInEditor") private var isInEditor = false
    @AppStorage("macSelectedNoteId") private var macSelectedNoteId: String?

    private var selectedModule: Module? {
        moduleRepository.modules.first { $0.id == selectedModuleId }
    }

    private var selectedModuleName: String {
        selectedModule?.name ?? "Local"
    }

    private var projectNotes: [Note] {
        appState.noteRepository.notes
            .filter { $0.moduleId == selectedModuleId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isInEditor {
                // Project selector header with <> chevron
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingProjectPicker.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(white: 0.45))

                        Text(selectedModuleName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            showingAddModule = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(white: 0.45))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                // Expandable project picker
                if showingProjectPicker {
                    VStack(spacing: 2) {
                        ForEach(moduleRepository.modules) { module in
                            projectRow(module)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()
                    .background(Color(white: 0.12))

                // Pages list — only visible when inside the note editor
                if isInEditor {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(projectNotes) { note in
                                pageRow(note)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                    }
                }
            }

            Spacer()

            // Navigation tabs at bottom
            VStack(spacing: 2) {
                Divider()
                    .background(Color(white: 0.15))
                    .padding(.bottom, 4)

                navButton("Notes", icon: "note.text", tag: 0)
                navButtonCustomIcon("Insights", imageName: "ObiusLogo", tag: 1)
                navButton("More", icon: "person.crop.circle", tag: 2)

                Button {
                    showingSettings = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.5))
                            .frame(width: 18)

                        Text("Settings")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.6))

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.04))
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        .alert("New Project", isPresented: $showingAddModule) {
            TextField("Project name", text: $newModuleName)
            Button("Local") { createModule(storageType: .local) }
            Button("Cloud") { createModule(storageType: .cloud) }
            Button("Cancel", role: .cancel) { newModuleName = "" }
        } message: {
            Text("Enter a name for the new project")
        }
        .alert("Rename Project", isPresented: Binding(
            get: { moduleToRename != nil },
            set: { if !$0 { moduleToRename = nil } }
        )) {
            TextField("Project name", text: $renameText)
            Button("Save") {
                if let module = moduleToRename {
                    let newName = renameText
                    Task { try? await moduleRepository.renameModule(id: module.id, newName: newName) }
                }
                moduleToRename = nil
            }
            Button("Cancel", role: .cancel) { moduleToRename = nil }
        } message: {
            Text("Enter a new name for this project")
        }
        .confirmationDialog(
            "Delete \"\(moduleToDelete?.name ?? "")\"?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let module = moduleToDelete {
                    if selectedModuleId == module.id {
                        selectedModuleId = moduleRepository.getLocalModule()?.id
                    }
                    Task {
                        let movedNoteIds = (try? await moduleRepository.deleteModule(id: module.id)) ?? []
                        for noteId in movedNoteIds {
                            if let note = try? await appState.noteRepository.getNote(id: noteId) {
                                await appState.syncLogger.logNoteUpdateSync(note)
                            }
                        }
                        try? await Task.sleep(for: .milliseconds(200))
                        await appState.triggerSync()
                    }
                }
                moduleToDelete = nil
            }
            Button("Cancel", role: .cancel) { moduleToDelete = nil }
        } message: {
            Text("Notes in this project will be moved to Local.")
        }
        .onAppear {
            if selectedModuleId == nil, let local = moduleRepository.getLocalModule() {
                selectedModuleId = local.id
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
            .frame(minWidth: 450, minHeight: 500)
            .preferredColorScheme(.dark)
            .environmentObject(appState)
            .environmentObject(AuthManager.shared)
            .environmentObject(AppearanceManager.shared)
        }
    }

    // MARK: - Page Row

    private func pageRow(_ note: Note) -> some View {
        Button {
            selectedNote = note
            selectedTab = 0
            macSelectedNoteId = note.id
            isInEditor = true
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(note.intent.color)
                    .frame(width: 3, height: 16)

                Text(appState.noteRepository.resolvedTitle(for: note))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.75))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(macSelectedNoteId == note.id ? Color(white: 0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Project Row

    private func projectRow(_ module: Module) -> some View {
        let isSelected = selectedModuleId == module.id

        return Button {
            selectedModuleId = module.id
            selectedNote = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                showingProjectPicker = false
            }
            if selectedTab != 0 {
                selectedTab = 0
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: module.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : Color(white: 0.5))
                    .frame(width: 18)

                Text(module.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Color(white: 0.7))
                    .lineLimit(1)

                if module.storageType == .cloud {
                    Image(systemName: "cloud")
                        .font(.system(size: 8))
                        .foregroundStyle(.blue.opacity(0.7))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color(white: 0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameText = module.name
                moduleToRename = module
            } label: {
                Label("Rename Project", systemImage: "pencil")
            }

            if moduleRepository.modules.filter({ $0.deletedAt == nil }).count > 1 {
                Button(role: .destructive) {
                    moduleToDelete = module
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Project", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Nav Button

    private func navButton(_ title: String, icon: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag

        return Button {
            selectedTab = tag
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : Color(white: 0.5))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Color(white: 0.6))

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color(white: 0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func navButtonCustomIcon(_ title: String, imageName: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag

        return Button {
            selectedTab = tag
        } label: {
            HStack(spacing: 8) {
                Image(imageName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(isSelected ? .white : Color(white: 0.5))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Color(white: 0.6))

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color(white: 0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func createModule(storageType: ModuleStorageType) {
        let name = newModuleName
        newModuleName = ""
        Task {
            try? await moduleRepository.createModule(name: name, storageType: storageType)
        }
    }
}

// MARK: - Notification for sidebar note selection

extension Notification.Name {
    static let sidebarNoteSelected = Notification.Name("sidebarNoteSelected")
}
#endif
