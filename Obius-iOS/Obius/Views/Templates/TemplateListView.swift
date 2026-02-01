import SwiftUI

/// View for listing, creating, and selecting templates
struct TemplateListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateManager = TemplateManager.shared

    @State private var showingCreator = false
    @State private var editingTemplate: SectionTemplate?

    let onApplyTemplate: ((SectionTemplate) -> Void)?

    init(onApplyTemplate: ((SectionTemplate) -> Void)? = nil) {
        self.onApplyTemplate = onApplyTemplate
    }

    var body: some View {
        NavigationStack {
            Group {
                if templateManager.templates.isEmpty {
                    emptyState
                } else {
                    templateList
                }
            }
            .navigationTitle("Templates")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreator = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreator) {
                TemplateCreatorView()
            }
            .sheet(item: $editingTemplate) { template in
                TemplateCreatorView(existingTemplate: template)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Templates")
                .font(.headline)

            Text("Create a template to quickly add pre-made sections to your notes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showingCreator = true
            } label: {
                Label("Create Template", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var templateList: some View {
        List {
            ForEach(templateManager.templates) { template in
                TemplateRow(
                    template: template,
                    onApply: onApplyTemplate != nil ? {
                        onApplyTemplate?(template)
                        dismiss()
                    } : nil,
                    onEdit: {
                        editingTemplate = template
                    }
                )
            }
            .onDelete(perform: deleteTemplates)
        }
    }

    private func deleteTemplates(at offsets: IndexSet) {
        for index in offsets {
            templateManager.deleteTemplate(templateManager.templates[index].id)
        }
    }
}

/// Row displaying a single template
struct TemplateRow: View {
    let template: SectionTemplate
    let onApply: (() -> Void)?
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Template name
            Text(template.name)
                .font(.headline)

            // Section preview
            HStack(spacing: 4) {
                ForEach(template.sections.prefix(5)) { section in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(section.intent.color)
                        .frame(width: 12, height: 12)
                }
                if template.sections.count > 5 {
                    Text("+\(template.sections.count - 5)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Section count
            Text("\(template.sections.count) section\(template.sections.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let onApply = onApply {
                onApply()
            } else {
                onEdit()
            }
        }
        .contextMenu {
            if onApply != nil {
                Button {
                    onApply?()
                } label: {
                    Label("Apply Template", systemImage: "plus.circle")
                }
            }

            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                TemplateManager.shared.deleteTemplate(template.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    TemplateListView()
}
