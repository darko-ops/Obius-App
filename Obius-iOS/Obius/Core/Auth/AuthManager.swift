import Foundation
import Combine
import Supabase

/// Manages authentication state
@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    private let supabase = SupabaseManager.shared
    private var authStateTask: Task<Void, Never>?

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var currentUser: User?
    @Published private(set) var isLoading: Bool = true
    @Published var authError: String?

    private init() {
        // Check initial auth state
        Task {
            await checkAuthState()
            observeAuthState()
        }
    }

    // MARK: - Auth State

    private func checkAuthState() async {
        isLoading = true
        defer { isLoading = false }

        if let session = supabase.currentSession {
            currentUser = session.user
            isAuthenticated = true
        } else {
            // Try to restore session
            do {
                let session = try await supabase.refreshSession()
                currentUser = session.user
                isAuthenticated = true
            } catch {
                currentUser = nil
                isAuthenticated = false
            }
        }
    }

    private func observeAuthState() {
        authStateTask = Task {
            for await (event, session) in supabase.client.auth.authStateChanges {
                switch event {
                case .signedIn:
                    currentUser = session?.user
                    isAuthenticated = true
                case .signedOut:
                    currentUser = nil
                    isAuthenticated = false
                case .tokenRefreshed:
                    currentUser = session?.user
                case .userUpdated:
                    currentUser = session?.user
                default:
                    break
                }
            }
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String? = nil) async {
        authError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            var metadata: [String: AnyJSON]? = nil
            if let displayName = displayName {
                metadata = ["display_name": .string(displayName)]
            }

            let user = try await supabase.signUp(email: email, password: password, data: metadata)
            currentUser = user
            isAuthenticated = true
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async {
        authError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await supabase.signIn(email: email, password: password)
            currentUser = session.user
            isAuthenticated = true
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        authError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await supabase.signOut()
            currentUser = nil
            isAuthenticated = false
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - Update Profile

    func updateProfile(displayName: String, bio: String, phoneNumber: String) async {
        authError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let updatedUser = try await supabase.client.auth.update(user: .init(data: [
                "display_name": .string(displayName),
                "bio": .string(bio),
                "phone_number": .string(phoneNumber)
            ]))
            currentUser = updatedUser
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - Password Reset

    func sendPasswordReset(email: String) async {
        authError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await supabase.client.auth.resetPasswordForEmail(email)
        } catch {
            authError = error.localizedDescription
        }
    }

    deinit {
        authStateTask?.cancel()
    }
}
