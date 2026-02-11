import Foundation

/// Template type - node templates apply to nodes, page templates create full pages
enum TemplateType: String, Codable, CaseIterable {
    case node = "node"
    case page = "page"

    var displayName: String {
        switch self {
        case .node: return "Node"
        case .page: return "Page"
        }
    }

    var icon: String {
        switch self {
        case .node: return "app"
        case .page: return "doc.text"
        }
    }

    var description: String {
        switch self {
        case .node: return "Apply to nodes within a page"
        case .page: return "Create a full page structure"
        }
    }

    // Custom decoder to handle migration from "fold" to "node"
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "node", "fold":  // "fold" was the old name
            self = .node
        case "page":
            self = .page
        default:
            self = .node  // Default to node for unknown types
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
        templateType: TemplateType = .node,
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
    case node = "node"
    case line = "line"

    var displayName: String {
        switch self {
        case .node: return "Node"
        case .line: return "Line"
        }
    }

    var icon: String {
        switch self {
        case .node: return "circle"
        case .line: return "text.alignleft"
        }
    }

    // Custom decoder to handle migration from "fold" to "node"
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "node", "fold":  // "fold" was the old name
            self = .node
        case "line":
            self = .line
        default:
            self = .node  // Default to node for unknown types
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
        itemType: TemplateItemType = .node,
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
        itemType = try container.decodeIfPresent(TemplateItemType.self, forKey: .itemType) ?? .node
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

    var nodeTemplates: [SectionTemplate] {
        templates.filter { $0.templateType == .node }
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
