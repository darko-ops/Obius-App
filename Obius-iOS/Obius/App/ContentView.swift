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
        .platformFullScreenCover(item: $deepLinkRouter.pendingShareSlugItem) { item in
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
                            #if os(iOS)
                            Image(systemName: "iphone")
                            #else
                            Image(systemName: "desktopcomputer")
                            #endif
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

                // Free trial nudge — shown after they've seen the app intro
                if TierManager.shared.currentTier == .free {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("Start a 7-day free trial of Pro anytime in Settings.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 32)
                }

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

    #if os(iOS)
    private static func tintedLogo(color: UIColor) -> UIImage {
        guard let original = UIImage(named: "ObiusLogo")?.withRenderingMode(.alwaysTemplate),
              let cgImage = original.cgImage else { return UIImage() }
        let iconSize: CGFloat = 25
        let canvasSize = CGSize(width: iconSize, height: iconSize)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { ctx in
            let context = ctx.cgContext
            let rect = CGRect(origin: .zero, size: canvasSize)
            context.translateBy(x: 0, y: canvasSize.height)
            context.scaleBy(x: 1, y: -1)
            context.clip(to: rect, mask: cgImage)
            context.setFillColor(color.cgColor)
            context.fill(rect)
        }.withRenderingMode(.alwaysOriginal)
        // Align with SF Symbol baseline
        return image.withBaselineOffset(fromBottom: 6)
    }

    private static let resizedGreyLogo = tintedLogo(color: .systemGray)
    private static let resizedTwoToneLogo = tintedLogo(color: .white)

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.systemGray
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.white
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    #endif

    var body: some View {
        ZStack(alignment: .top) {
            mainNavigation

            // In-app echo alert banner with context
            if showBanner, let echo = bannerEcho {
                VStack(spacing: 0) {
                    EchoContextCard(
                        echo: echo,
                        handleName: echoManager.getHandleName(for: echo),
                        portalContexts: bannerContexts,
                        onNavigate: { noteId in
                            withAnimation { showBanner = false }
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
            bannerContexts = []
            withAnimation(.spring(duration: 0.4)) { showBanner = true }
            echoManager.firedEcho = nil

            Task {
                let contexts = await EchoContextCard.buildContexts(
                    handleId: echo.handleId,
                    handleRepository: appState.handleRepository,
                    noteRepository: appState.noteRepository
                )
                withAnimation { bannerContexts = contexts }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                withAnimation { showBanner = false }
            }
        }
    }

    // MARK: - Platform Navigation

    @ViewBuilder
    private var mainNavigation: some View {
        #if os(iOS)
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
                Image(uiImage: selectedTab == 1 ? Self.resizedTwoToneLogo : Self.resizedGreyLogo)
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
        .tint(.white)
        #else
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Notes", systemImage: "note.text")
                    .tag(0)
                Label("Intelligence", systemImage: "brain")
                    .tag(1)
                Label("Library", systemImage: "person.crop.circle")
                    .tag(2)
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .navigationTitle("Obius")
        } detail: {
            NavigationStack {
                switch selectedTab {
                case 0:
                    NotesListView()
                case 1:
                    IntelligenceView()
                        .environmentObject(appState.insightRepository)
                case 2:
                    LibraryView(pendingEchoId: $pendingEchoId)
                default:
                    NotesListView()
                }
            }
            .background(Color.black)
        }
        #endif
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(AuthManager.shared)
        .environmentObject(DeepLinkRouter.shared)
}
