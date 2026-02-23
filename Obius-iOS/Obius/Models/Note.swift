import Foundation
import GRDB

struct Note: Codable, Identifiable, Hashable {
    var id: String
    var title: String?
    var aiTitle: String?
    var body: String  // Direct note content (before any sections)
    var bodyRichText: String?  // Base64-encoded RTF data for rich text body
    var interstitialContent: [String: String]  // Text between sections, keyed by "after_<sectionId>" or "end"
    var interstitialRichContent: [String: String]  // Base64-encoded RTF data for interstitial rich text, same keys
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?
    var isPinned: Bool
    var groupName: String?  // Name of the group this note belongs to (nil = ungrouped)
    var intent: IntentType  // Renamed from colorIntent
    var tags: [String]  // Hashtag labels for the page
    var aiTags: [String]  // AI-generated concept tags
    var moduleId: String?  // Module (folder) this note belongs to

    // Sync fields
    var localVersion: Int
    var serverVersion: Int?
    var syncStatus: SyncStatus
    var lastSyncedAt: Int64?

    init(
        id: String = UUID().uuidString,
        title: String? = nil,
        aiTitle: String? = nil,
        body: String = "",
        bodyRichText: String? = nil,
        interstitialContent: [String: String] = [:],
        interstitialRichContent: [String: String] = [:],
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        deletedAt: Int64? = nil,
        isPinned: Bool = false,
        groupName: String? = nil,
        intent: IntentType = .idea,
        tags: [String] = [],
        aiTags: [String] = [],
        moduleId: String? = nil,
        localVersion: Int = 1,
        serverVersion: Int? = nil,
        syncStatus: SyncStatus = .pending,
        lastSyncedAt: Int64? = nil
    ) {
        self.id = id
        self.title = title
        self.aiTitle = aiTitle
        self.body = body
        self.bodyRichText = bodyRichText
        self.interstitialContent = interstitialContent
        self.interstitialRichContent = interstitialRichContent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isPinned = isPinned
        self.groupName = groupName
        self.intent = intent
        self.tags = tags
        self.aiTags = aiTags
        self.moduleId = moduleId
        self.localVersion = localVersion
        self.serverVersion = serverVersion
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
    }

    // Helper to get text after a specific section
    func textAfterSection(_ sectionId: String) -> String {
        interstitialContent["after_\(sectionId)"] ?? ""
    }

    // Helper to get text at the end (after all sections)
    var endText: String {
        interstitialContent["end"] ?? ""
    }
    
    var displayTitle: String {
        displayTitle(sections: [])
    }

    func displayTitle(sections: [Section]) -> String {
        // User-set or AI-generated title takes priority
        if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
        if let t = aiTitle, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }

        // Auto-title from first 3 words of text content
        if let words = firstWords(from: sections, count: 3) { return words }

        // No text — derive title from media content
        if let mediaTitle = mediaTitle(from: sections) { return mediaTitle }

        // Absolute fallback
        return "Untitled"
    }

    /// Derives a title from media sections: Snapshot, Gallery, Audio, Audio Log, or Collection.
    private func mediaTitle(from sections: [Section]) -> String? {
        let mediaSections = sections.filter { $0.contentType == .image || $0.contentType == .audio }
        guard !mediaSections.isEmpty else { return nil }

        let imageSections = mediaSections.filter { $0.contentType == .image }
        let audioSections = mediaSections.filter { $0.contentType == .audio }
        let timeStamp = createdTimeString

        let hasImages = !imageSections.isEmpty
        let hasAudio = !audioSections.isEmpty

        if hasImages && hasAudio {
            return "Collection"
        } else if hasImages {
            if imageSections.count == 1 {
                // Single image section — check if it has multiple photos
                let photoCount = imageSections[0].content
                    .split(separator: ",")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .count
                return photoCount <= 1 ? "Snapshot \(timeStamp)" : "Gallery"
            }
            return "Gallery"
        } else {
            return audioSections.count == 1 ? "Audio \(timeStamp)" : "Audio Log"
        }
    }

    private var createdTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: createdDate)
    }

    /// Finds the first `count` words from body, interstitial, or section text content.
    private func firstWords(from sections: [Section], count: Int) -> String? {
        var sources: [String] = []

        // Body text first
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty { sources.append(trimmedBody) }

        if !sections.isEmpty {
            // Sections available — scan in reading order
            for section in sections {
                if section.contentType == .text || section.contentType == .checklist || section.contentType == .code || section.contentType == .quote {
                    let t = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { sources.append(t) }
                }
                let interstitial = textAfterSection(section.id).trimmingCharacters(in: .whitespacesAndNewlines)
                if !interstitial.isEmpty { sources.append(interstitial) }
            }
        } else {
            // No sections provided — scan all interstitial values directly
            for (_, value) in interstitialContent {
                let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { sources.append(t) }
            }
        }

        let endTrimmed = endText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endTrimmed.isEmpty { sources.append(endTrimmed) }

        // Collect words across sources until we have enough, skipping hashtags
        var words: [String] = []
        for source in sources {
            let sourceWords = source.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            for word in sourceWords {
                // Skip hashtag words (e.g. #tag)
                if word.hasPrefix("#") { continue }
                words.append(word)
                if words.count >= count { break }
            }
            if words.count >= count { break }
        }

        guard !words.isEmpty else { return nil }
        return words.prefix(count).joined(separator: " ")
    }
    
    var isDeleted: Bool {
        deletedAt != nil
    }
    
    var createdDate: Date {
        Date(timeIntervalSince1970: Double(createdAt) / 1000)
    }
    
    var updatedDate: Date {
        Date(timeIntervalSince1970: Double(updatedAt) / 1000)
    }
}

// MARK: - GRDB Conformance

extension Note: FetchableRecord, PersistableRecord {
    static let databaseTableName = "notes"
    
    enum Columns: String, ColumnExpression {
        case id, title, aiTitle, body, bodyRichText, interstitialContent, interstitialRichContent, createdAt, updatedAt, deletedAt
        case isPinned, groupName, intent, tags, aiTags, moduleId, localVersion, serverVersion
        case syncStatus, lastSyncedAt
    }
    
    // Relationship to sections
    static let sections = hasMany(Section.self)
    
    var sections: QueryInterfaceRequest<Section> {
        request(for: Note.sections)
            .filter(Section.Columns.deletedAt == nil)
            .order(Section.Columns.orderKey)
    }
}

// MARK: - Mutations

extension Note {
    mutating func touch() {
        updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        localVersion += 1
        syncStatus = .pending
    }
    
    mutating func softDelete() {
        deletedAt = Int64(Date().timeIntervalSince1970 * 1000)
        touch()
    }
    
    mutating func setIntent(_ newIntent: IntentType) {
        intent = newIntent
        touch()
    }
}
