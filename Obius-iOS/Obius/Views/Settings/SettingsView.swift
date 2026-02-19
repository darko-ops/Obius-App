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

    var body: some View {
        List {
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

                    Button(role: .destructive) {
                        showingSignOut = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button {
                        showingAuth = true
                    } label: {
                        Label("Sign In", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }

            // Privacy Section
            SwiftUI.Section("Privacy") {
                NavigationLink {
                    PrivacyModeView()
                } label: {
                    Label("Privacy Mode", systemImage: "lock.shield")
                }

                NavigationLink {
                    DataManagementView()
                } label: {
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

            // About Section
            SwiftUI.Section("About") {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://obius.io/privacy")!) {
                    Label("Privacy Policy", systemImage: "doc.text")
                }

                Link(destination: URL(string: "https://obius.io/terms")!) {
                    Label("Terms of Service", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("Settings")
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
        .sheet(isPresented: $showingAuth) {
            AuthView()
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
                .environmentObject(authManager)
        }
    }
}

// MARK: - Privacy Mode View

struct PrivacyModeView: View {
    @State private var privacyMode = "standard"

    var body: some View {
        List {
            SwiftUI.Section {
                Picker("Privacy Mode", selection: $privacyMode) {
                    Text("Standard").tag("standard")
                    Text("Private").tag("private")
                }
                .pickerStyle(.inline)
            } footer: {
                Text(privacyMode == "standard"
                    ? "Notes sync to cloud and AI features are enabled."
                    : "Notes stay local only. No cloud sync or AI features.")
            }

            SwiftUI.Section {
                if privacyMode == "standard" {
                    Label("Cloud sync enabled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("AI summaries enabled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("Semantic search enabled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Notes stored locally only", systemImage: "lock.fill")
                        .foregroundStyle(.orange)
                    Label("No data sent to servers", systemImage: "lock.fill")
                        .foregroundStyle(.orange)
                    Label("Local search only", systemImage: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Privacy Mode")
    }
}

// MARK: - Data Management View

struct DataManagementView: View {
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
                // TODO: Implement delete all
            }
        } message: {
            Text("This cannot be undone. All local notes will be permanently deleted.")
        }
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var profileImages = ProfileImageManager.shared

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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
                Image(uiImage: banner)
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
                Image(uiImage: avatar)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 4))
            } else {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 100, height: 100)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 4))

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
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
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
                  let image = UIImage(data: data) else { return }
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
