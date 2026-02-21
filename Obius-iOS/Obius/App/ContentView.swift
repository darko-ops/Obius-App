import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var deepLinkRouter: DeepLinkRouter
    @StateObject private var networkMonitor = NetworkMonitor.shared

    var body: some View {
        Group {
            if authManager.isLoading && !appState.isInitialized {
                // Loading state
                ProgressView("Loading...")
            } else if authManager.isAuthenticated {
                // Main app
                MainTabView()
            } else {
                // Auth flow (but still allow local use)
                LocalOrAuthView()
            }
        }
        .fullScreenCover(item: $deepLinkRouter.pendingShareSlugItem) { item in
            SharedContentView(slug: item.slug)
                .environmentObject(appState)
        }
    }
}

// MARK: - Local or Auth Choice

struct LocalOrAuthView: View {
    @EnvironmentObject var appState: AppState
    @State private var useLocalMode = false
    @State private var showAuth = false

    var body: some View {
        if useLocalMode {
            MainTabView()
        } else {
            VStack(spacing: 32) {
                Spacer()

                // Logo
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 80))
                        .foregroundStyle(Color.accentColor)

                    Text("Obius")
                        .font(.largeTitle.bold())

                    Text("Local-first notes with AI")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Options
                VStack(spacing: 16) {
                    Button {
                        showAuth = true
                    } label: {
                        HStack {
                            Image(systemName: "cloud")
                            Text("Sign In for Cloud Sync")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        useLocalMode = true
                    } label: {
                        HStack {
                            Image(systemName: "iphone")
                            Text("Continue Offline")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Text("Your notes are always stored locally. Sign in to enable cloud sync and AI features.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .sheet(isPresented: $showAuth) {
                AuthView()
            }
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                NotesListView()
            }
            .tabItem {
                Image(systemName: "note.text")
            }
            .tag(0)

            NavigationStack {
                IntelligenceView()
            }
            .tabItem {
                Image("ObiusLogo")
                    .renderingMode(.template)
            }
            .tag(1)

            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Image(systemName: "person.crop.circle")
            }
            .tag(2)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(AuthManager.shared)
        .environmentObject(DeepLinkRouter.shared)
}
