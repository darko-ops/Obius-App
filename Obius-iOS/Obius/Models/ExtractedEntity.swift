import Foundation

struct ExtractedEntity: Identifiable, Codable {
    var id: String { name }
    let name: String        // e.g. "Grocery List"
    let handleName: String  // e.g. "grocery_list" (normalized)
    let reason: String      // Why this should be a Loop
    let sectionId: String?  // Which section contains this entity
}
