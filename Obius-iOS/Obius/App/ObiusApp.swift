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
    @Published private(set) var database: DatabaseManager
    @Published private(set) var noteRepository: NoteRepository
    @Published private(set) var sectionRepository: SectionRepository
    @Published private(set) var handleRepository: HandleRepository  // Handle Loop support
    @Published private(set) var echoRepository: EchoRepository      // Echo alert/reminder support
    @Published private(set) var shareLinkRepository: ShareLinkRepository  // Share link support
    @Published private(set) var commentRepository: CommentRepository      // Share comments support
    @Published private(set) var moduleRepository: ModuleRepository        // Module (folder) support
    @Published private(set) var syncEngine: SyncEngine
    @Published private(set) var syncLogger: SyncOperationLogger

    // Split-Storage Engine components
    let coldStore: ColdStore  // singleton, retargeted via switchUser
    @Published private(set) var commitRepository: CommitRepository
    @Published private(set) var mediaRepository: MediaRepository
    @Published private(set) var commitModule: CommitModule
    @Published private(set) var autoCommitManager: AutoCommitManager
    @Published private(set) var insightRepository: InsightRepository
    @Published private(set) var calendarMemoRepository: CalendarMemoRepository
    @Published private(set) var noteIndexRepository: NoteIndexRepository
    @Published private(set) var contextAssembler: ContextAssembler

    /// Identifier of the user the local database is currently scoped to. `nil` = anon.
    @Published private(set) var currentUserId: String?

    @Published var isInitialized = false
    /// Set to true if the database had to be recreated from scratch due to corruption.
    /// The UI can check this to inform the user that local data was reset.
    @Published var didRecoverFromCorruption = false

    private var authObservationTask: Task<Void, Never>?
    private var isSwitching = false
    private var pendingSwitchTarget: String?? = nil

    init() {
        // Read the synchronous Supabase session so cold launch opens the right
        // per-user file immediately, with no anon→user flash.
        let bootUserId = SupabaseManager.shared.currentSession?.user.id.uuidString.lowercased()

        // Migrate database from legacy path / shared file to per-user file (one-time)
        DatabaseMigrationHelper.migrateIfNeeded(currentUserId: bootUserId)
        ColdStore.migrateLegacyDirectoriesIfNeeded(currentUserId: bootUserId)
        ProfileImageManager.migrateLegacyDirectoryIfNeeded(currentUserId: bootUserId)

        // Point ColdStore + ProfileImageManager at this user's directories before any
        // dependent code runs.
        ColdStore.shared.switchUser(bootUserId)
        ProfileImageManager.shared.switchUser(bootUserId)
        self.coldStore = ColdStore.shared

        do {
            let opened = try Self.openDatabase(forUserId: bootUserId)
            let bundle = Self.makeRepositories(database: opened.manager, coldStore: ColdStore.shared)

            self.database = opened.manager
            self.currentUserId = bootUserId
            if opened.wasRecovered { self.didRecoverFromCorruption = true }
            self.noteRepository = bundle.noteRepository
            self.sectionRepository = bundle.sectionRepository
            self.handleRepository = bundle.handleRepository
            self.echoRepository = bundle.echoRepository
            self.shareLinkRepository = bundle.shareLinkRepository
            self.commentRepository = bundle.commentRepository
            self.moduleRepository = bundle.moduleRepository
            self.syncEngine = bundle.syncEngine
            self.syncLogger = bundle.syncLogger
            self.commitRepository = bundle.commitRepository
            self.mediaRepository = bundle.mediaRepository
            self.commitModule = bundle.commitModule
            self.autoCommitManager = bundle.autoCommitManager
            self.insightRepository = bundle.insightRepository
            self.calendarMemoRepository = bundle.calendarMemoRepository
            self.noteIndexRepository = bundle.noteIndexRepository
            self.contextAssembler = bundle.contextAssembler

            wireSingletons(with: bundle)
            observeAuthChanges()
        } catch {
            fatalError("Failed to initialize database after recovery attempt: \(error)")
        }
    }

    deinit {
        authObservationTask?.cancel()
    }

    // MARK: - Repository assembly

    private struct RepositoryBundle {
        let noteRepository: NoteRepository
        let sectionRepository: SectionRepository
        let handleRepository: HandleRepository
        let echoRepository: EchoRepository
        let shareLinkRepository: ShareLinkRepository
        let commentRepository: CommentRepository
        let moduleRepository: ModuleRepository
        let syncEngine: SyncEngine
        let syncLogger: SyncOperationLogger
        let commitRepository: CommitRepository
        let mediaRepository: MediaRepository
        let commitModule: CommitModule
        let autoCommitManager: AutoCommitManager
        let insightRepository: InsightRepository
        let calendarMemoRepository: CalendarMemoRepository
        let noteIndexRepository: NoteIndexRepository
        let contextAssembler: ContextAssembler
    }

    private static func makeRepositories(database: DatabaseManager, coldStore: ColdStore) -> RepositoryBundle {
        let noteRepository = NoteRepository(database: database)
        let sectionRepository = SectionRepository(database: database)
        let handleRepository = HandleRepository(database: database)
        let echoRepository = EchoRepository(database: database)
        let shareLinkRepository = ShareLinkRepository(database: database)
        let commentRepository = CommentRepository(database: database)
        let moduleRepository = ModuleRepository(database: database)
        let syncEngine = SyncEngine(database: database)
        let syncLogger = SyncOperationLogger(database: database)
        handleRepository.syncLogger = syncLogger
        echoRepository.syncLogger = syncLogger
        moduleRepository.syncLogger = syncLogger

        let commitRepository = CommitRepository(database: database)
        let mediaRepository = MediaRepository(database: database, coldStore: coldStore)
        let commitModule = CommitModule(
            coldStore: coldStore,
            noteRepository: noteRepository,
            sectionRepository: sectionRepository,
            commitRepository: commitRepository
        )
        let autoCommitManager = AutoCommitManager(
            commitModule: commitModule,
            noteRepository: noteRepository,
            commitRepository: commitRepository,
            sectionRepository: sectionRepository,
            coldStore: coldStore
        )
        let insightRepository = InsightRepository(database: database)
        let calendarMemoRepository = CalendarMemoRepository(database: database)
        calendarMemoRepository.syncLogger = syncLogger

        let noteIndexRepository = NoteIndexRepository(database: database)
        let contextAssembler = ContextAssembler(
            noteIndexRepo: noteIndexRepository,
            sectionRepository: sectionRepository,
            noteRepository: noteRepository,
            handleRepository: handleRepository,
            database: database,
            syncEngine: syncEngine
        )

        return RepositoryBundle(
            noteRepository: noteRepository,
            sectionRepository: sectionRepository,
            handleRepository: handleRepository,
            echoRepository: echoRepository,
            shareLinkRepository: shareLinkRepository,
            commentRepository: commentRepository,
            moduleRepository: moduleRepository,
            syncEngine: syncEngine,
            syncLogger: syncLogger,
            commitRepository: commitRepository,
            mediaRepository: mediaRepository,
            commitModule: commitModule,
            autoCommitManager: autoCommitManager,
            insightRepository: insightRepository,
            calendarMemoRepository: calendarMemoRepository,
            noteIndexRepository: noteIndexRepository,
            contextAssembler: contextAssembler
        )
    }

    private func wireSingletons(with bundle: RepositoryBundle) {
        HandleManager.shared.initialize(handleRepository: bundle.handleRepository)
        EchoManager.shared.initialize(echoRepository: bundle.echoRepository)
        ShareManager.shared.initialize(
            shareLinkRepository: bundle.shareLinkRepository,
            commentRepository: bundle.commentRepository
        )
    }

    /// Try to open the database. If it fails (corruption, migration error, etc.),
    /// back up the broken file and create a fresh database.
    private static func openDatabase(forUserId userId: String?) throws -> (manager: DatabaseManager, wasRecovered: Bool) {
        do {
            let manager = try DatabaseManager(userId: userId)
            return (manager, false)
        } catch {
            print("[AppState] Database initialization failed: \(error)")
            print("[AppState] Attempting corruption recovery...")
            if DatabaseManager.recoverFromCorruption(forUserId: userId) {
                // Retry with a fresh database
                let manager = try DatabaseManager(userId: userId)
                print("[AppState] Recovery successful — fresh database created")
                return (manager, true)
            }
            throw error
        }
    }

    // MARK: - Account switching

    /// Watches the Supabase auth stream for sign-in/sign-out and re-points the
    /// local store at the corresponding per-user database file.
    /// We listen to `authStateChanges` directly (not `AuthManager.$currentUser`)
    /// because that publisher initializes to `nil` and races with the async
    /// session-refresh on cold launch — which would spuriously switch us back
    /// to the anon database immediately after we booted with a real user.
    private func observeAuthChanges() {
        authObservationTask?.cancel()
        authObservationTask = Task { [weak self] in
            for await (event, session) in SupabaseManager.shared.client.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .signedIn:
                    let newUserId = session?.user.id.uuidString.lowercased()
                    if newUserId != self.currentUserId {
                        await self.switchUser(to: newUserId)
                    }
                case .signedOut:
                    if self.currentUserId != nil {
                        await self.switchUser(to: nil)
                    }
                default:
                    // .tokenRefreshed / .userUpdated / .initialSession etc. do not change identity.
                    // For any unknown event, reconcile against the synchronous session in case
                    // identity drifted (defensive — should be rare).
                    let canonicalUserId = SupabaseManager.shared.currentSession?.user.id.uuidString.lowercased()
                    if canonicalUserId != self.currentUserId {
                        await self.switchUser(to: canonicalUserId)
                    }
                }
            }
        }
    }

    /// Tear down the active per-user state and rebuild it for `newUserId`.
    /// Triggered automatically when the auth state changes.
    /// If a switch is already in-flight, the latest target is queued and applied
    /// once the current swap finishes (so a sign-out during sign-in's `initialize()`
    /// is not lost).
    func switchUser(to newUserId: String?) async {
        // Record the latest request. `String??` distinguishes "no pending request"
        // (`nil`) from "pending request to switch to anon" (`.some(nil)`).
        pendingSwitchTarget = .some(newUserId)
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }

        while let next = pendingSwitchTarget {
            pendingSwitchTarget = nil
            let target = next
            guard target != currentUserId else { continue }

            print("[AppState] Switching active user: \(currentUserId ?? "anon") → \(target ?? "anon")")

            // 1. Tear down sync engine subscriptions on the old database.
            await syncEngine.unsubscribeRealtime()

            // 2. Drop singleton state so they don't keep observing the old DB queue.
            HandleManager.shared.reset()
            EchoManager.shared.reset()
            ShareManager.shared.reset()
            // Tier state is per-user; clear before initialize() re-fetches from server.
            // Otherwise the new user inherits the previous user's tier, and a Free
            // account stays "Pro" because the no-entitlement downgrade is gated on
            // serverConfirmedTier being nil.
            TierManager.shared.logout()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

            // 3. Repoint cold storage + profile images, and open the new database.
            ColdStore.shared.switchUser(target)
            ProfileImageManager.shared.switchUser(target)

            let opened: (manager: DatabaseManager, wasRecovered: Bool)
            do {
                opened = try Self.openDatabase(forUserId: target)
            } catch {
                print("[AppState] Failed to open database for user \(target ?? "anon"): \(error)")
                continue
            }

            let bundle = Self.makeRepositories(database: opened.manager, coldStore: coldStore)

            // 4. Publish the new bundle. SwiftUI observers re-render and pick up new repos.
            self.database = opened.manager
            self.noteRepository = bundle.noteRepository
            self.sectionRepository = bundle.sectionRepository
            self.handleRepository = bundle.handleRepository
            self.echoRepository = bundle.echoRepository
            self.shareLinkRepository = bundle.shareLinkRepository
            self.commentRepository = bundle.commentRepository
            self.moduleRepository = bundle.moduleRepository
            self.syncEngine = bundle.syncEngine
            self.syncLogger = bundle.syncLogger
            self.commitRepository = bundle.commitRepository
            self.mediaRepository = bundle.mediaRepository
            self.commitModule = bundle.commitModule
            self.autoCommitManager = bundle.autoCommitManager
            self.insightRepository = bundle.insightRepository
            self.calendarMemoRepository = bundle.calendarMemoRepository
            self.noteIndexRepository = bundle.noteIndexRepository
            self.contextAssembler = bundle.contextAssembler
            self.currentUserId = target
            self.didRecoverFromCorruption = self.didRecoverFromCorruption || opened.wasRecovered
            self.isInitialized = false

            wireSingletons(with: bundle)

            // 5. Re-run startup so the new account gets sync, echo scheduling, etc.
            await initialize()
        }
    }

    /// Delete all local data (notes, sections, handles, echoes, etc.) from the device.
    /// Cloud data is not affected — signing in again will re-sync.
    func deleteAllLocalData() async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM sections")
            try db.execute(sql: "DELETE FROM notes")
            try db.execute(sql: "DELETE FROM handles")
            try db.execute(sql: "DELETE FROM echoes")
            try db.execute(sql: "DELETE FROM commits")
            try db.execute(sql: "DELETE FROM media")
            try db.execute(sql: "DELETE FROM note_media")
            try db.execute(sql: "DELETE FROM shareLinks")
            try db.execute(sql: "DELETE FROM comments")
            try db.execute(sql: "DELETE FROM insights")
            try db.execute(sql: "DELETE FROM modules")
            try db.execute(sql: "DELETE FROM syncOperations")
        }
        // Clear cold store (commit .obx files)
        try? coldStore.clearAll()
        // Cancel pending echo notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("[AppState] All local data deleted")
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

        // Clean up expired versions based on retention settings
        _ = await VersionRetentionManager.runCleanup(commitRepository: commitRepository, coldStore: coldStore)

        // Re-fetch tier for the current user before the sync gate decision.
        // On account switch, switchUser() called TierManager.logout() to clear
        // the previous user's state; this re-populates it from Supabase + RC.
        await TierManager.shared.initialize()

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

        // Upload existing local media to cloud for cross-device sync (one-time)
        if AuthManager.shared.isAuthenticated && TierManager.shared.limits.cloudSync {
            Task { await mediaRepository.syncExistingMediaToCloud() }
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
