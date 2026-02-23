import Foundation

/// Centralized app configuration
/// Reads values from Info.plist (set via xcconfig files)
enum AppConfiguration {

    // MARK: - Environment

    enum Environment: String {
        case debug
        case release

        var isDebug: Bool { self == .debug }
        var isRelease: Bool { self == .release }
    }

    static var environment: Environment {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }

    // MARK: - Supabase

    /// Whether Supabase is configured (for offline-first testing)
    static var isSupabaseConfigured: Bool {
        guard let url = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
              !url.isEmpty, !url.hasPrefix("$(") else {
            return false
        }
        guard let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String,
              !key.isEmpty, !key.hasPrefix("$(") else {
            return false
        }
        return true
    }

    static var supabaseURL: String {
        guard let url = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
              !url.isEmpty, !url.hasPrefix("$(") else {
            // Return placeholder for offline testing
            return "https://placeholder.supabase.co"
        }
        return url
    }

    static var supabaseAnonKey: String {
        guard let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String,
              !key.isEmpty, !key.hasPrefix("$(") else {
            // Return placeholder for offline testing
            return "placeholder-anon-key"
        }
        return key
    }

    // MARK: - Claude API

    static var claudeAPIKey: String? {
        guard let key = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String,
              !key.isEmpty, !key.hasPrefix("$("), key != "YOUR_API_KEY_HERE" else {
            return nil
        }
        return key
    }

    // MARK: - API

    static var apiBaseURL: String {
        Bundle.main.infoDictionary?["OBIUS_API_BASE_URL"] as? String ?? "https://api.obius.io"
    }

    // MARK: - Logging

    enum LogLevel: String {
        case debug
        case info
        case warning
        case error

        var priority: Int {
            switch self {
            case .debug: return 0
            case .info: return 1
            case .warning: return 2
            case .error: return 3
            }
        }
    }

    static var logLevel: LogLevel {
        guard let level = Bundle.main.infoDictionary?["OBIUS_LOG_LEVEL"] as? String else {
            return environment.isDebug ? .debug : .error
        }
        return LogLevel(rawValue: level) ?? .error
    }

    static var isAnalyticsEnabled: Bool {
        guard let enabled = Bundle.main.infoDictionary?["OBIUS_ENABLE_ANALYTICS"] as? String else {
            return environment.isRelease
        }
        return enabled == "YES"
    }

    // MARK: - App Info

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var fullVersion: String {
        "\(appVersion) (\(buildNumber))"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "app.obius.ios"
    }

    // MARK: - Feature Flags

    static var isAIEnabled: Bool {
        // AI features only available online
        true
    }

    static var isSemanticSearchEnabled: Bool {
        // Semantic search requires embeddings
        true
    }

    static var maxNotesForFreeUser: Int {
        100
    }

    static var maxSectionsPerNote: Int {
        500
    }

    // MARK: - Sync Configuration

    static var syncDebounceInterval: TimeInterval {
        environment.isDebug ? 1.0 : 2.0
    }

    static var syncRetryMaxAttempts: Int {
        3
    }

    static var syncRetryBaseDelay: TimeInterval {
        1.0
    }

    static var maxPendingOperationsPerBatch: Int {
        100
    }

    // MARK: - Cache Configuration

    static var cacheExpirationDays: Int {
        7
    }

    static var maxCacheSizeMB: Int {
        50
    }

    // MARK: - Debug Helpers

    static func printConfiguration() {
        #if DEBUG
        print("""
        ╔════════════════════════════════════════╗
        ║        OBIUS CONFIGURATION             ║
        ╠════════════════════════════════════════╣
        ║ Environment: \(environment.rawValue.padding(toLength: 24, withPad: " ", startingAt: 0)) ║
        ║ Version: \(fullVersion.padding(toLength: 28, withPad: " ", startingAt: 0)) ║
        ║ Bundle ID: \(bundleIdentifier.padding(toLength: 26, withPad: " ", startingAt: 0)) ║
        ║ Log Level: \(logLevel.rawValue.padding(toLength: 26, withPad: " ", startingAt: 0)) ║
        ║ Analytics: \(isAnalyticsEnabled ? "Enabled" : "Disabled".padding(toLength: 26, withPad: " ", startingAt: 0)) ║
        ╚════════════════════════════════════════╝
        """)
        #endif
    }
}
