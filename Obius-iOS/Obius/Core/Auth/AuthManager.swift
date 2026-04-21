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

        // Always try to get a valid session — refreshSession() will use the
        // refresh token to obtain a fresh access token if the current one is expired.
        do {
            let session = try await supabase.refreshSession()

            // Verify the token is actually valid (not a stale cached return)
            if session.expiresAt > Date().timeIntervalSince1970 {
                currentUser = session.user
                isAuthenticated = true
                await StoreManager.shared.identify(userId: session.user.id.uuidString.lowercased())
                print("[AuthManager] Session valid, expires: \(Date(timeIntervalSince1970: session.expiresAt))")
            } else {
                // Token is expired even after refresh — verify with server
                print("[AuthManager] Refreshed token already expired, verifying with server...")
                let user = try await supabase.client.auth.user()
                currentUser = user
                isAuthenticated = true
                await StoreManager.shared.identify(userId: user.id.uuidString.lowercased())
                print("[AuthManager] Server verification succeeded")
            }
        } catch {
            // Check if there's a cached session we can use (user might be offline)
            if let session = supabase.currentSession {
                currentUser = session.user
                isAuthenticated = true
                await StoreManager.shared.identify(userId: session.user.id.uuidString.lowercased())
                print("[AuthManager] Using cached session (refresh failed: \(error.localizedDescription))")
            } else {
                currentUser = nil
                isAuthenticated = false
                print("[AuthManager] No valid session — user needs to sign in")
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
                    if let userId = session?.user.id.uuidString.lowercased() {
                        await StoreManager.shared.identify(userId: userId)
                    }
                case .signedOut:
                    currentUser = nil
                    isAuthenticated = false
                    await StoreManager.shared.logout()
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

            // Sync RevenueCat identity
            await StoreManager.shared.identify(userId: user.id.uuidString.lowercased())
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

            // Sync RevenueCat identity
            await StoreManager.shared.identify(userId: session.user.id.uuidString.lowercased())
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

            // Reset RevenueCat to anonymous user
            await StoreManager.shared.logout()
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

    // MARK: - Change Password

    /// Re-authenticates with the current password, then updates to the new password.
    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let email = currentUser?.email else {
            throw AuthError.noEmail
        }

        // Re-authenticate with current password to verify identity
        _ = try await supabase.signIn(email: email, password: currentPassword)

        // Update to new password
        _ = try await supabase.client.auth.update(user: .init(password: newPassword))
    }

    enum AuthError: LocalizedError {
        case noEmail

        var errorDescription: String? {
            switch self {
            case .noEmail: return "No email associated with this account."
            }
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
