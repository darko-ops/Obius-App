import Foundation

/// Payload passed from the main app to the iMessage extension via shared UserDefaults.
struct MessageSharePayload: Codable {
    let slug: String
    let shareType: String             // "live" or "commit"
    let title: String
    let creatorName: String?
    let commitShortId: String?        // "OBX-XXXX-XXXX"
    let sectionPreviews: [SectionPreview]
    let handleNames: [String]
    let noteId: String?               // For offline resolution in extension

    struct SectionPreview: Codable {
        let content: String           // First ~100 chars
        let contentType: String       // "text", "image", "audio", etc.
        let intent: String?           // "idea", "question", "task", "evidence"
    }

    // MARK: - Shared UserDefaults Helpers

    static let userDefaultsKey = "pendingMessageShare"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: "group.app.obius.shared")
    }

    func writeToSharedDefaults() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.sharedDefaults?.set(data, forKey: Self.userDefaultsKey)
    }

    static func readFromSharedDefaults() -> MessageSharePayload? {
        guard let data = sharedDefaults?.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(MessageSharePayload.self, from: data)
    }

    static func clearSharedDefaults() {
        sharedDefaults?.removeObject(forKey: userDefaultsKey)
    }
}
