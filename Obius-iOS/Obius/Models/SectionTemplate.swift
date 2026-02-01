import Foundation

/// Template type - fold templates apply to folds, page templates create full pages
enum TemplateType: String, Codable, CaseIterable {
    case fold = "fold"
    case page = "page"

    var displayName: String {
        switch self {
        case .fold: return "Fold"
        case .page: return "Page"
        }
    }

    var icon: String {
        switch self {
        case .fold: return "rectangle.split.3x1"
        case .page: return "doc.text"
        }
    }

    var description: String {
        switch self {
        case .fold: return "Apply to folds within a page"
        case .page: return "Create a full page structure"
        }
    }
}

/// A template for creating pre-defined section structures in notes
struct SectionTemplate: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var templateType: TemplateType
    var sections: [TemplateSectionItem]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String = "New Template",
        templateType: TemplateType = .fold,
        sections: [TemplateSectionItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.templateType = templateType
        self.sections = sections
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Item type for template items
enum TemplateItemType: String, Codable, CaseIterable {
    case fold = "fold"
    case line = "line"

    var displayName: String {
        switch self {
        case .fold: return "Fold"
        case .line: return "Line"
        }
    }

    var icon: String {
        switch self {
        case .fold: return "rectangle"
        case .line: return "text.alignleft"
        }
    }
}

/// A single section item within a template
struct TemplateSectionItem: Codable, Identifiable, Hashable {
    let id: String
    var itemType: TemplateItemType
    var content: String
    var intent: IntentType
    var indentLevel: Int

    init(
        id: String = UUID().uuidString,
        itemType: TemplateItemType = .fold,
        content: String = "",
        intent: IntentType = .idea,
        indentLevel: Int = 0
    ) {
        self.id = id
        self.itemType = itemType
        self.content = content
        self.intent = intent
        self.indentLevel = indentLevel
    }

    // Custom decoder to handle existing templates without itemType
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        itemType = try container.decodeIfPresent(TemplateItemType.self, forKey: .itemType) ?? .fold
        content = try container.decode(String.self, forKey: .content)
        intent = try container.decode(IntentType.self, forKey: .intent)
        indentLevel = try container.decode(Int.self, forKey: .indentLevel)
    }

    private enum CodingKeys: String, CodingKey {
        case id, itemType, content, intent, indentLevel
    }
}

/// Manager for saving and loading templates
@MainActor
class TemplateManager: ObservableObject {
    static let shared = TemplateManager()

    @Published var templates: [SectionTemplate] = []

    private let userDefaultsKey = "savedSectionTemplates"

    init() {
        loadTemplates()
    }

    var foldTemplates: [SectionTemplate] {
        templates.filter { $0.templateType == .fold }
    }

    var pageTemplates: [SectionTemplate] {
        templates.filter { $0.templateType == .page }
    }

    func loadTemplates() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([SectionTemplate].self, from: data) else {
            templates = []
            return
        }
        templates = decoded
    }

    func saveTemplates() {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    func addTemplate(_ template: SectionTemplate) {
        templates.append(template)
        saveTemplates()
    }

    func updateTemplate(_ template: SectionTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            var updated = template
            updated.updatedAt = Date()
            templates[index] = updated
            saveTemplates()
        }
    }

    func deleteTemplate(_ templateId: String) {
        templates.removeAll { $0.id == templateId }
        saveTemplates()
    }
}
