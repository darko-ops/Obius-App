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
                .sheet(isPresented: $tierManager.showPowerPackPaywall) {
                    PowerPackPaywall()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        Task {
                            await EchoManager.shared.checkForFiredEchoes()
                            await appState.autoCommitManager.checkAndAutoCommit()
                            // Sync on every foreground (only if already initialized)
                            if appState.isInitialized && AuthManager.shared.isAuthenticated && (TierManager.shared.limits.cloudSync || AppState.debugForceSyncEnabled) {
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
        sectionRepository.syncLogger = syncLogger
        noteRepository.syncLogger = syncLogger

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
        let canSync = TierManager.shared.limits.cloudSync || AppState.debugForceSyncEnabled
        print("[AppState] Sync gate: authenticated=\(isAuthed), cloudSync=\(canSync), tier=\(TierManager.shared.currentTier.rawValue)\(AppState.debugForceSyncEnabled ? " [DEBUG override]" : "")")
        if isAuthed && canSync {
            await syncEngine.sync()
            await syncEngine.subscribeRealtime()
        }

        // Sync profile images from cloud (downloads if they exist remotely but not locally)
        if AuthManager.shared.isAuthenticated {
            await ProfileImageManager.shared.syncFromCloud()
        }

        // Upload existing local media to cloud for cross-device sync (one-time)
        if AuthManager.shared.isAuthenticated && canSync {
            Task { await mediaRepository.syncExistingMediaToCloud() }
        }

        // Seed first-run demo note
        await seedFirstRunNoteIfNeeded()
    }

    private func seedFirstRunNoteIfNeeded() async {
        let key = "hasSeededDemoContentV2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        do {
            try await seedDemoContent()
            print("[FirstRun] Seeded demo content (V2)")
        } catch {
            print("[FirstRun] Failed to seed demo content: \(error)")
        }
    }

    /// Builds a first-launch demo that teaches Obius by example:
    /// a primary "Welcome" note with one section per intent color, a Loop
    /// portal block, an Echo portal block, plus a second note that shares
    /// the same Loop so users see cross-note sync in action.
    private func seedDemoContent() async throws {
        // MARK: Loops

        let launchHandle = try await handleRepository.createHandle(
            name: "launch_checklist",
            content: """
            - Finalize App Store screenshots
            - Schedule launch announcement for 10 AM PT
            - Thank the 5 beta testers individually
            - Open the front door — we're live
            """,
            intent: .task
        )

        let standupHandle = try await handleRepository.createHandle(
            name: "daily_standup",
            content: """
            Yesterday: shipped the onboarding flow.
            Today: wire up TestFlight feedback channel.
            Blockers: none.
            """,
            intent: .evidence
        )

        // MARK: Welcome note

        let welcome = try await noteRepository.createNote(
            title: "Welcome to Obius",
            intent: .idea
        )

        var previousId: String? = nil

        func addSection(_ text: String, intent: IntentType) async throws -> String {
            let s = try await sectionRepository.createSection(
                noteId: welcome.id,
                content: text,
                afterSectionId: previousId
            )
            try await sectionRepository.setIntent(s.id, intent: intent)
            previousId = s.id
            return s.id
        }

        func addPortalSection(handleId: String, intent: IntentType) async throws -> String {
            let s = try await sectionRepository.createSection(
                noteId: welcome.id,
                content: "",
                afterSectionId: previousId
            )
            try await sectionRepository.linkSectionToHandle(sectionId: s.id, handleId: handleId)
            try await sectionRepository.setIntent(s.id, intent: intent)
            previousId = s.id
            return s.id
        }

        _ = try await addSection(
            "Welcome. This note is yours — edit it, delete it, or keep it around. Every section below is real and editable. Tap any one to change its color.",
            intent: .idea
        )

        _ = try await addSection(
            "Sections carry intent. The color tells you what kind of thinking lives there — at a glance, without reading a word.",
            intent: .evidence
        )

        _ = try await addSection(
            "Open — half-formed, still exploring.\n\n\"What if my notes could think back at me?\"",
            intent: .idea
        )

        _ = try await addSection(
            "Waiting — questions held, decisions deferred.\n\n\"Polish dark mode before launch, or after?\"",
            intent: .question
        )

        _ = try await addSection(
            "Active — in motion right now.\n\n\"Cutting the App Store screenshots.\"",
            intent: .evidence
        )

        _ = try await addSection(
            "Issue — broken, blocked, needs attention.\n\n\"Onboarding drop-off after the second screen.\"",
            intent: .issue
        )

        _ = try await addSection(
            "Done — locked in.\n\n\"Submitted to App Store.\"",
            intent: .task
        )

        _ = try await addSection(
            "Loops — reusable content blocks prefixed with @. Edit one, every copy updates. The block below is a live Loop. So is the one in your second demo note, 'Project: launch'. Try editing either — both stay in sync.",
            intent: .idea
        )

        _ = try await addPortalSection(handleId: launchHandle.id, intent: .task)

        _ = try await addSection(
            "Echoes — time-based reminders attached to a Loop. They resurface the whole note with its context, not a one-line ping. The Loop below has a daily Echo attached — long-press a Loop in the Library to set your own.",
            intent: .evidence
        )

        _ = try await addPortalSection(handleId: standupHandle.id, intent: .evidence)

        _ = try await addSection(
            "Ready to make your own? Tap + at the bottom of the notes list to start a new note.\n\nSign in any time from Settings to sync across all your devices.",
            intent: .idea
        )

        // MARK: Second note (cross-note Loop demonstration)

        let projectNote = try await noteRepository.createNote(
            title: "Project: launch",
            intent: .task
        )

        let intro = try await sectionRepository.createSection(
            noteId: projectNote.id,
            content: "Same launch checklist as in 'Welcome to Obius' — edit it here and it changes there too. That's a Loop."
        )
        try await sectionRepository.setIntent(intro.id, intent: .idea)

        let sharedPortal = try await sectionRepository.createSection(
            noteId: projectNote.id,
            content: "",
            afterSectionId: intro.id
        )
        try await sectionRepository.linkSectionToHandle(
            sectionId: sharedPortal.id, handleId: launchHandle.id
        )
        try await sectionRepository.setIntent(sharedPortal.id, intent: .task)

        // MARK: Echo on @daily_standup — daily at 9 AM starting tomorrow

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.day = (components.day ?? 0) + 1
        components.hour = 9
        components.minute = 0
        let tomorrow9AM = calendar.date(from: components) ?? Date().addingTimeInterval(86400)

        _ = try await echoRepository.createEcho(
            handleId: standupHandle.id,
            isRecurring: true,
            intervals: [EchoInterval(value: 1, unit: .days)],
            fireDate: Int64(tomorrow9AM.timeIntervalSince1970 * 1000)
        )
    }

    func triggerSync() async {
        guard TierManager.shared.limits.cloudSync || AppState.debugForceSyncEnabled else { return }
        await syncEngine.sync()
    }

    /// Debug-only override that lets a developer bypass the tier gate for
    /// cloud sync. Reads `debugForceSyncEnabled` from `UserDefaults`. Always
    /// returns `false` in release builds — the production gate stays intact.
    static var debugForceSyncEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "debugForceSyncEnabled")
        #else
        return false
        #endif
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
