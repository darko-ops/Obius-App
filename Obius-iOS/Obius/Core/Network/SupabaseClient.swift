import Foundation
import Supabase

/// Supabase client configuration for OBIUS
final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient
    
    /// Whether Supabase is properly configured
    let isConfigured: Bool

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

        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: AppConfiguration.supabaseAnonKey,
            options: .init(
                auth: .init(
                    storage: KeychainLocalStorage(
                        service: "supabase.gotrue.swift",
                        accessGroup: "W276447S6T.app.obius.shared"
                    )
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

    func invokeFunction<T: Decodable>(
        _ name: String,
        body: some Encodable
    ) async throws -> T {
        let data: Data = try await client.functions.invoke(
            name,
            options: .init(body: body)
        )
        return try JSONDecoder().decode(T.self, from: data)
    }

    func invokeFunction(
        _ name: String,
        body: some Encodable
    ) async throws {
        let _: Data = try await client.functions.invoke(
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
