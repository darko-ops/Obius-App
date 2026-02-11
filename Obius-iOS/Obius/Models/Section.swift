import Foundation
import GRDB

struct Section: Codable, Identifiable, Hashable {
    var id: String
    var noteId: String
    var content: String
    var contentType: ContentType
    var sectionType: SectionType  // fold or line

    // New: Section title (auto-generated or editable)
    var title: String?

    // Hierarchy & ordering
    var parentSectionId: String?
    var orderKey: String
    var indentLevel: Int

    // UI state
    var isCollapsed: Bool
    var isLocked: Bool  // Requires biometric to view
    var isTemplateContent: Bool  // Has template text - template is bold and uneditable
    var templatePrefix: String?  // Bold, uneditable template text (e.g., "Name:")
    var contentBefore: String?   // Editable content before template text
    var intent: IntentType

    // Handle Loop - links this section to a global handle (portal mode)
    var handleId: String?

    // Timestamps
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    // Sync fields
    var localVersion: Int
    var serverVersion: Int?
    var syncStatus: SyncStatus
    
    init(
        id: String = UUID().uuidString,
        noteId: String,
        content: String = "",
        contentType: ContentType = .text,
        sectionType: SectionType = .fold,
        title: String? = nil,
        parentSectionId: String? = nil,
        orderKey: String,
        indentLevel: Int = 0,
        isCollapsed: Bool = false,
        isLocked: Bool = false,
        isTemplateContent: Bool = false,
        templatePrefix: String? = nil,
        contentBefore: String? = nil,
        intent: IntentType = .idea,
        handleId: String? = nil,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        deletedAt: Int64? = nil,
        localVersion: Int = 1,
        serverVersion: Int? = nil,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.noteId = noteId
        self.content = content
        self.contentType = contentType
        self.sectionType = sectionType
        self.title = title
        self.parentSectionId = parentSectionId
        self.orderKey = orderKey
        self.indentLevel = indentLevel
        self.isCollapsed = isCollapsed
        self.isLocked = isLocked
        self.isTemplateContent = isTemplateContent
        self.templatePrefix = templatePrefix
        self.contentBefore = contentBefore
        self.intent = intent
        self.handleId = handleId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.localVersion = localVersion
        self.serverVersion = serverVersion
        self.syncStatus = syncStatus
    }

    /// Whether this section is a portal to a handle (displays handle content)
    var isPortal: Bool {
        handleId != nil
    }
    
    var isDeleted: Bool {
        deletedAt != nil
    }
    
    var isEmpty: Bool {
        let full = (contentBefore ?? "") + (templatePrefix ?? "") + content
        return full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Full display content including contentBefore, template prefix, and content after
    var fullContent: String {
        (contentBefore ?? "") + (templatePrefix ?? "") + content
    }

    /// One-line preview for ghost summaries when collapsed
    var preview: String {
        let trimmed = fullContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        if firstLine.count <= 80 {
            return firstLine
        }
        return String(firstLine.prefix(80)) + "…"
    }

    /// Display title - uses explicit title, auto-generated from content, or default
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        // Auto-generate from first line of content (including template prefix)
        let firstLine = fullContent.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        if firstLine.isEmpty {
            return "Untitled Section"
        }
        return String(firstLine.prefix(50))
    }
}

// MARK: - GRDB Conformance

extension Section: FetchableRecord, PersistableRecord {
    static let databaseTableName = "sections"
    
    enum Columns: String, ColumnExpression {
        case id, noteId, content, contentType, sectionType
        case title
        case parentSectionId, orderKey, indentLevel
        case isCollapsed, isLocked, isTemplateContent, templatePrefix, contentBefore, intent
        case handleId
        case createdAt, updatedAt, deletedAt
        case localVersion, serverVersion, syncStatus
    }

    // Handle relationship
    static let handle = belongsTo(Handle.self)
    
    // Relationships
    static let note = belongsTo(Note.self)
    static let parentSection = belongsTo(Section.self, key: "parentSection", using: ForeignKey(["parentSectionId"]))
    static let childSections = hasMany(Section.self, key: "childSections", using: ForeignKey(["parentSectionId"]))
    
    var note: QueryInterfaceRequest<Note> {
        request(for: Section.note)
    }
    
    var childSections: QueryInterfaceRequest<Section> {
        request(for: Section.childSections)
            .filter(Section.Columns.deletedAt == nil)
            .order(Section.Columns.orderKey)
    }
}

// MARK: - Mutations

extension Section {
    mutating func touch() {
        updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        localVersion += 1
        syncStatus = .pending
    }
    
    mutating func softDelete() {
        deletedAt = Int64(Date().timeIntervalSince1970 * 1000)
        touch()
    }
    
    /// Toggle the locked state (requires biometric authentication first if unlocking)
    mutating func toggleLocked() {
        isLocked.toggle()
        touch()
    }
    
    /// Update the section's intent type
    mutating func setIntent(_ newIntent: IntentType) {
        intent = newIntent
        touch()
    }
}

// MARK: - NoteWithSections

struct NoteWithSections: Identifiable {
    let note: Note
    var sections: [Section]
    
    var id: String { note.id }
    
    var preview: String {
        sections.first?.preview ?? ""
    }
    
    var sectionCount: Int {
        sections.count
    }
}
