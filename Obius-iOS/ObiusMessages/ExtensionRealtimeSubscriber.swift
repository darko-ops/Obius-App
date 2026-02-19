import Foundation
import Combine
import Supabase

/// Subscribes to Supabase Realtime changes for live shared content in the iMessage extension.
/// Follows the pattern of RealtimeShareSubscriber but uses ExtensionSupabaseClient.
@MainActor
final class ExtensionRealtimeSubscriber: ObservableObject {
    @Published var note: SharedNote?
    @Published var sections: [SharedSection]?
    @Published var comments: [SharedComment] = []
    @Published var interactions: [SharedInteraction] = []

    private let noteId: String
    private let shareLinkId: String
    private let supabase = ExtensionSupabaseClient.shared
    private var channel: RealtimeChannelV2?

    init(noteId: String, shareLinkId: String) {
        self.noteId = noteId
        self.shareLinkId = shareLinkId
    }

    func subscribe() {
        let channel = supabase.client.realtimeV2.channel("ext_share_\(noteId)")

        // Listen for note changes
        let noteChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "notes",
            filter: .eq("id", value: noteId)
        )

        // Listen for section changes
        let sectionChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "sections",
            filter: .eq("note_id", value: noteId)
        )

        // Listen for new comments on this share
        let commentChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "comments",
            filter: .eq("share_link_id", value: shareLinkId)
        )

        // Listen for interaction changes (handshakes)
        let interactionChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "node_interactions",
            filter: .eq("share_link_id", value: shareLinkId)
        )

        Task { [weak self] in
            for await change in noteChanges {
                guard let self else { return }
                self.handleNoteChange(change)
            }
        }

        Task { [weak self] in
            for await _ in sectionChanges {
                guard let self else { return }
                await self.handleSectionChange()
            }
        }

        Task { [weak self] in
            for await _ in commentChanges {
                guard let self else { return }
                await self.refreshComments()
            }
        }

        Task { [weak self] in
            for await _ in interactionChanges {
                guard let self else { return }
                await self.refreshInteractions()
            }
        }

        Task {
            try? await channel.subscribeWithError()
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
        guard let record = extractRecord(from: change) else { return }
        let updatedNote = SharedNote(
            id: record["id"]?.extractString ?? noteId,
            title: record["title"]?.extractString,
            body: record["body"]?.extractString ?? ""
        )
        note = updatedNote
    }

    private func handleSectionChange() async {
        // Re-fetch all sections for the note to maintain ordering
        do {
            let updatedSections: [SharedSection] = try await supabase.client
                .from("sections")
                .select()
                .eq("note_id", value: noteId)
                .is("deleted_at", value: nil)
                .order("order_key")
                .execute()
                .value

            sections = updatedSections
        } catch {
            print("[ExtensionRealtime] Failed to refresh sections: \(error)")
        }
    }

    private func refreshComments() async {
        do {
            let updatedComments: [SharedComment] = try await supabase.client
                .from("comments")
                .select()
                .eq("share_link_id", value: shareLinkId)
                .is("deleted_at", value: nil)
                .execute()
                .value

            comments = updatedComments
        } catch {
            print("[ExtensionRealtime] Failed to refresh comments: \(error)")
        }
    }

    func refreshInteractions() async {
        do {
            let updatedInteractions: [SharedInteraction] = try await supabase.client
                .from("node_interactions")
                .select()
                .eq("share_link_id", value: shareLinkId)
                .execute()
                .value

            interactions = updatedInteractions
        } catch {
            print("[ExtensionRealtime] Failed to refresh interactions: \(error)")
        }
    }

    // MARK: - Helpers

    private func extractRecord(from action: AnyAction) -> [String: AnyJSON]? {
        switch action {
        case .insert(let a): return a.record
        case .update(let a): return a.record
        case .delete: return nil
        }
    }
}

// MARK: - AnyJSON Helpers

private extension AnyJSON {
    var extractString: String? {
        switch self {
        case .string(let value): return value
        default: return nil
        }
    }
}
