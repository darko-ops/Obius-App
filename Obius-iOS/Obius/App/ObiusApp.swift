import SwiftUI
import UserNotifications
import RevenueCat
#if os(iOS)
import BackgroundTasks
#endif

@main
struct ObiusApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var deepLinkRouter = DeepLinkRouter.shared
    @StateObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var tierManager = TierManager.shared
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        InterFontRegistration.registerAsDefault()
        #if os(iOS)
        AutoCommitManager.registerBackgroundTask()
        #endif

        let rcKey = AppConfiguration.revenueCatAPIKey
        if !rcKey.isEmpty {
            Purchases.logLevel = AppConfiguration.environment.isDebug ? .debug : .error
            Purchases.configure(withAPIKey: rcKey)
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .font(.custom("Inter-Regular", size: 17))
                .environmentObject(appState)
                .environmentObject(authManager)
                .environmentObject(deepLinkRouter)
                .environmentObject(appearanceManager)
                .environmentObject(tierManager)
                .preferredColorScheme(appearanceManager.currentMode.colorScheme)
                .task {
                    await TierManager.shared.initialize()
                    await StoreManager.shared.initialize()
                    await appState.initialize()
                }
                .sheet(isPresented: $tierManager.showPaywall) {
                    PaywallSheet()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        Task {
                            await EchoManager.shared.checkForFiredEchoes()
                            await appState.autoCommitManager.checkAndAutoCommit()
                            // Sync on every foreground (only if already initialized)
                            if appState.isInitialized && AuthManager.shared.isAuthenticated && TierManager.shared.limits.cloudSync {
                                await appState.triggerSync()
                                await appState.syncEngine.subscribeRealtime()
                            }
                        }
                        EchoManager.shared.scheduleNextCheck()
                    } else if phase == .background {
                        EchoManager.shared.stopPeriodicCheck()
                        Task { await appState.syncEngine.unsubscribeRealtime() }
                    }
                }
                .onOpenURL { url in
                    deepLinkRouter.handleURL(url)
                }
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 500)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    NotificationCenter.default.post(name: .createNewNote, object: nil)
                }
                .keyboardShortcut("n")
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(authManager)
                .environmentObject(tierManager)
                .environmentObject(appearanceManager)
        }
        #endif
    }
}

// MARK: - Notification Delegate

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    // Show notifications even when app is in foreground + update echo state
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Immediately update echo alert state so the UI reflects the fired echo
        Task { @MainActor in
            await EchoManager.shared.checkForFiredEchoes()
        }
        completionHandler([.banner, .sound])
    }

    // Handle notification tap — navigate to the Echo alert
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let echoId = userInfo["echoId"] as? String {
            NotificationCenter.default.post(
                name: .echoNotificationTapped,
                object: nil,
                userInfo: ["echoId": echoId]
            )
        }
        completionHandler()
    }
}

@MainActor
class AppState: ObservableObject {
    let database: DatabaseManager
    let noteRepository: NoteRepository
    let sectionRepository: SectionRepository
    let handleRepository: HandleRepository  // Handle Loop support
    let echoRepository: EchoRepository      // Echo alert/reminder support
    let shareLinkRepository: ShareLinkRepository  // Share link support
    let commentRepository: CommentRepository      // Share comments support
    let moduleRepository: ModuleRepository        // Module (folder) support
    let syncEngine: SyncEngine
    let syncLogger: SyncOperationLogger

    // Split-Storage Engine components
    let coldStore: ColdStore
    let commitRepository: CommitRepository
    let mediaRepository: MediaRepository
    let commitModule: CommitModule
    let autoCommitManager: AutoCommitManager
    let insightRepository: InsightRepository

    @Published var isInitialized = false

    init() {
        do {
            // Migrate database from legacy path to App Group container (one-time)
            DatabaseMigrationHelper.migrateIfNeeded()

            self.database = try DatabaseManager()
            self.noteRepository = NoteRepository(database: database)
            self.sectionRepository = SectionRepository(database: database)
            self.handleRepository = HandleRepository(database: database)  // Handle Loop support
            self.echoRepository = EchoRepository(database: database)      // Echo alert/reminder support
            self.shareLinkRepository = ShareLinkRepository(database: database)  // Share link support
            self.commentRepository = CommentRepository(database: database)      // Share comments support
            self.moduleRepository = ModuleRepository(database: database)        // Module (folder) support
            self.syncEngine = SyncEngine(database: database)
            self.syncLogger = SyncOperationLogger(database: database)
            self.handleRepository.syncLogger = syncLogger  // Wire up handle cloud sync
            self.echoRepository.syncLogger = syncLogger  // Wire up echo cloud sync

            // Initialize Split-Storage Engine
            self.coldStore = ColdStore.shared
            self.commitRepository = CommitRepository(database: database)
            self.mediaRepository = MediaRepository(database: database, coldStore: coldStore)
            self.commitModule = CommitModule(
                coldStore: coldStore,
                noteRepository: noteRepository,
                sectionRepository: sectionRepository,
                commitRepository: commitRepository
            )
            self.autoCommitManager = AutoCommitManager(
                commitModule: commitModule,
                noteRepository: noteRepository,
                commitRepository: commitRepository,
                sectionRepository: sectionRepository,
                coldStore: coldStore
            )
            self.insightRepository = InsightRepository(database: database)

            // Initialize HandleManager singleton with repository
            HandleManager.shared.initialize(handleRepository: handleRepository)

            // Initialize EchoManager singleton with repository
            EchoManager.shared.initialize(echoRepository: echoRepository)

            // Initialize ShareManager singleton with repositories
            ShareManager.shared.initialize(
                shareLinkRepository: shareLinkRepository,
                commentRepository: commentRepository
            )
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    func initialize() async {
        await syncEngine.initialize()
        isInitialized = true

        // Wire up sync logger to auto-push changes after operations are logged
        syncLogger.onOperationLogged = { [weak self] in
            guard let self else { return }
            Task { await self.syncEngine.schedulePush() }
        }

        // Initialize Echo notifications
        await EchoManager.shared.requestNotificationPermission()
        EchoManager.shared.rescheduleAllEchoes()
        await EchoManager.shared.checkForFiredEchoes()
        EchoManager.shared.scheduleNextCheck()

        // Auto-commit check (creates commits for notes modified before today)
        await autoCommitManager.checkAndAutoCommit()

        // Auto-sync if authenticated and tier allows it
        let isAuthed = AuthManager.shared.isAuthenticated
        let canSync = TierManager.shared.limits.cloudSync
        print("[AppState] Sync gate: authenticated=\(isAuthed), cloudSync=\(canSync), tier=\(TierManager.shared.currentTier.rawValue)")
        if isAuthed && canSync {
            await syncEngine.sync()
            await syncEngine.subscribeRealtime()
        }

        // Sync profile images from cloud (downloads if they exist remotely but not locally)
        if AuthManager.shared.isAuthenticated {
            await ProfileImageManager.shared.syncFromCloud()
        }

        // Seed first-run demo note
        await seedFirstRunNoteIfNeeded()
    }

    private func seedFirstRunNoteIfNeeded() async {
        let key = "hasSeededFirstRunNote"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        do {
            // 1. Create the demo note
            let note = try await noteRepository.createNote(title: "Welcome to Obius")

            // 2. Create two handles (loops)
            let groceryHandle = try await handleRepository.createHandle(
                name: "grocery_list", content: "Milk, Eggs, Bread"
            )
            let meetingHandle = try await handleRepository.createHandle(
                name: "meeting_notes", content: "Discuss project timeline"
            )

            // 3. Create sections: intro text, 2 portal sections, explanation text
            let introSection = try await sectionRepository.createSection(
                noteId: note.id, content: "This note demonstrates Loops — synced content blocks."
            )
            let portalSection1 = try await sectionRepository.createSection(
                noteId: note.id, content: "", afterSectionId: introSection.id
            )
            try await sectionRepository.linkSectionToHandle(
                sectionId: portalSection1.id, handleId: groceryHandle.id
            )
            let portalSection2 = try await sectionRepository.createSection(
                noteId: note.id, content: "", afterSectionId: portalSection1.id
            )
            try await sectionRepository.linkSectionToHandle(
                sectionId: portalSection2.id, handleId: meetingHandle.id
            )
            _ = try await sectionRepository.createSection(
                noteId: note.id,
                content: "Edit a Loop here — it updates everywhere it appears.",
                afterSectionId: portalSection2.id
            )

            print("[FirstRun] Seeded demo note with 2 loop portals")
        } catch {
            print("[FirstRun] Failed to seed demo note: \(error)")
        }
    }

    func triggerSync() async {
        guard TierManager.shared.limits.cloudSync else { return }
        await syncEngine.sync()
    }

    #if os(iOS)
    // MARK: - Background Auto-Commit

    /// Called from BGProcessingTask handler at midnight.
    /// Creates a minimal AppState just to run auto-commits.
    static func backgroundAutoCommit(task: BGProcessingTask) async {
        do {
            let appState = AppState()
            await appState.autoCommitManager.checkAndAutoCommit()
            task.setTaskCompleted(success: true)
        }
    }
    #endif
}

// MARK: - Notification Names

extension Notification.Name {
    static let echoNotificationTapped = Notification.Name("echoNotificationTapped")
    static let createNewNote = Notification.Name("createNewNote")
}
