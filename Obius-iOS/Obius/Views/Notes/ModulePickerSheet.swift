import SwiftUI

struct ModulePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var moduleRepository: ModuleRepository
    @Binding var selectedModuleId: String?

    @State private var showingAddModule = false
    @State private var newModuleName = ""
    @State private var newModuleStorageType: ModuleStorageType = .local
    @State private var showingDeleteConfirmation = false
    @State private var moduleToDelete: Module?
    @State private var moduleToRename: Module?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            moduleList
                .background(Color(.systemBackground))
                .navigationTitle("Projects")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
                .alert("New Project", isPresented: $showingAddModule) {
                    addModuleAlertContent
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
                            Task {
                                try? await moduleRepository.renameModule(id: module.id, newName: newName)
                            }
                        }
                        moduleToRename = nil
                    }
                    Button("Cancel", role: .cancel) {
                        moduleToRename = nil
                    }
                } message: {
                    Text("Enter a new name for this project")
                }
                .confirmationDialog(
                    "Delete \"\(moduleToDelete?.name ?? "")\"?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    deleteConfirmationContent
                } message: {
                    Text("Notes in this project will be moved to Local.")
                }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Subviews

    private var moduleList: some View {
        List {
            ForEach(moduleRepository.modules) { module in
                moduleRow(module)
            }
            .onMove { source, destination in
                var ids = moduleRepository.modules.map { $0.id }
                ids.move(fromOffsets: source, toOffset: destination)
                Task {
                    try? await moduleRepository.reorderModules(ids: ids)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        #if os(iOS)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #endif
    }

    private func moduleRow(_ module: Module) -> some View {
        Button {
            selectedModuleId = module.id
            dismiss()
        } label: {
            moduleRowLabel(module)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(.secondarySystemBackground))
        .contextMenu {
            if !module.isDefault {
                Button {
                    renameText = module.name
                    moduleToRename = module
                } label: {
                    Label("Rename Project", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    moduleToDelete = module
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Project", systemImage: "trash")
                }
            }
        }
    }

    private func moduleRowLabel(_ module: Module) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(module.name)
                .foregroundStyle(.primary)

            StorageTypeBadge(storageType: module.storageType)

            Spacer()

            if selectedModuleId == module.id {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
                dismiss()
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                newModuleStorageType = .local
                showingAddModule = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    @ViewBuilder
    private var addModuleAlertContent: some View {
        TextField("Project name", text: $newModuleName)
        Button("Local") {
            createNewModule(storageType: .local)
        }
        Button("Cloud") {
            createNewModule(storageType: .cloud)
        }
        Button("Cancel", role: .cancel) {
            newModuleName = ""
        }
    }

    private func createNewModule(storageType: ModuleStorageType) {
        let name = newModuleName
        newModuleName = ""
        Task {
            try? await moduleRepository.createModule(name: name, storageType: storageType)
        }
    }

    @ViewBuilder
    private var deleteConfirmationContent: some View {
        Button("Delete", role: .destructive) {
            if let module = moduleToDelete {
                if selectedModuleId == module.id {
                    selectedModuleId = moduleRepository.getLocalModule()?.id
                }
                Task {
                    try? await moduleRepository.deleteModule(id: module.id)
                }
            }
            moduleToDelete = nil
        }
        Button("Cancel", role: .cancel) {
            moduleToDelete = nil
        }
    }
}

// MARK: - Storage Type Badge

struct StorageTypeBadge: View {
    let storageType: ModuleStorageType

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: storageType.icon)
                .font(.system(size: 8, weight: .semibold))
            Text(storageType.displayName)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(storageType == .cloud ? Color.blue : Color.gray)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(storageType == .cloud ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
        )
    }
}
