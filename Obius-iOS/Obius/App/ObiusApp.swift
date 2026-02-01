import SwiftUI

@main
struct ObiusApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(authManager)
                .task {
                    await appState.initialize()
                }
        }
    }
}

@MainActor
class AppState: ObservableObject {
    let database: DatabaseManager
    let noteRepository: NoteRepository
    let sectionRepository: SectionRepository
    let handleRepository: HandleRepository  // Handle Loop support
    let syncEngine: SyncEngine
    let syncLogger: SyncOperationLogger

    @Published var isInitialized = false

    init() {
        do {
            self.database = try DatabaseManager()
            self.noteRepository = NoteRepository(database: database)
            self.sectionRepository = SectionRepository(database: database)
            self.handleRepository = HandleRepository(database: database)  // Handle Loop support
            self.syncEngine = SyncEngine(database: database)
            self.syncLogger = SyncOperationLogger(database: database)

            // Initialize HandleManager singleton with repository
            HandleManager.shared.initialize(handleRepository: handleRepository)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    func initialize() async {
        await syncEngine.initialize()
        isInitialized = true

        // Auto-sync if authenticated
        if AuthManager.shared.isAuthenticated {
            await syncEngine.sync()
        }
    }

    func triggerSync() async {
        await syncEngine.sync()
    }
}
