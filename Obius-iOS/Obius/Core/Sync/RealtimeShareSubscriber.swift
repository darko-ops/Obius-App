import Foundation
import Combine
import Supabase

/// Subscribes to Supabase Realtime changes for live shared content.
/// Updates published properties when the shared note, sections, or comments change.
@MainActor
final class RealtimeShareSubscriber: ObservableObject {
    @Published var note: SharedNote?
    @Published var sections: [SharedSection]?
    @Published var comments: [SharedComment] = []

    private let noteId: String
    private let slug: String
    private let supabase = SupabaseManager.shared
    private var channel: RealtimeChannelV2?

    init(noteId: String, slug: String) {
        self.noteId = noteId
        self.slug = slug
    }

    func subscribe() {
        let channel = supabase.client.realtimeV2.channel("share_\(noteId)")

        // Listen for changes on the notes table filtered by noteId
        let noteChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "notes",
            filter: "id=eq.\(noteId)"
        )

        // Listen for changes on the sections table filtered by noteId
        let sectionChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "sections",
            filter: "note_id=eq.\(noteId)"
        )

        Task { [weak self] in
            for await change in noteChanges {
                guard let self else { return }
                self.handleNoteChange(change)
            }
        }

        Task { [weak self] in
            for await change in sectionChanges {
                guard let self else { return }
                self.handleSectionChange(change)
            }
        }

        Task {
            await channel.subscribe()
        }

        self.channel = channel
    }

    func unsubscribe() {
        guard let channel else { return }
        Task {
            await supabase.client.realtimeV2.removeChannel(channel)
        }
        self.channel = nil
    }

    // MARK: - Change Handlers

    private func handleNoteChange(_ change: AnyAction) {
        guard let record = change.record else { return }
        var interstitial: [String: String] = [:]
        if let raw = record["interstitial_content"]?.stringValue,
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            // Normalize keys to lowercase to match Postgres-returned section IDs
            interstitial = Dictionary(uniqueKeysWithValues: decoded.map { ($0.key.lowercased(), $0.value) })
        }
        let updatedNote = SharedNote(
            id: record["id"]?.stringValue ?? noteId,
            title: record["title"]?.stringValue,
            body: record["body"]?.stringValue ?? "",
            interstitialContent: interstitial
        )
        note = updatedNote
    }

    private func handleSectionChange(_ change: AnyAction) {
        // Re-fetch all sections for the note to maintain ordering.
        // Pass the share slug explicitly — passing an empty string here silently
        // returned no rows, so reorders/edits from the sharer never reached the viewer.
        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await ShareManager.shared.fetchSharedContent(slug: self.slug)
                if let updatedSections = response.sections {
                    self.sections = updatedSections
                }
            } catch {
                // Silently fail — the next change will retry
                print("RealtimeShareSubscriber: Failed to refresh sections: \(error)")
            }
        }
    }
}

// MARK: - Realtime Helpers

private extension AnyAction {
    var record: [String: AnyJSON]? {
        switch self {
        case .insert(let action):
            return action.record
        case .update(let action):
            return action.record
        case .delete:
            return nil
        default:
            return nil
        }
    }
}

private extension AnyJSON {
    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        default:
            return nil
        }
    }
}
