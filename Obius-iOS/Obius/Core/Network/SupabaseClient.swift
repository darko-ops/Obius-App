import Foundation
import Supabase

/// Supabase client configuration for OBIUS
final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    /// Whether Supabase is properly configured
    let isConfigured: Bool

    /// Resolve the keychain access group dynamically using the app's team ID prefix.
    /// This ensures it works on both iOS and macOS regardless of sandbox/signing differences.
    private static var keychainAccessGroup: String {
        let fallback = "W276447S6T.app.obius.shared"
        guard let bundlePrefix = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String else {
            // AppIdentifierPrefix not in Info.plist — try reading from entitlements at build time
            // Fall back to the known team ID prefix
            return fallback
        }
        return "\(bundlePrefix)app.obius.shared"
    }

    private init() {
        self.isConfigured = AppConfiguration.isSupabaseConfigured

        // Always create a client (even with placeholder values for offline testing)
        guard let url = URL(string: AppConfiguration.supabaseURL) else {
            // Fallback URL for testing
            let fallbackURL = URL(string: "https://placeholder.supabase.co")!
            self.client = SupabaseClient(
                supabaseURL: fallbackURL,
                supabaseKey: "placeholder-key"
            )
            return
        }

        let accessGroup = Self.keychainAccessGroup
        #if DEBUG
        print("[SupabaseManager] Using keychain access group: \(accessGroup)")
        #endif

        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: AppConfiguration.supabaseAnonKey,
            options: .init(
                auth: .init(
                    storage: KeychainLocalStorage(
                        service: "supabase.gotrue.swift",
                        accessGroup: accessGroup
                    ),
                    autoRefreshToken: true
                )
            )
        )
    }

    // MARK: - Auth Helpers

    var currentUser: User? {
        client.auth.currentUser
    }

    var currentSession: Session? {
        client.auth.currentSession
    }

    var isAuthenticated: Bool {
        currentSession != nil
    }

    func signUp(email: String, password: String, data: [String: AnyJSON]? = nil) async throws -> User {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: data
        )
        return response.user
    }

    func signIn(email: String, password: String) async throws -> Session {
        try await client.auth.signIn(
            email: email,
            password: password
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func refreshSession() async throws -> Session {
        try await client.auth.refreshSession()
    }

    // MARK: - Edge Function Helpers

    /// Get a valid access token, refreshing if needed
    private func validAccessToken() async -> String? {
        // If current session is valid, use it
        if let session = client.auth.currentSession,
           session.expiresAt > Date().timeIntervalSince1970 + 30 { // 30s buffer
            return session.accessToken
        }
        // Try refreshing
        if let session = try? await client.auth.refreshSession() {
            return session.accessToken
        }
        return client.auth.currentSession?.accessToken
    }

    func invokeFunction<T: Decodable>(
        _ name: String,
        body: some Encodable
    ) async throws -> T {
        // Ensure token is fresh — the SDK handles passing it via fetchWithAuth
        _ = await validAccessToken()

        #if DEBUG
        if let session = client.auth.currentSession {
            let prefix = String(session.accessToken.prefix(20))
            print("[SupabaseManager] invokeFunction(\(name)) token: \(prefix)... expires: \(session.expiresAt)")
        } else {
            print("[SupabaseManager] invokeFunction(\(name)) — no session!")
        }
        #endif

        let result: T = try await client.functions.invoke(
            name,
            options: .init(body: body)
        )
        return result
    }

    func invokeFunction(
        _ name: String,
        body: some Encodable
    ) async throws {
        _ = await validAccessToken()
        try await client.functions.invoke(
            name,
            options: .init(body: body)
        )
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case signUpFailed
    case signInFailed
    case sessionExpired
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .signUpFailed:
            return "Failed to create account"
        case .signInFailed:
            return "Failed to sign in"
        case .sessionExpired:
            return "Your session has expired"
        case .notAuthenticated:
            return "Please sign in to continue"
        }
    }
}

// MARK: - Supabase Types Extension

extension User {
    var displayName: String? {
        userMetadata["display_name"]?.stringValue
    }

    var bio: String? {
        userMetadata["bio"]?.stringValue
    }

    var phoneNumber: String? {
        userMetadata["phone_number"]?.stringValue
    }
}
