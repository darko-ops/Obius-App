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
    @StateObject private var echoManager = EchoManager.shared
    @State private var selectedTab = 0
    @State private var pendingEchoId: String?
    @State private var bannerEcho: Echo?
    @State private var showBanner = false

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    NotesListView()
                }
                .tabItem {
                    Image(systemName: "note.text")
                }
                .tag(0)

                NavigationStack {
                    LibraryView(pendingEchoId: $pendingEchoId)
                }
                .tabItem {
                    Image(systemName: "person.crop.circle")
                }
                .tag(1)
            }

            // In-app echo alert banner
            if showBanner, let echo = bannerEcho {
                EchoAlertBanner(echo: echo) {
                    withAnimation { showBanner = false }
                    pendingEchoId = echo.id
                    selectedTab = 1
                } onDismiss: {
                    withAnimation { showBanner = false }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .echoNotificationTapped)) { notification in
            if let echoId = notification.userInfo?["echoId"] as? String {
                pendingEchoId = echoId
                selectedTab = 1
            }
        }
        .onChange(of: echoManager.firedEcho) { _, echo in
            guard let echo else { return }
            bannerEcho = echo
            withAnimation(.spring(duration: 0.4)) { showBanner = true }
            echoManager.firedEcho = nil
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation { showBanner = false }
            }
        }
    }
}

// MARK: - In-App Echo Alert Banner

struct EchoAlertBanner: View {
    let echo: Echo
    let onTap: () -> Void
    let onDismiss: () -> Void
    @StateObject private var echoManager = EchoManager.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("Echo Fired")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("@\(echoManager.getHandleName(for: echo))")
                    .font(.subheadline.weight(.medium))
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(AuthManager.shared)
        .environmentObject(DeepLinkRouter.shared)
}
