import Foundation
import Combine

/// Global manager for Handle Loop feature.
/// Observes all handles and provides real-time content updates across the app.
@MainActor
final class HandleManager: ObservableObject {
    static let shared = HandleManager()

    @Published private(set) var handles: [Handle] = []
    @Published private(set) var isLoaded: Bool = false

    private var handleRepository: HandleRepository?
    private var cancellables = Set<AnyCancellable>()

    // Cache for quick lookups
    private var handlesByName: [String: Handle] = [:]
    private var handlesById: [String: Handle] = [:]

    private init() {}

    /// Initialize the HandleManager with a repository
    /// This should be called once during app startup
    func initialize(handleRepository: HandleRepository) {
        self.handleRepository = handleRepository

        // Observe all handles and update caches
        handleRepository.observeAllHandles()
            .receive(on: DispatchQueue.main)
            .catch { error -> Just<[Handle]> in
                print("HandleManager: Error observing handles: \(error)")
                return Just([])
            }
            .sink { [weak self] handles in
                self?.updateHandles(handles)
            }
            .store(in: &cancellables)
    }

    private func updateHandles(_ newHandles: [Handle]) {
        handles = newHandles
        isLoaded = true

        // Update caches
        handlesByName = Dictionary(uniqueKeysWithValues: newHandles.map { ($0.name, $0) })
        handlesById = Dictionary(uniqueKeysWithValues: newHandles.map { ($0.id, $0) })
    }

    // MARK: - Quick Lookups (Synchronous)

    /// Get a handle by its ID (synchronous, from cache)
    func getHandle(id: String) -> Handle? {
        handlesById[id]
    }

    /// Get a handle by its name (case-insensitive, synchronous, from cache)
    func getHandle(named name: String) -> Handle? {
        let normalized = Handle.normalizeName(name)
        return handlesByName[normalized]
    }

    /// Get the content for a handle by ID
    func getContent(handleId: String) -> String? {
        handlesById[handleId]?.content
    }

    /// Check if a handle name exists
    func handleExists(name: String) -> Bool {
        let normalized = Handle.normalizeName(name)
        return handlesByName[normalized] != nil
    }

    // MARK: - Handle Detection

    /// Regex pattern to detect @mentions in text
    private static let mentionPattern = try! NSRegularExpression(
        pattern: "@([a-zA-Z0-9_]+)",
        options: []
    )

    /// Detect @mentions in text and return the handle names
    func detectMentions(in text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = Self.mentionPattern.matches(in: text, options: [], range: range)

        return matches.compactMap { match -> String? in
            guard let nameRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[nameRange])
        }
    }

    /// Find handles that match mentions in the text
    func findMentionedHandles(in text: String) -> [Handle] {
        let mentions = detectMentions(in: text)
        return mentions.compactMap { getHandle(named: $0) }
    }

    /// Check if text starts with a handle mention and return that handle
    func detectHandleAtStart(in text: String) -> Handle? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("@") else { return nil }

        // Extract the potential handle name (everything after @ until space or end)
        let afterAt = trimmed.dropFirst()
        let name = afterAt.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })

        if name.isEmpty { return nil }
        return getHandle(named: String(name))
    }

    // MARK: - Autocomplete Support

    /// Search handles for autocomplete (filters by query)
    func searchHandles(query: String) -> [Handle] {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty {
            return handles
        }

        return handles.filter { handle in
            handle.name.contains(normalized) || handle.displayName.lowercased().contains(normalized)
        }
    }

    // MARK: - Repository Actions (Async)

    /// Update handle content (updates the handle, all portals see it instantly via observation)
    func updateContent(handleId: String, content: String, richText: String? = nil) async throws {
        guard let repository = handleRepository else {
            throw HandleError.notFound("HandleManager not initialized")
        }
        try await repository.updateHandleContent(id: handleId, content: content, richText: richText)
    }

    /// Create a new handle
    func createHandle(name: String, content: String = "", intent: IntentType = .idea) async throws -> Handle {
        guard let repository = handleRepository else {
            throw HandleError.notFound("HandleManager not initialized")
        }
        return try await repository.createHandle(name: name, content: content, intent: intent)
    }

    /// Delete a handle
    func deleteHandle(id: String) async throws {
        guard let repository = handleRepository else {
            throw HandleError.notFound("HandleManager not initialized")
        }
        try await repository.deleteHandle(id: id)
    }
}
