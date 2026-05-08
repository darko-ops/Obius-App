import SwiftUI
import PhotosUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var appearanceManager: AppearanceManager
    @State private var showingSignOut = false
    @State private var showingAuth = false
    @State private var showingEditProfile = false
    @State private var showingChangePassword = false
    @State private var showingDeleteAccount = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var settingsPath: [SettingsDestination] = []

    enum SettingsDestination: Hashable {
        case subscription
        case dataManagement
        case ledger
        case versionRetention
    }

    var body: some View {
        Form {
            // Account Section
            SwiftUI.Section("Account") {
                if authManager.isAuthenticated {
                    if let user = authManager.currentUser {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading) {
                                Text(user.displayName ?? "User")
                                    .font(.headline)
                                Text(user.email ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        showingEditProfile = true
                    } label: {
                        Label("Edit Profile", systemImage: "pencil")
                    }

                    Button {
                        showingChangePassword = true
                    } label: {
                        Label("Change Password", systemImage: "lock.rotation")
                    }

                    Button(role: .destructive) {
                        showingSignOut = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    Button(role: .destructive) {
                        showingDeleteAccount = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                    }
                    .disabled(isDeletingAccount)
                } else {
                    Button {
                        showingAuth = true
                    } label: {
                        Label("Sign In", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }

            // Subscription Section
            SwiftUI.Section {
                NavigationLink(value: SettingsDestination.subscription) {
                    HStack {
                        Label("Subscription", systemImage: "crown")
                        Spacer()
                        Text(TierManager.shared.tierDisplayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Privacy Section
            SwiftUI.Section("Privacy") {
                NavigationLink(value: SettingsDestination.dataManagement) {
                    Label("Data Management", systemImage: "externaldrive")
                }
            }

            // Appearance Section
            SwiftUI.Section("Appearance") {
                Picker(selection: $appearanceManager.currentMode) {
                    ForEach(AppearanceManager.AppearanceMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                } label: {
                    Label("Theme", systemImage: "paintbrush")
                }
            }

            // Commits Section
            SwiftUI.Section("Versions") {
                NavigationLink(value: SettingsDestination.ledger) {
                    Label("Ledger", systemImage: "list.bullet.rectangle")
                }

                NavigationLink(value: SettingsDestination.versionRetention) {
                    Label("Retention", systemImage: "clock.arrow.circlepath")
                }
            }

            // About Section
            SwiftUI.Section("About") {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://docs.google.com/document/d/e/2PACX-1vRbJ9cYTWnyQSYeL8JrTOizC0eC-f8rhoicqh3GttTDIrbNlesR-_auwkFz2OLsTTzguDG3YLtzwnEY/pub")!) {
                    Label("Privacy Policy", systemImage: "doc.text")
                }

                Link(destination: URL(string: "https://docs.google.com/document/d/e/2PACX-1vRq_bt_Z_V7ci7lS3hHLzq4QjRrDFJsJu6Ab-oedeeSakGPGcx_dJlG3EDAzdetptd21GPyEtzTxKbg/pub")!) {
                    Label("Terms of Service", systemImage: "doc.text")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .navigationDestination(for: SettingsDestination.self) { destination in
            switch destination {
            case .subscription:
                SubscriptionView()
            case .dataManagement:
                DataManagementView()
            case .ledger:
                LedgerView()
                    .environmentObject(appState)
            case .versionRetention:
                VersionRetentionView()
                    .environmentObject(appState)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert("Sign Out", isPresented: $showingSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task {
                    await authManager.signOut()
                }
            }
        } message: {
            Text("Your local notes will remain on this device. You can sign in again to sync.")
        }
        .alert("Delete Account", isPresented: $showingDeleteAccount) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Forever", role: .destructive) {
                Task { await performDeleteAccount() }
            }
        } message: {
            Text("This will permanently delete your account and all of your data, including notes, versions, handles, echoes, and media — on this device and in the cloud. This cannot be undone.")
        }
        .alert(
            "Couldn't Delete Account",
            isPresented: Binding(
                get: { deleteAccountError != nil },
                set: { if !$0 { deleteAccountError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
        .overlay {
            if isDeletingAccount {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("Deleting account…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .sheet(isPresented: $showingAuth) {
            AuthView()
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordView()
                .environmentObject(authManager)
        }
    }

    @MainActor
    private func performDeleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await authManager.deleteAccount()
        } catch {
            deleteAccountError = "We couldn't delete your account: \(error.localizedDescription). Your account is still active. Please try again, or contact support."
            return
        }

        // Server-side delete succeeded — wipe local state. Failures here are not
        // fatal (the cloud account is gone); we still sign out and dismiss.
        try? await appState.deleteAllLocalData()
        await authManager.signOut()
        dismiss()
    }
}

// MARK: - Change Password View

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var didSucceed = false

    private var isValid: Bool {
        !currentPassword.isEmpty && newPassword.count >= 6 && newPassword == confirmPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    SecureField("Current Password", text: $currentPassword)
                        .textContentType(.password)
                } header: {
                    Text("Verify Identity")
                }

                SwiftUI.Section {
                    SecureField("New Password", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirm New Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                } header: {
                    Text("New Password")
                } footer: {
                    if newPassword.count > 0 && newPassword.count < 6 {
                        Text("Password must be at least 6 characters.")
                            .foregroundStyle(.red)
                    } else if !confirmPassword.isEmpty && newPassword != confirmPassword {
                        Text("Passwords do not match.")
                            .foregroundStyle(.red)
                    }
                }

                if let error = errorMessage {
                    SwiftUI.Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if didSucceed {
                    SwiftUI.Section {
                        Label("Password changed successfully.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Change Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if didSucceed {
                        Button("Done") { dismiss() }
                    } else {
                        Button("Save") {
                            changePassword()
                        }
                        .disabled(!isValid || isLoading)
                    }
                }
            }
            .disabled(isLoading)
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
        }
    }

    private func changePassword() {
        errorMessage = nil
        isLoading = true

        Task {
            do {
                try await authManager.changePassword(
                    currentPassword: currentPassword,
                    newPassword: newPassword
                )
                await MainActor.run {
                    isLoading = false
                    didSucceed = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    if error.localizedDescription.contains("Invalid login") {
                        errorMessage = "Current password is incorrect."
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

// MARK: - Data Management View

struct DataManagementView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingDeleteConfirm = false
    @State private var showingExport = false

    var body: some View {
        List {
            SwiftUI.Section("Export") {
                Button {
                    showingExport = true
                } label: {
                    Label("Export All Notes", systemImage: "square.and.arrow.up")
                }
            }

            SwiftUI.Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete All Local Data", systemImage: "trash")
                }
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("This will delete all notes from this device. Cloud data will not be affected.")
            }
        }
        .navigationTitle("Data Management")
        .alert("Delete All Data", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    try? await appState.deleteAllLocalData()
                }
            }
        } message: {
            Text("This cannot be undone. All local notes will be permanently deleted.")
        }
    }
}

// MARK: - Version Retention View

struct VersionRetentionView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("retention_auto_days") private var autoRetentionDays: Int = 30
    @AppStorage("retention_ai_days") private var aiRetentionDays: Int = 7
    @AppStorage("retention_manual") private var manualRetention: String = "permanent"
    @State private var lastCleanupCount = 0
    @State private var showingCleanupResult = false

    private let dayOptions = [7, 14, 30, 60, 90, 180, 365]

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker("Auto Versions", selection: $autoRetentionDays) {
                    ForEach(dayOptions, id: \.self) { days in
                        Text(formatDays(days)).tag(days)
                    }
                }

                Picker("AI Versions", selection: $aiRetentionDays) {
                    ForEach(dayOptions, id: \.self) { days in
                        Text(formatDays(days)).tag(days)
                    }
                }

                HStack {
                    Text("Manual Versions")
                    Spacer()
                    Text("Permanent")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Retention Policy")
            } footer: {
                Text("Versions older than the retention period will be automatically removed from this device on app launch.")
            }

            SwiftUI.Section {
                Button {
                    Task { await runCleanup() }
                } label: {
                    Label("Clean Up Now", systemImage: "trash.circle")
                }
            } footer: {
                if let lastRun = lastCleanupDate {
                    Text("Last cleanup: \(lastRun, style: .relative) ago")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Version Retention")
        .alert("Cleanup Complete", isPresented: $showingCleanupResult) {
            Button("OK") {}
        } message: {
            Text(lastCleanupCount == 0
                 ? "No expired versions found."
                 : "Removed \(lastCleanupCount) expired version\(lastCleanupCount == 1 ? "" : "s") from this device.")
        }
    }

    private var lastCleanupDate: Date? {
        let ts = UserDefaults.standard.double(forKey: "retention_last_cleanup")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    private func formatDays(_ days: Int) -> String {
        switch days {
        case 7: return "7 days"
        case 14: return "14 days"
        case 30: return "30 days"
        case 60: return "60 days"
        case 90: return "90 days"
        case 180: return "6 months"
        case 365: return "1 year"
        default: return "\(days) days"
        }
    }

    private func runCleanup() async {
        let count = await VersionRetentionManager.runCleanup(
            commitRepository: appState.commitRepository,
            coldStore: appState.coldStore
        )
        lastCleanupCount = count
        showingCleanupResult = true
    }
}

// MARK: - Version Retention Manager

enum VersionRetentionManager {
    /// Deletes expired commits based on retention settings.
    /// Returns the number of commits deleted.
    @MainActor
    static func runCleanup(commitRepository: CommitRepository, coldStore: ColdStore) async -> Int {
        let autoRetentionDays = UserDefaults.standard.integer(forKey: "retention_auto_days")
        let aiRetentionDays = UserDefaults.standard.integer(forKey: "retention_ai_days")

        // Use defaults if not yet configured
        let autoDays = autoRetentionDays > 0 ? autoRetentionDays : 30
        let aiDays = aiRetentionDays > 0 ? aiRetentionDays : 7

        let now = Date()
        let autoExpiry = now.addingTimeInterval(-Double(autoDays) * 86400)
        let aiExpiry = now.addingTimeInterval(-Double(aiDays) * 86400)

        let autoExpiryMs = Int64(autoExpiry.timeIntervalSince1970 * 1000)
        let aiExpiryMs = Int64(aiExpiry.timeIntervalSince1970 * 1000)

        guard let allCommits = try? await commitRepository.getAllCommits() else { return 0 }

        var deleted = 0
        for commit in allCommits {
            let isAI = commit.name?.hasPrefix("AI:") ?? false
            let isAuto = commit.isAutoCommit && !isAI
            let isManual = !commit.isAutoCommit && !isAI

            // Manual commits are permanent — never auto-delete
            if isManual { continue }

            let expired: Bool
            if isAuto {
                expired = commit.createdAt < autoExpiryMs
            } else if isAI {
                expired = commit.createdAt < aiExpiryMs
            } else {
                continue
            }

            if expired {
                do {
                    try coldStore.deleteCommit(hash: commit.hash)
                    try await commitRepository.deleteCommit(id: commit.id)
                    deleted += 1
                } catch {
                    print("[Retention] Failed to delete commit \(commit.shortId): \(error)")
                }
            }
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "retention_last_cleanup")
        if deleted > 0 {
            print("[Retention] Cleaned up \(deleted) expired version(s)")
        }
        return deleted
    }
}

// MARK: - Ledger View

struct LedgerView: View {
    @EnvironmentObject var appState: AppState
    @State private var commits: [Commit] = []
    @State private var noteNames: [String: String] = [:]
    @State private var isLoading = true
    @State private var commitToDelete: Commit?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if commits.isEmpty {
                ContentUnavailableView(
                    "No Versions",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Versions will appear here as you save snapshots of your notes.")
                )
            } else {
                List {
                    ForEach(commits) { commit in
                        let noteName = noteNames[commit.noteId] ?? commit.name ?? "Archived Version"
                        Group {
                            if commit.isAutoCommit {
                                HStack(spacing: 0) {
                                    ZStack {
                                        LinearGradient(
                                            colors: [Color.orange.opacity(0.2), Color.orange.opacity(0)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )

                                        Text("Auto")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.orange)
                                            .rotationEffect(.degrees(-90))
                                            .fixedSize()
                                    }
                                    .frame(width: 24)

                                    HStack {
                                        Text(commit.name ?? noteName)
                                            .font(.subheadline)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(formattedDate(commit.createdAt))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.leading, 6)
                                }
                            } else {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 8, height: 8)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(commit.name ?? noteName)
                                            .font(.headline)
                                            .lineLimit(1)

                                        Text("#\(commit.shortId)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.tertiary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        if commit.name != nil {
                                            Text("from \(noteName)")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }

                                        Text(formattedDate(commit.createdAt))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .listRowBackground(
                            commit.isHidden
                                ? Color.gray.opacity(0.08)
                                : Color.clear
                        )
                        .opacity(commit.isHidden ? 0.6 : 1.0)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                commitToDelete = commit
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            if commit.isHidden {
                                Button {
                                    Task { await toggleHidden(commit) }
                                } label: {
                                    Label("Unhide", systemImage: "eye")
                                }
                                .tint(.accentColor)
                            } else {
                                Button {
                                    Task { await toggleHidden(commit) }
                                } label: {
                                    Label("Hide", systemImage: "eye.slash")
                                }
                                .tint(.orange)
                            }
                        }
                        .contextMenu {
                            Button {
                                Task { await toggleHidden(commit) }
                            } label: {
                                Label(commit.isHidden ? "Unhide" : "Hide",
                                      systemImage: commit.isHidden ? "eye" : "eye.slash")
                            }

                            Button(role: .destructive) {
                                commitToDelete = commit
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Ledger")
        .alert("Delete Version", isPresented: Binding(
            get: { commitToDelete != nil },
            set: { if !$0 { commitToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { commitToDelete = nil }
            Button("Delete", role: .destructive) {
                if let commit = commitToDelete {
                    Task { await deleteCommit(commit) }
                }
            }
        } message: {
            Text("This version will be permanently deleted. This cannot be undone.")
        }
        .task {
            await loadAllCommits()
        }
    }

    private func formattedDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "M.dd.yyyy"
        return formatter.string(from: date)
    }

    private func loadAllCommits() async {
        isLoading = true
        defer { isLoading = false }

        do {
            commits = try await appState.commitRepository.getAllCommits()

            for commit in commits {
                if noteNames[commit.noteId] == nil {
                    if let note = try await appState.noteRepository.getNote(id: commit.noteId) {
                        noteNames[commit.noteId] = note.displayTitle
                    }
                }
            }
        } catch {
            print("Failed to load ledger: \(error)")
        }
    }

    private func deleteCommit(_ commit: Commit) async {
        do {
            try await appState.commitRepository.deleteCommit(id: commit.id)
            commits.removeAll { $0.id == commit.id }
        } catch {
            print("Failed to delete commit: \(error)")
        }
    }

    private func toggleHidden(_ commit: Commit) async {
        do {
            let newHidden = !commit.isHidden
            try await appState.commitRepository.setHidden(newHidden, id: commit.id)
            if let index = commits.firstIndex(where: { $0.id == commit.id }) {
                commits[index].isHidden = newHidden
            }
        } catch {
            print("Failed to toggle commit visibility: \(error)")
        }
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var profileImages = ProfileImageManager.shared

    @State private var displayName = ""
    @State private var bio = ""
    @State private var phoneNumber = ""
    @State private var showingAvatarPicker = false
    @State private var showingBannerPicker = false
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var bannerPickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Banner
                    bannerSection

                    // Avatar (overlaps banner)
                    avatarSection
                        .offset(y: -50)
                        .padding(.bottom, -50)

                    // Form fields
                    VStack(spacing: 24) {
                        // Display Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Display Name")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            TextField("Your name", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.name)
                        }

                        // Bio
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bio")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            TextField("Tell us about yourself", text: $bio, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...6)
                        }

                        // Phone Number
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Phone Number")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            TextField("Your phone number", text: $phoneNumber)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.telephoneNumber)
                                #if os(iOS)
                                .keyboardType(.phonePad)
                                #endif

                            Text("Not visible on your profile.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        // Email (read-only)
                        if let email = authManager.currentUser?.email {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)

                                Text(email)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 10)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }

                        if let error = authManager.authError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Edit Profile")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
                            let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespaces)
                            await authManager.updateProfile(
                                displayName: trimmedName,
                                bio: trimmedBio,
                                phoneNumber: trimmedPhone
                            )
                            if authManager.authError == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(authManager.isLoading)
                }
            }
            .onAppear {
                displayName = authManager.currentUser?.displayName ?? ""
                bio = authManager.currentUser?.bio ?? ""
                phoneNumber = authManager.currentUser?.phoneNumber ?? ""
            }
            .onChange(of: avatarPickerItem) { _, newItem in
                loadImage(from: newItem, type: .avatar)
            }
            .onChange(of: bannerPickerItem) { _, newItem in
                loadImage(from: newItem, type: .banner)
            }
        }
    }

    // MARK: - Banner Section

    private var bannerSection: some View {
        ZStack(alignment: .bottomTrailing) {
            if let banner = profileImages.bannerImage {
                platformImage(banner)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 160)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 160)
            }

            // Edit banner button
            PhotosPicker(selection: $bannerPickerItem, matching: .images) {
                Image(systemName: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(12)

            // Remove banner button
            if profileImages.bannerImage != nil {
                Button {
                    profileImages.removeBannerImage()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
            }
        }
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        ZStack(alignment: .bottomTrailing) {
            if let avatar = profileImages.profileImage {
                platformImage(avatar)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.systemBackground, lineWidth: 4))
            } else {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 100, height: 100)
                        .overlay(Circle().stroke(Color.systemBackground, lineWidth: 4))

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

            // Edit avatar button
            PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                Image(systemName: "camera.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.systemBackground, lineWidth: 2))
            }
        }
    }

    // MARK: - Helpers

    private var userInitials: String {
        guard let name = authManager.currentUser?.displayName else { return "?" }
        let components = name.components(separatedBy: " ")
        let initials = components.compactMap { $0.first }.prefix(2)
        return String(initials).uppercased()
    }

    private enum ImageType {
        case avatar, banner
    }

    private func loadImage(from item: PhotosPickerItem?, type: ImageType) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = PlatformImage(data: data) else { return }
            switch type {
            case .avatar:
                profileImages.saveProfileImage(image)
            case .banner:
                profileImages.saveBannerImage(image)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(AppState())
    .environmentObject(AuthManager.shared)
    .environmentObject(AppearanceManager.shared)
}
