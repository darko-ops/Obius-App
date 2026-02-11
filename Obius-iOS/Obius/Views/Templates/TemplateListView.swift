import SwiftUI

/// View for listing, creating, and selecting templates
struct TemplateListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateManager = TemplateManager.shared

    @State private var showingTemplateTypePicker = false
    @State private var showingNodeCreator = false
    @State private var showingPageCreator = false
    @State private var editingTemplate: SectionTemplate?
    @State private var nodeTemplatesCollapsed = false
    @State private var pageTemplatesCollapsed = false

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
                    Menu {
                        Button {
                            showingNodeCreator = true
                        } label: {
                            Label("Node Template", systemImage: "circle")
                        }

                        Button {
                            showingPageCreator = true
                        } label: {
                            Label("Page Template", systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNodeCreator) {
                CreateNodeTemplateSheet()
            }
            .sheet(isPresented: $showingPageCreator) {
                CreatePageTemplateSheet()
            }
            .sheet(item: $editingTemplate) { template in
                if template.templateType == .node {
                    EditNodeTemplateSheet(template: template)
                } else {
                    EditPageTemplateSheet(template: template)
                }
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

            HStack(spacing: 12) {
                Button {
                    showingNodeCreator = true
                } label: {
                    Label("Node", systemImage: "circle")
                }
                .buttonStyle(.bordered)

                Button {
                    showingPageCreator = true
                } label: {
                    Label("Page", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var templateList: some View {
        List {
            // Node templates section
            if !templateManager.nodeTemplates.isEmpty {
                SwiftUI.Section {
                    if !nodeTemplatesCollapsed {
                        ForEach(templateManager.nodeTemplates) { template in
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
                        .onDelete { offsets in
                            deleteTemplates(from: templateManager.nodeTemplates, at: offsets)
                        }
                    }
                } header: {
                    CollapsibleSectionHeader(
                        title: "Node Templates",
                        count: templateManager.nodeTemplates.count,
                        isCollapsed: nodeTemplatesCollapsed,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                nodeTemplatesCollapsed.toggle()
                            }
                        }
                    )
                }
            }

            // Page templates section
            if !templateManager.pageTemplates.isEmpty {
                SwiftUI.Section {
                    if !pageTemplatesCollapsed {
                        ForEach(templateManager.pageTemplates) { template in
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
                        .onDelete { offsets in
                            deleteTemplates(from: templateManager.pageTemplates, at: offsets)
                        }
                    }
                } header: {
                    CollapsibleSectionHeader(
                        title: "Page Templates",
                        count: templateManager.pageTemplates.count,
                        isCollapsed: pageTemplatesCollapsed,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                pageTemplatesCollapsed.toggle()
                            }
                        }
                    )
                }
            }
        }
    }

    private func deleteTemplates(from templates: [SectionTemplate], at offsets: IndexSet) {
        for index in offsets {
            templateManager.deleteTemplate(templates[index].id)
        }
    }
}

/// Row displaying a single template
struct TemplateRow: View {
    let template: SectionTemplate
    let onApply: (() -> Void)?
    let onEdit: () -> Void

    private var previewText: String {
        if template.templateType == .node {
            // Show content preview for node templates
            return template.sections.first?.content ?? ""
        } else {
            // Show node count for page templates
            let count = template.sections.count
            return "\(count) \(count == 1 ? "item" : "items")"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: template.templateType.icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                // Template name
                Text(template.name)
                    .font(.headline)

                // Preview text
                if !previewText.isEmpty {
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Intent colors for page templates
            if template.templateType == .page {
                HStack(spacing: 2) {
                    ForEach(template.sections.prefix(4)) { section in
                        Circle()
                            .fill(section.intent.color)
                            .frame(width: 8, height: 8)
                    }
                    if template.sections.count > 4 {
                        Text("+\(template.sections.count - 4)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
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

/// Collapsible section header with toggle button
struct CollapsibleSectionHeader: View {
    let title: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Text(title)

            if isCollapsed {
                Text("(\(count))")
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                onToggle()
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.gray.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
        .textCase(nil)
    }
}

#Preview {
    TemplateListView()
}
