import SwiftUI
import UserNotifications

@main
struct ObiusApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authManager = AuthManager.shared
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(authManager)
                .task {
                    await appState.initialize()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        Task {
                            await EchoManager.shared.checkForFiredEchoes()
                        }
                    }
                }
        }
    }
}

// MARK: - Notification Delegate

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
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
    let syncEngine: SyncEngine
    let syncLogger: SyncOperationLogger

    // Split-Storage Engine components
    let coldStore: ColdStore
    let commitRepository: CommitRepository
    let mediaRepository: MediaRepository
    let commitModule: CommitModule
    let profileScanner: ProfileScanner

    @Published var isInitialized = false

    init() {
        do {
            self.database = try DatabaseManager()
            self.noteRepository = NoteRepository(database: database)
            self.sectionRepository = SectionRepository(database: database)
            self.handleRepository = HandleRepository(database: database)  // Handle Loop support
            self.echoRepository = EchoRepository(database: database)    // Echo alert/reminder support
            self.syncEngine = SyncEngine(database: database)
            self.syncLogger = SyncOperationLogger(database: database)

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
            self.profileScanner = ProfileScanner(
                coldStore: coldStore,
                commitRepository: commitRepository
            )

            // Initialize HandleManager singleton with repository
            HandleManager.shared.initialize(handleRepository: handleRepository)

            // Initialize EchoManager singleton with repository
            EchoManager.shared.initialize(echoRepository: echoRepository)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    func initialize() async {
        await syncEngine.initialize()
        isInitialized = true

        // Initialize Echo notifications
        await EchoManager.shared.requestNotificationPermission()
        EchoManager.shared.rescheduleAllEchoes()
        await EchoManager.shared.checkForFiredEchoes()

        // Auto-sync if authenticated
        if AuthManager.shared.isAuthenticated {
            await syncEngine.sync()
        }
    }

    func triggerSync() async {
        await syncEngine.sync()
    }
}
