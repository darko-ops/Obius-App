import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var showingSignOut = false

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

                    Button(role: .destructive) {
                        showingSignOut = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button {
                        // Show auth view
                    } label: {
                        Label("Sign In", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }

            // Sync Section
            SwiftUI.Section("Sync") {
                HStack {
                    Label("Status", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    SyncStatusView()
                }

                HStack {
                    Label("Connection", systemImage: "wifi")
                    Spacer()
                    Text(networkMonitor.isConnected ? "Online" : "Offline")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await appState.triggerSync()
                    }
                } label: {
                    Label("Sync Now", systemImage: "arrow.clockwise")
                }
                .disabled(!networkMonitor.isConnected || !authManager.isAuthenticated)
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

            // About Section
            SwiftUI.Section("About") {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://obius.app/privacy")!) {
                    Label("Privacy Policy", systemImage: "doc.text")
                }

                Link(destination: URL(string: "https://obius.app/terms")!) {
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

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(AppState())
    .environmentObject(AuthManager.shared)
}
