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
    @State private var bannerContexts: [PortalContext] = []

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
                    IntelligenceView()
                        .environmentObject(appState.insightRepository)
                }
                .tabItem {
                    Image("ObiusLogo")
                        .renderingMode(.original)
                }
                .tag(1)

                NavigationStack {
                    LibraryView(pendingEchoId: $pendingEchoId)
                }
                .tabItem {
                    Image(systemName: "person.crop.circle")
                }
                .tag(2)
            }

            // In-app echo alert banner with context
            if showBanner, let echo = bannerEcho {
                VStack(spacing: 0) {
                    EchoContextCard(
                        echo: echo,
                        handleName: echoManager.getHandleName(for: echo),
                        portalContexts: bannerContexts,
                        onNavigate: { noteId in
                            withAnimation { showBanner = false }
                            // Navigate to the note via Intelligence tab
                            pendingEchoId = echo.id
                            selectedTab = 2
                        }
                    )
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation { showBanner = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { showBanner = false }
                        pendingEchoId = echo.id
                        selectedTab = 2
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .echoNotificationTapped)) { notification in
            if let echoId = notification.userInfo?["echoId"] as? String {
                pendingEchoId = echoId
                selectedTab = 2
            }
        }
        .onChange(of: echoManager.firedEcho) { _, echo in
            guard let echo else { return }
            bannerEcho = echo
            bannerContexts = [] // Show immediately, contexts load async
            withAnimation(.spring(duration: 0.4)) { showBanner = true }
            echoManager.firedEcho = nil

            // Load portal context in background
            Task {
                let contexts = await EchoContextCard.buildContexts(
                    handleId: echo.handleId,
                    handleRepository: appState.handleRepository,
                    noteRepository: appState.noteRepository
                )
                withAnimation { bannerContexts = contexts }
            }

            // Auto-dismiss after 8 seconds (longer with context card)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                withAnimation { showBanner = false }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(AuthManager.shared)
        .environmentObject(DeepLinkRouter.shared)
}
