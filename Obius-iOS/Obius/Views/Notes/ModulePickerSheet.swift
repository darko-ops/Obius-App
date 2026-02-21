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

    var body: some View {
        NavigationStack {
            moduleList
                .background(Color.black)
                .navigationTitle("Modules")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
                .alert("New Module", isPresented: $showingAddModule) {
                    addModuleAlertContent
                } message: {
                    Text("Enter a name for the new module")
                }
                .confirmationDialog(
                    "Delete \(moduleToDelete?.name ?? "")?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    deleteConfirmationContent
                } message: {
                    Text("Notes in this module will be moved to Local.")
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
        }
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
        .listRowBackground(Color(white: 0.06))
        .contextMenu {
            if !module.isDefault {
                Button(role: .destructive) {
                    moduleToDelete = module
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Module", systemImage: "trash")
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
        TextField("Module name", text: $newModuleName)
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
