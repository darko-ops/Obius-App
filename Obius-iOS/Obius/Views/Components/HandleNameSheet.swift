import SwiftUI

/// Sheet for creating a new handle or selecting an existing one
struct HandleNameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingHandles: [Handle]
    let onCreateNew: (String, EchoConfig?) -> Void
    let onSelectExisting: (Handle) -> Void

    @State private var handleName: String = ""
    @State private var validationError: String?
    @State private var showExisting: Bool = true
    @State private var echoConfig: EchoConfig?
    @State private var showingEchoConfig: Bool = false

    private var normalizedName: String {
        handleName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidName: Bool {
        Handle.validateName(normalizedName) == nil
    }

    private var nameAlreadyExists: Bool {
        let normalized = Handle.normalizeName(normalizedName)
        return existingHandles.contains { $0.name == normalized }
    }

    private var filteredHandles: [Handle] {
        if normalizedName.isEmpty {
            return existingHandles
        }
        let query = normalizedName.lowercased()
        return existingHandles.filter { handle in
            handle.name.contains(query) || handle.displayName.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Handle name input
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Text("@")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            TextField("LoopName", text: $handleName)
                                .font(.title2)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .autocorrectionDisabled()
                                .onChange(of: handleName) { _, newValue in
                                    // Real-time validation
                                    validationError = Handle.validateName(newValue)
                                }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            showingEchoConfig = true
                        } label: {
                            Image(systemName: echoConfig != nil ? "dot.radiowaves.left.and.right" : "dot.radiowaves.left.and.right")
                                .font(.title2)
                                .foregroundStyle(echoConfig != nil ? .yellow : .secondary)
                                .frame(width: 44, height: 44)
                                .background(Color.gray.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    if let error = validationError, !normalizedName.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if nameAlreadyExists {
                        Text("This loop already exists - select it below or choose a different name")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()

                Divider()

                // Existing handles section
                if !existingHandles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(normalizedName.isEmpty ? "Existing Loops" : "Matching Loops")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            if !filteredHandles.isEmpty {
                                Text("\(filteredHandles.count)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)

                        if filteredHandles.isEmpty && !normalizedName.isEmpty {
                            Text("No matching loops")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(filteredHandles) { handle in
                                        ExistingHandleRow(handle: handle) {
                                            onSelectExisting(handle)
                                            dismiss()
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }

                Spacer()
            }
            .navigationTitle("Create Loop")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreateNew(normalizedName, echoConfig)
                        dismiss()
                    }
                    .disabled(!isValidName || nameAlreadyExists)
                }
            }
            .sheet(isPresented: $showingEchoConfig) {
                EchoConfigSheet(config: $echoConfig)
            }
        }
    }
}

/// Row displaying an existing handle for selection
struct ExistingHandleRow: View {
    let handle: Handle
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Loop indicator
                Circle()
                    .fill(Color.purple)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(handle.formattedName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

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
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(handle.intent.backgroundTint)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Handle Name Sheet") {
    HandleNameSheet(
        existingHandles: [
            Handle(name: "jokes", displayName: "Jokes", content: "Why did the chicken cross the road?", intent: .idea),
            Handle(name: "todos", displayName: "TODOs", content: "Buy groceries", intent: .task),
            Handle(name: "research", displayName: "Research", content: "According to the study...", intent: .evidence)
        ],
        onCreateNew: { name, echoConfig in
            print("Create new handle: @\(name), echo: \(String(describing: echoConfig))")
        },
        onSelectExisting: { handle in
            print("Selected existing: \(handle.formattedName)")
        }
    )
}
