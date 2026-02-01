import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Visual template creator - create templates using actual section bubbles
struct TemplateCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateManager = TemplateManager.shared

    @State private var templateName: String
    @State private var sections: [TemplateSectionItem]
    @State private var focusedSectionId: String?

    let existingTemplate: SectionTemplate?
    let onSave: (() -> Void)?

    init(existingTemplate: SectionTemplate? = nil, onSave: (() -> Void)? = nil) {
        self.existingTemplate = existingTemplate
        self.onSave = onSave
        _templateName = State(initialValue: existingTemplate?.name ?? "")
        _sections = State(initialValue: existingTemplate?.sections ?? [
            TemplateSectionItem(content: "", intent: .idea)
        ])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Template name header
                HStack {
                    TextField("Template Name", text: $templateName)
                        .font(.title2.bold())
                        .padding()
                }
                #if os(iOS)
                .background(Color(UIColor.systemBackground))
                #else
                .background(Color(NSColor.windowBackgroundColor))
                #endif

                Divider()

                // Section bubbles
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                            TemplateSectionBubble(
                                section: binding(for: index),
                                isFocused: focusedSectionId == section.id,
                                onFocus: { focusedSectionId = section.id },
                                onDelete: sections.count > 1 ? { deleteSection(at: index) } : nil,
                                onIndent: section.indentLevel < 5 ? { indentSection(at: index) } : nil,
                                onOutdent: section.indentLevel > 0 ? { outdentSection(at: index) } : nil
                            )
                        }

                        // Add section button
                        Button {
                            addSection()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add section")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(existingTemplate == nil ? "New Template" : "Edit Template")
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
                    .disabled(templateName.isEmpty)
                }
            }
        }
    }

    private func binding(for index: Int) -> Binding<TemplateSectionItem> {
        Binding(
            get: { sections[index] },
            set: { sections[index] = $0 }
        )
    }

    private func addSection() {
        let newSection = TemplateSectionItem(content: "", intent: .idea)
        withAnimation {
            sections.append(newSection)
            focusedSectionId = newSection.id
        }
    }

    private func deleteSection(at index: Int) {
        withAnimation {
            sections.remove(at: index)
        }
    }

    private func indentSection(at index: Int) {
        withAnimation {
            sections[index].indentLevel += 1
        }
    }

    private func outdentSection(at index: Int) {
        withAnimation {
            sections[index].indentLevel -= 1
        }
    }

    private func saveTemplate() {
        let template = SectionTemplate(
            id: existingTemplate?.id ?? UUID().uuidString,
            name: templateName,
            sections: sections,
            createdAt: existingTemplate?.createdAt ?? Date(),
            updatedAt: Date()
        )

        if existingTemplate != nil {
            templateManager.updateTemplate(template)
        } else {
            templateManager.addTemplate(template)
        }

        onSave?()
        dismiss()
    }
}

/// A section bubble for template editing - matches the look of real sections
struct TemplateSectionBubble: View {
    @Binding var section: TemplateSectionItem
    let isFocused: Bool
    let onFocus: () -> Void
    let onDelete: (() -> Void)?
    let onIndent: (() -> Void)?
    let onOutdent: (() -> Void)?

    private let railWidth: CGFloat = 3

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Intent Rail
            RoundedRectangle(cornerRadius: 2)
                .fill(section.intent.color)
                .frame(width: railWidth)

            // Content area
            VStack(alignment: .leading, spacing: 8) {
                // Text editor
                TextEditor(text: $section.content)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 40)
                    .fixedSize(horizontal: false, vertical: true)

                // Controls row
                HStack(spacing: 12) {
                    // Intent picker
                    Menu {
                        ForEach(IntentType.allCases, id: \.self) { intent in
                            Button {
                                section.intent = intent
                            } label: {
                                Label(intent.displayName, systemImage: intent.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: section.intent.icon)
                            Text(section.intent.displayName)
                        }
                        .font(.caption)
                        .foregroundStyle(section.intent.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(section.intent.color.opacity(0.15))
                        .clipShape(Capsule())
                    }

                    // Indent/Outdent
                    if let onOutdent = onOutdent {
                        Button {
                            onOutdent()
                        } label: {
                            Image(systemName: "decrease.indent")
                                .font(.caption)
                        }
                    }

                    if let onIndent = onIndent {
                        Button {
                            onIndent()
                        } label: {
                            Image(systemName: "increase.indent")
                                .font(.caption)
                        }
                    }

                    Spacer()

                    // Delete
                    if let onDelete = onDelete {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(section.intent.backgroundTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? section.intent.color.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.leading, CGFloat(section.indentLevel) * 24)
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus()
        }
    }
}

#Preview {
    TemplateCreatorView()
}
