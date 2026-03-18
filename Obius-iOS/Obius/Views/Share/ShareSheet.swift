import SwiftUI

struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    let noteId: String

    @State private var shareLinks: [ShareLink] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var createdShareLink: ShareLink?
    @State private var showingCommitPicker = false

    private var isAuthenticated: Bool {
        SupabaseManager.shared.isAuthenticated
    }

    var body: some View {
        NavigationStack {
            List {
                if !isAuthenticated {
                    signInPrompt
                }

                if !shareLinks.isEmpty {
                    activeLinksSection
                }

                if isAuthenticated {
                    createLinkSection
                }

                if let error = errorMessage {
                    SwiftUI.Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadShareLinks() }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            .sheet(item: $createdShareLink) { link in
                ShareLinkCreatedView(shareLink: link)
            }
            .sheet(isPresented: $showingCommitPicker) {
                CommitPickerForShare(noteId: noteId) { commit in
                    showingCommitPicker = false
                    Task { await createCommitShare(commit: commit) }
                }
            }
        }
    }

    // MARK: - Sections

    private var signInPrompt: some View {
        SwiftUI.Section {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Sign in to share")
                    .font(.subheadline.weight(.medium))
                Text("Create shareable links that anyone can view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var activeLinksSection: some View {
        SwiftUI.Section("Active Links") {
            ForEach(shareLinks.filter { $0.isActive }) { link in
                ShareLinkRow(shareLink: link) {
                    Task { await deactivateLink(link) }
                }
            }
        }
    }

    private var createLinkSection: some View {
        SwiftUI.Section {
            Button {
                Task { await createLiveShare() }
            } label: {
                Label("Live Link", systemImage: "antenna.radiowaves.left.and.right")
            }
            .disabled(isLoading)

            Button {
                showingCommitPicker = true
            } label: {
                Label("Version Link", systemImage: "doc.zipper")
            }
            .disabled(isLoading)
        } header: {
            Text("Create New Link")
        } footer: {
            Text("Live links update in real-time as you edit. Version links are permanent snapshots.")
        }
    }

    // MARK: - Actions

    private func loadShareLinks() async {
        do {
            shareLinks = try await ShareManager.shared.getShareLinks(noteId: noteId)
        } catch {
            print("ShareSheet: Error loading links: \(error)")
        }
    }

    private func createLiveShare() async {
        isLoading = true
        errorMessage = nil
        do {
            // Fetch current note and sections to push to Supabase
            guard let note = try await appState.noteRepository.getNote(id: noteId) else {
                errorMessage = "Note not found"
                isLoading = false
                return
            }
            let sections = try await appState.sectionRepository.getSections(noteId: noteId)

            let link = try await ShareManager.shared.createLiveShare(
                noteId: noteId,
                note: note,
                sections: sections
            )
            createdShareLink = link
            await loadShareLinks()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func createCommitShare(commit: Commit) async {
        isLoading = true
        errorMessage = nil
        do {
            let content = try await loadCommitContent(commit: commit)
            let link = try await ShareManager.shared.createCommitShare(
                commitHash: commit.hash,
                commitName: commit.name,
                commitShortId: commit.shortId,
                commitContent: content
            )
            createdShareLink = link
            await loadShareLinks()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadCommitContent(commit: Commit) async throws -> String {
        let coldStore = appState.coldStore
        let content = try coldStore.readCommit(hash: commit.hash)
        let data = try JSONEncoder().encode(content)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ShareError.encodingError
        }
        return jsonString
    }

    private func deactivateLink(_ link: ShareLink) async {
        do {
            try await ShareManager.shared.deactivateShare(id: link.id)
            await loadShareLinks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

