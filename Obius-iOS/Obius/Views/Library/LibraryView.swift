import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var handleManager = HandleManager.shared
    @StateObject private var echoManager = EchoManager.shared
    @State private var selectedSection: LibrarySection = .commits
    @State private var searchQuery = ""
    @State private var showingEditProfile = false
    @State private var selectedEcho: Echo?
    @ObservedObject private var profileImages = ProfileImageManager.shared
    var pendingEchoId: Binding<String?> = .constant(nil)

    enum LibrarySection: String, CaseIterable {
        case loops = "Loops"
        case commits = "Versions"

        var icon: String {
            switch self {
            case .loops: return "link"
            case .commits: return "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // User Profile Section
                userProfileSection

                Divider()
                    .padding(.horizontal)

                // Search bar
                RoundedSearchBar(text: $searchQuery, placeholder: "Search \(selectedSection.rawValue.lowercased())")
                    .padding(.horizontal)

                // Section filter
                HStack(spacing: 20) {
                    ForEach(LibrarySection.allCases, id: \.self) { section in
                        let isSelected = selectedSection == section
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedSection = section
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Text(section.rawValue)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(isSelected ? .primary : .secondary)

                                // Underline
                                Rectangle()
                                    .fill(isSelected ? Color.primary : .clear)
                                    .frame(height: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                // Content
                switch selectedSection {
                case .loops:
                    LoopsListView(searchQuery: searchQuery)
                case .commits:
                    CommitsListView(searchQuery: searchQuery)
                }
            }
            .padding(.bottom)
        }
        .background(Color.systemBackground)
        .ignoresSafeArea(.container, edges: .top)
        #if os(iOS)
        .navigationBarHidden(true)
        #elseif os(macOS)
        .navigationTitle("")
        #endif
        .onChange(of: selectedSection) { _, _ in
            searchQuery = ""
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    KeyboardHelper.dismiss()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
            }
        }
        #endif
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
                .environmentObject(authManager)
        }
        .sheet(item: $selectedEcho) { echo in
            EchoDetailSheet(echo: echo)
        }
        .onChange(of: pendingEchoId.wrappedValue) { _, echoId in
            guard let echoId else { return }
            if let echo = echoManager.activeEchoes.first(where: { $0.id == echoId }) {
                selectedEcho = echo
            }
            pendingEchoId.wrappedValue = nil
        }
    }

    // MARK: - Active Echoes Section

    // MARK: - User Profile Section

    private var userProfileSection: some View {
        VStack(spacing: 0) {
            // Banner — extends to very top of screen
            ZStack(alignment: .bottom) {
                GeometryReader { geo in
                    let minY = geo.frame(in: .global).minY
                    let extraHeight = max(minY, 0)

                    if let banner = profileImages.bannerImage {
                        platformImage(banner)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: 160 + extraHeight)
                            .clipped()
                            .offset(y: -extraHeight)
                    } else {
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: geo.size.width, height: 160 + extraHeight)
                        .offset(y: -extraHeight)
                    }
                }
                .frame(height: 160)

                // Profile avatar overlapping the banner
                profileAvatar
                    .offset(y: 40)
            }

            // User info
            VStack(spacing: 4) {
                if authManager.isAuthenticated, let user = authManager.currentUser {
                    Text(user.displayName ?? "User")
                        .font(.title3.weight(.semibold))

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Text(user.email ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not Signed In")
                        .font(.title3.weight(.semibold))

                    Text("Sign in to sync your notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 48)
        }
        .frame(maxWidth: .infinity)
    }

    private var profileAvatar: some View {
        ZStack {
            if let avatar = profileImages.profileImage {
                platformImage(avatar)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.systemBackground, lineWidth: 3))
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay(Circle().stroke(Color.systemBackground, lineWidth: 3))
                    .overlay {
                        if authManager.isAuthenticated {
                            Text(userInitials)
                                .font(.title.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Image(systemName: "person.fill")
                                .font(.title)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
            }
        }
        .contentShape(Circle())
        .onTapGesture {
            showingEditProfile = true
        }
    }

    private var userInitials: String {
        guard let name = authManager.currentUser?.displayName else { return "?" }
        let components = name.components(separatedBy: " ")
        let initials = components.compactMap { $0.first }.prefix(2)
        return String(initials).uppercased()
    }
}

// MARK: - Loops List View

struct LoopsListView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var handleManager = HandleManager.shared
    @State private var showingCreateSheet = false
    @State private var selectedHandle: Handle?
    var searchQuery: String = ""

    private var filteredHandles: [Handle] {
        if searchQuery.isEmpty {
            return handleManager.handles
        }
        return handleManager.handles.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery) ||
            $0.preview.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Create loop pill (matches commit filter bar style)
            HStack(spacing: 4) {
                Button {
                    showingCreateSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                        Text("New Loop")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }

            if handleManager.handles.isEmpty {
                emptyState
            } else if filteredHandles.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                loopsList
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateLoopSheet()
        }
        .sheet(item: $selectedHandle) { handle in
            LoopDetailSheet(handle: handle)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "link")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Loops")
                .font(.headline)
            Text("Loops sync content across sections")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var loopsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredHandles) { handle in
                LoopRowView(handle: handle)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color.systemBackground)
                    .cornerRadius(12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedHandle = handle
                    }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Loop Row View

struct LoopRowView: View {
    let handle: Handle

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = Date(timeIntervalSince1970: Double(handle.updatedAt) / 1000)
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var hasEcho: Bool {
        EchoManager.shared.activeEchoes.contains { $0.handleId == handle.id && $0.isActive }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Spine: 4px wide, intent-colored
            RoundedRectangle(cornerRadius: 2)
                .fill(handle.intent.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                // Row 1: Name + echo tag + time
                HStack(spacing: 6) {
                    Text(handle.formattedName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if hasEcho {
                        HStack(spacing: 2) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 7))
                            Text("echo")
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.yellow.opacity(0.12)))
                    }

                    Spacer()

                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Row 2: Content preview
                if !handle.preview.isEmpty {
                    Text(handle.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 10)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Create Loop Sheet

struct CreateLoopSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var handleManager = HandleManager.shared
    @State private var name = ""
    @State private var content = ""
    @State private var intent: IntentType = .idea
    @State private var errorMessage: String?

    private var isValid: Bool {
        Handle.validateName(name) == nil && !handleManager.handleExists(name: name)
    }

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section("Name") {
                    HStack {
                        Text("@")
                            .foregroundStyle(.secondary)
                        TextField("LoopName", text: $name)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                    }

                    if let error = Handle.validateName(name), !name.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if handleManager.handleExists(name: name) {
                        Text("This name is already taken")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                SwiftUI.Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 100)
                }

                SwiftUI.Section("Intent") {
                    Picker("Intent", selection: $intent) {
                        ForEach(IntentType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("Create Loop")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createLoop()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func createLoop() {
        Task {
            do {
                _ = try await handleManager.createHandle(name: name, content: content, intent: intent)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Loop Detail Sheet

struct LoopDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    let handle: Handle

    @StateObject private var handleManager = HandleManager.shared
    @State private var content: String
    @State private var intent: IntentType
    @State private var references: [(note: Note, section: Section)] = []

    init(handle: Handle) {
        self.handle = handle
        _content = State(initialValue: handle.content)
        _intent = State(initialValue: handle.intent)
    }

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section("Loop") {
                    Text(handle.formattedName)
                        .font(.headline)
                }

                SwiftUI.Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                }

                SwiftUI.Section("Intent") {
                    Picker("Intent", selection: $intent) {
                        ForEach(IntentType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                SwiftUI.Section("Appears In") {
                    if references.isEmpty {
                        Text("Not referenced in any pages")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(references, id: \.section.id) { ref in
                            NavigationLink {
                                NoteEditorView(noteId: ref.note.id, targetSectionId: ref.section.id)
                                    .environmentObject(appState)
                            } label: {
                                loopReferenceRow(note: ref.note, section: ref.section)
                            }
                        }
                    }
                }

                SwiftUI.Section("Actions") {
                    Button(role: .destructive) {
                        deleteLoop()
                    } label: {
                        Label("Delete Loop", systemImage: "trash")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Loop")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
            .task {
                await loadReferences()
            }
        }
    }

    @ViewBuilder
    private func loopReferenceRow(note: Note, section: Section) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(note.intent.color)
                .frame(width: 4, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                let preview = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !preview.isEmpty {
                    Text(String(preview.prefix(60)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(relativeTime(for: section.updatedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func relativeTime(for timestamp: Int64) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadReferences() async {
        guard let sections = try? await appState.handleRepository.getSectionsWithHandle(handleId: handle.id) else { return }

        let notes = appState.noteRepository.notes
        var refs: [(note: Note, section: Section)] = []
        var seenNoteIds: Set<String> = []

        for section in sections {
            guard !seenNoteIds.contains(section.noteId),
                  let note = notes.first(where: { $0.id == section.noteId }) else { continue }
            seenNoteIds.insert(section.noteId)
            refs.append((note: note, section: section))
        }

        await MainActor.run {
            references = refs
        }
    }

    private func saveChanges() {
        Task {
            try? await handleManager.updateContent(handleId: handle.id, content: content)
            dismiss()
        }
    }

    private func deleteLoop() {
        Task {
            try? await handleManager.deleteHandle(id: handle.id)
            dismiss()
        }
    }
}

// MARK: - Commits List View

/// A commit item for display in the commits list.
struct CommitListItem: Identifiable {
    let commit: Commit
    let noteName: String

    var id: String { "page_\(commit.id)" }
    var createdAt: Int64 { commit.createdAt }
}

enum CommitFilter: String, CaseIterable {
    case all
    case manual
    case auto
    case ai

    var icon: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .manual: return "arrow.trianglehead.branch"
        case .auto: return "clock.fill"
        case .ai: return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .white
        case .manual: return .accentColor
        case .auto: return .orange
        case .ai: return .purple
        }
    }
}

struct CommitsListView: View {
    @EnvironmentObject var appState: AppState
    @State private var commits: [Commit] = []
    @State private var noteNames: [String: String] = [:]
    @State private var isLoading = true
    @State private var selectedCommit: Commit?
    @State private var selectedFilter: CommitFilter = .all
@State private var shareSheetLink: ShareLink?
    @State private var sharePreview: String = ""
    @State private var shareError: String?
    @State private var isSharing = false
    @State private var commitViewCounts: [String: Int] = [:]
    var searchQuery: String = ""

    private var allItems: [CommitListItem] {
        commits
            .map { CommitListItem(commit: $0, noteName: noteNames[$0.noteId] ?? $0.name ?? "Archived Version") }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredItems: [CommitListItem] {
        var items = allItems

        switch selectedFilter {
        case .all:
            break
        case .ai:
            items = items.filter { $0.commit.name?.hasPrefix("AI:") ?? false }
        case .auto:
            items = items.filter { $0.commit.isAutoCommit && !($0.commit.name?.hasPrefix("AI:") ?? false) }
        case .manual:
            items = items.filter { !$0.commit.isAutoCommit && !($0.commit.name?.hasPrefix("AI:") ?? false) }
        }

        if !searchQuery.isEmpty {
            items = items.filter { item in
                (item.commit.name ?? "").localizedCaseInsensitiveContains(searchQuery) ||
                    item.noteName.localizedCaseInsensitiveContains(searchQuery) ||
                    item.commit.shortId.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        return items
    }

    var body: some View {
        VStack(spacing: 12) {

            // Filter bar
            commitFilterBar

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else if allItems.isEmpty {
                emptyState
            } else if filteredItems.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                commitsList
            }
        }
        .task {
            await loadCommits()
        }
        .sheet(item: $selectedCommit) { commit in
            CommitDetailSheet(commit: commit, noteName: noteNames[commit.noteId]) {
                commits.removeAll { $0.id == commit.id }
            }
        }
        .sheet(item: $shareSheetLink) { link in
            NodeShareSheet(
                url: URL(string: link.url)!,
                title: link.commitName ?? "Version Snapshot",
                preview: sharePreview
            )
        }
        .overlay {
            if isSharing {
                ProgressView("Sharing...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
    }

    private var commitFilterBar: some View {
        HStack(spacing: 4) {
            ForEach(CommitFilter.allCases, id: \.self) { filter in
                let isSelected = selectedFilter == filter
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = filter
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 9))
                        if isSelected {
                            Text(filter.rawValue.capitalized)
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .foregroundStyle(isSelected ? filter.tint : .secondary)
                    .padding(.horizontal, isSelected ? 10 : 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isSelected ? filter.tint.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Versions")
                .font(.headline)
            Text("Versions save snapshots of your notes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var commitsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                CommitRowView(commit: item.commit, noteName: item.noteName, viewCount: commitViewCounts[item.commit.hash] ?? 0, isFirst: index == 0, isLast: index == filteredItems.count - 1)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color.systemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCommit = item.commit
                    }
                    .contextMenu {
                        Button {
                            Task { await shareCommit(item.commit) }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            ClipboardHelper.copy(item.commit.shortId)
                        } label: {
                            Label("Copy ID", systemImage: "doc.on.doc")
                        }

                        Button {
                            ClipboardHelper.copy(item.commit.hash)
                        } label: {
                            Label("Copy Hash", systemImage: "number")
                        }

                        Divider()

                        Button(role: .destructive) {
                            Task { await hideCommit(item.commit) }
                        } label: {
                            Label("Hide", systemImage: "eye.slash")
                        }
                    }
            }
        }
        .padding(.horizontal)
    }

    private func loadCommits() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load page commits
            commits = try await appState.commitRepository.getVisibleCommits()

            // Load note names for display
            for commit in commits {
                if noteNames[commit.noteId] == nil {
                    if let note = try await appState.noteRepository.getNote(id: commit.noteId) {
                        noteNames[commit.noteId] = note.displayTitle
                    }
                }
            }

            // Load view counts from share links
            let allShareLinks = try await appState.shareLinkRepository.getAllShareLinks()
            var counts: [String: Int] = [:]
            for link in allShareLinks {
                if let hash = link.commitHash, link.viewCount > 0 {
                    counts[hash, default: 0] += link.viewCount
                }
            }
            commitViewCounts = counts

        } catch {
            print("Failed to load commits: \(error)")
        }
    }

    private func hideCommit(_ commit: Commit) async {
        do {
            try await appState.commitRepository.setHidden(true, id: commit.id)
            commits.removeAll { $0.id == commit.id }
        } catch {
            print("Failed to hide commit: \(error)")
        }
    }

    private func shareCommit(_ commit: Commit) async {
        isSharing = true
        defer { isSharing = false }

        do {
            let content = try appState.coldStore.readCommit(hash: commit.hash)
            let data = try JSONEncoder().encode(content)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw ShareError.encodingError
            }

            let link = try await ShareManager.shared.createCommitShare(
                commitHash: commit.hash,
                commitName: commit.name ?? noteNames[commit.noteId],
                commitShortId: commit.shortId,
                commitContent: jsonString
            )

            // Build iMessage payload from commit section snapshots
            let sectionPreviews = content.sections.prefix(3).map { snapshot in
                MessageSharePayload.SectionPreview(
                    content: String(snapshot.content.prefix(100)),
                    contentType: snapshot.contentType,
                    intent: snapshot.intent
                )
            }

            let payload = MessageSharePayload(
                slug: link.slug,
                shareType: "commit",
                title: commit.name ?? noteNames[commit.noteId] ?? "Version Snapshot",
                creatorName: SupabaseManager.shared.currentUser?.displayName,
                commitShortId: commit.shortId,
                sectionPreviews: Array(sectionPreviews),
                handleNames: [],
                noteId: commit.noteId
            )
            payload.writeToSharedDefaults()

            // Set preview text for the share sheet
            let preview = content.sections.first.map { String($0.content.prefix(200)) } ?? ""
            sharePreview = preview
            shareSheetLink = link
        } catch {
            shareError = error.localizedDescription
            print("Failed to share commit: \(error)")
        }
    }
}

// MARK: - Commit Row View

struct CommitRowView: View {
    let commit: Commit
    let noteName: String
    var viewCount: Int = 0
    var isFirst: Bool = false
    var isLast: Bool = false

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = Date(timeIntervalSince1970: Double(commit.createdAt) / 1000)
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var isAI: Bool {
        commit.name?.hasPrefix("AI:") ?? false
    }

    private var tint: Color {
        isAI ? .purple : (commit.isAutoCommit ? .orange : .accentColor)
    }

    private var icon: String {
        isAI ? "sparkles" : (commit.isAutoCommit ? "clock.fill" : "arrow.trianglehead.branch")
    }

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(tint.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                // Row 1: Name + pills + time
                HStack(spacing: 6) {
                    if isAI {
                        Text("AI")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())
                    } else if commit.isAutoCommit {
                        Text("Auto")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(commit.name ?? noteName)
                        .font(.subheadline.weight(commit.isAutoCommit && !isAI ? .regular : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    if viewCount > 0 {
                        Label("\(viewCount)", systemImage: "eye")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Row 2: Source note (if named commit)
                if commit.name != nil {
                    Text("from \(noteName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Commit Detail Sheet

struct CommitDetailSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    let commit: Commit
    let noteName: String?
    var onDelete: (() -> Void)?

    @State private var content: CommitContent?
    @State private var isLoading = true
    @State private var copiedField: String?
    @State private var comments: [SharedComment] = []
    @State private var isLoadingComments = false
    @State private var showingShareSheet = false
    @State private var shareURL: URL?
    @State private var shareTitle: String = ""
    @State private var sharePreview: String = ""
    @State private var showingDeleteConfirmation = false
    @FocusState private var isCommentFocused: Bool

    private var creatorName: String {
        authManager.currentUser?.email ?? "Local User"
    }

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(commit.createdAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let content = content {
                    commitContentView(content)
                } else {
                    Text("Failed to load version")
                        .foregroundStyle(.secondary)
                }
            }
            .background(Color.systemBackground)
            .navigationTitle("")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    Image("ObiusLogo")
                        .renderingMode(.original)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await shareFromDetail() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .task {
                await loadContent()
                await loadComments()
            }
            .alert("Delete Version", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task { await deleteCommit() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This version will be permanently removed from this device. This cannot be undone.")
            }
            .platformFullScreenCover(isPresented: $showingShareSheet) {
                if let url = shareURL {
                    NodeShareSheet(
                        url: url,
                        title: shareTitle,
                        preview: sharePreview
                    )
                }
            }
        }
    }

    private func deleteCommit() async {
        do {
            // Delete from cold store (.obx file)
            try appState.coldStore.deleteCommit(hash: commit.hash)
            // Delete from hot store (database index)
            try await appState.commitRepository.deleteCommit(id: commit.id)
            onDelete?()
            dismiss()
        } catch {
            print("Failed to delete commit: \(error)")
        }
    }

    @ViewBuilder
    private func commitContentView(_ content: CommitContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                if let title = content.note.title, !title.isEmpty {
                    Button {
                        ClipboardHelper.copy(title)
                        copiedField = "badge_title"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedField == "badge_title" { copiedField = nil }
                        }
                    } label: {
                        Text(copiedField == "badge_title" ? "Copied" : title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(copiedField == "badge_title" ? .green : .primary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                // Commit icon + centered ID
                ZStack {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.zipper")
                                .font(.caption2)
                            Text("Version")
                                .font(.caption2.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.15), in: Capsule())
                        .foregroundStyle(.purple)
                        Spacer()
                    }

                    Button {
                        ClipboardHelper.copy(commit.shortId)
                        copiedField = "nav_title"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedField == "nav_title" { copiedField = nil }
                        }
                    } label: {
                        Text(copiedField == "nav_title" ? "Copied" : "#\(commit.shortId)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(copiedField == "nav_title" ? .white : .green)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.2), in: Capsule())
                    }
                }

                // Metadata card
                VStack(alignment: .leading, spacing: 6) {
                    // .obx filename
                    copyableRow(
                        label: "File",
                        value: "\(commit.name ?? "Untitled").obx",
                        field: "file",
                        valueFont: .subheadline.weight(.medium),
                        valueColor: .primary
                    )

                    // Creator
                    copyableRow(
                        label: "By",
                        value: creatorName,
                        field: "creator",
                        valueFont: .subheadline,
                        valueColor: .secondary
                    )

                    // Created date
                    copyableRow(
                        label: "Date",
                        value: formattedDate,
                        field: "date",
                        valueFont: .subheadline,
                        valueColor: .secondary
                    )

                    // Hash
                    let bareHash = commit.hash.replacingOccurrences(of: "sha256:", with: "")
                    copyableRow(
                        label: "Hash",
                        value: bareHash,
                        field: "hash",
                        valueFont: .system(.caption2, design: .monospaced),
                        valueColor: .tertiary
                    )
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondarySystemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Dot divider
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, -4)

                // Section content
                if !content.note.body.isEmpty {
                    Text(content.note.body)
                        .font(.body)
                }

                ForEach(content.sections, id: \.id) { section in
                    CommitNodePreview(
                        content: section.content,
                        contentType: section.contentType,
                        indentLevel: section.indentLevel,
                        sectionType: section.sectionType,
                        mediaRepository: appState.mediaRepository
                    )

                    // Interstitial line after this section
                    let interstitialKey = "after_\(section.id)"
                    if let text = content.note.interstitialContent[interstitialKey],
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if content.note.interstitialContent[interstitialKey] != nil {
                        Color.clear.frame(height: 16)
                    }
                }

                // End interstitial
                if let endText = content.note.interstitialContent["end"],
                   !endText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(endText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Copy all button
                HStack {
                    Spacer()
                    Button {
                        let allText = buildFullContentText(content)
                        ClipboardHelper.copy(allText)
                        copiedField = "copy_all"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedField == "copy_all" { copiedField = nil }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedField == "copy_all" ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                            Text(copiedField == "copy_all" ? "" : "")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(copiedField == "copy_all" ? .green : .secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .padding(.vertical, 8)

                // Comments
                CommentThreadView(
                    comments: comments,
                    isAuthenticated: SupabaseManager.shared.isAuthenticated,
                    onAddComment: { body in
                        await addComment(body: body)
                    }
                )

                Divider()
                    .padding(.vertical, 8)

                // Delete version
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.caption)
                        Text("Delete Version from Device")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 40)
            }
            .padding()
        }
    }

    private func copyableRow<S: ShapeStyle>(label: String, value: String, field: String, valueFont: Font, valueColor: S) -> some View {
        Button {
            ClipboardHelper.copy(value)
            copiedField = field
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedField == field { copiedField = nil }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if copiedField == field {
                    Text("Copied")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Text(value)
                        .font(valueFont)
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            content = try appState.coldStore.readCommit(hash: commit.hash)
        } catch {
            print("Failed to load commit content: \(error)")
        }
    }

    private func loadComments() async {
        // Find share links for this commit and load their comments
        do {
            let links = try await ShareManager.shared.getShareLinks(commitHash: commit.hash)
            guard let link = links.first else { return }

            let response = try await SupabaseManager.shared.client
                .from("comments")
                .select()
                .eq("share_link_id", value: link.id)
                .is("deleted_at", value: nil)
                .execute()

            let decoded = try JSONDecoder().decode([SharedComment].self, from: response.data)

            // Enrich comments with email — current user's email for their own comments,
            // look up others from user_profiles
            let currentUser = SupabaseManager.shared.currentUser
            var userEmails: [String: String] = [:]
            if let user = currentUser {
                userEmails[user.id.uuidString] = user.email
            }

            comments = decoded.map { comment in
                SharedComment(
                    id: comment.id,
                    userId: comment.userId,
                    userDisplayName: comment.userDisplayName,
                    userEmail: userEmails[comment.userId],
                    body: comment.body,
                    createdAt: comment.createdAt
                )
            }
        } catch {
            print("Failed to load comments: \(error)")
        }
    }

    private func addComment(body: String) async {
        do {
            // Find or create share link for this commit
            let links = try await ShareManager.shared.getShareLinks(commitHash: commit.hash)
            let link: ShareLink
            if let existing = links.first {
                link = existing
            } else {
                // Create a share link so we can attach comments
                let content = try appState.coldStore.readCommit(hash: commit.hash)
                let data = try JSONEncoder().encode(content)
                guard let jsonString = String(data: data, encoding: .utf8) else { return }
                link = try await ShareManager.shared.createCommitShare(
                    commitHash: commit.hash,
                    commitName: commit.name ?? noteName,
                    commitShortId: commit.shortId,
                    commitContent: jsonString
                )
            }

            let comment = try await ShareManager.shared.addComment(
                shareLinkId: link.id,
                body: body
            )
            comments.append(comment)
        } catch {
            print("Failed to add comment: \(error)")
        }
    }

    private func shareFromDetail() async {
        guard let content = content else { return }
        do {
            let data = try JSONEncoder().encode(content)
            guard let jsonString = String(data: data, encoding: .utf8) else { return }

            let link = try await ShareManager.shared.createCommitShare(
                commitHash: commit.hash,
                commitName: commit.name ?? noteName,
                commitShortId: commit.shortId,
                commitContent: jsonString
            )

            let sectionPreviews = content.sections.prefix(3).map { snapshot in
                MessageSharePayload.SectionPreview(
                    content: String(snapshot.content.prefix(100)),
                    contentType: snapshot.contentType,
                    intent: snapshot.intent
                )
            }

            let payload = MessageSharePayload(
                slug: link.slug,
                shareType: "commit",
                title: commit.name ?? noteName ?? "Version Snapshot",
                creatorName: SupabaseManager.shared.currentUser?.displayName,
                commitShortId: commit.shortId,
                sectionPreviews: Array(sectionPreviews),
                handleNames: [],
                noteId: commit.noteId
            )
            payload.writeToSharedDefaults()

            shareURL = URL(string: link.url)
            shareTitle = commit.name ?? noteName ?? "Version Snapshot"
            sharePreview = content.sections.first.map { String($0.content.prefix(200)) } ?? ""
            showingShareSheet = true
        } catch {
            print("Failed to share commit: \(error)")
        }
    }

    private func buildFullContentText(_ content: CommitContent) -> String {
        var parts: [String] = []
        if !content.note.body.isEmpty {
            parts.append(content.note.body)
        }
        for section in content.sections {
            if section.contentType != "image" && section.contentType != "audio" {
                parts.append(section.content)
            }
            let interstitialKey = "after_\(section.id)"
            if let text = content.note.interstitialContent[interstitialKey],
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(text)
            }
        }
        if let endText = content.note.interstitialContent["end"],
           !endText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(endText)
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Commit Node Preview

/// A read-only grey/white preview of a section, mirroring the editor layout.
struct CommitNodePreview: View {
    let content: String
    let contentType: String
    let indentLevel: Int
    let sectionType: String
    let mediaRepository: MediaRepository?

    @State private var loadedImages: [String: PlatformImage] = [:]

    /// Parse image hashes from "hash|assetId,hash|assetId,..." format
    private var imageHashes: [String] {
        content
            .split(separator: ",")
            .map { entry in
                let parts = entry.split(separator: "|", maxSplits: 1)
                return String(parts[0]).trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    /// Parse audio hash and duration from "hash|duration" format
    private var audioHash: String {
        let parts = content.split(separator: "|", maxSplits: 1)
        return parts.count > 0 ? String(parts[0]).trimmingCharacters(in: .whitespaces) : ""
    }

    private var audioDuration: TimeInterval {
        let parts = content.split(separator: "|", maxSplits: 1)
        return parts.count > 1 ? (Double(parts[1]) ?? 0) : 0
    }

    var body: some View {
        if contentType == "image" {
            // Image: display all photos stacked vertically
            VStack(spacing: 8) {
                ForEach(imageHashes, id: \.self) { hash in
                    if let image = loadedImages[hash] {
                        platformImage(image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.systemGray5)
                            .frame(height: 160)
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.gray)
                            }
                    }
                }
            }
            .padding(.leading, CGFloat(indentLevel) * 20)
            .onAppear { loadImages() }
        } else if contentType == "audio", !audioHash.isEmpty, let mediaRepo = mediaRepository {
            // Audio: playable audio node
            AudioNodeView(
                audioHash: audioHash,
                duration: audioDuration,
                mediaRepository: mediaRepo
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.15))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.leading, CGFloat(indentLevel) * 20)
        } else if sectionType == "line" {
            // Interstitial line: plain text without node styling
            Text(content.isEmpty ? " " : content)
                .font(.subheadline)
                .foregroundStyle(content.isEmpty ? .clear : .primary)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .padding(.leading, CGFloat(indentLevel) * 20)
        } else {
            // Fold/Node: simple rounded box matching metadata card background
            Text(content.isEmpty ? "(empty)" : content)
                .font(.subheadline)
                .foregroundStyle(content.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondarySystemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.leading, CGFloat(indentLevel) * 20)
        }
    }

    private func loadImages() {
        guard let mediaRepository else { return }
        for hash in imageHashes where loadedImages[hash] == nil {
            if let data = try? mediaRepository.getMediaData(hash: hash),
               let image = PlatformImage(data: data) {
                loadedImages[hash] = image
            }
        }
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .environmentObject(AppState())
    .environmentObject(AuthManager.shared)
}
