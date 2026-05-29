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

    /// Set to the user's email after sign-up when the Supabase project requires
    /// email confirmation and no session was issued. The sign-up screen reads
    /// this to show a "Check your email" state. Cleared on `.signedIn` (i.e.
    /// after the user taps the confirmation link) or when the UI resets.
    @Published private(set) var pendingEmailConfirmation: String?

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
                    pendingEmailConfirmation = nil
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
        pendingEmailConfirmation = nil
        isLoading = true
        defer { isLoading = false }

        // Set the global signup flag BEFORE calling supabase.signUp. The
        // Supabase SDK emits `.signedIn` from within its internal awaits, so
        // AppState's auth-state observer can run `switchUser → initialize`
        // before this method returns. AppState.initialize converts this flag
        // into a per-user pending flag once it knows the new user's id.
        OnboardingSeeder.markSignupInProgress()

        do {
            var metadata: [String: AnyJSON]? = nil
            if let displayName = displayName {
                metadata = ["display_name": .string(displayName)]
            }

            let result = try await supabase.signUp(email: email, password: password, data: metadata)

            if result.session != nil {
                // No email confirmation required — user is fully signed in.
                // Belt-and-suspenders: also mark per-user pending here, but ONLY
                // if the observer hasn't yet consumed the global flag. If it has,
                // it already ran the seed and re-marking would cause a duplicate
                // on the next initialize().
                if OnboardingSeeder.isSignupInProgress() {
                    OnboardingSeeder.markPending(userId: result.user.id.uuidString.lowercased())
                }
                currentUser = result.user
                isAuthenticated = true

                // Sync RevenueCat identity
                await StoreManager.shared.identify(userId: result.user.id.uuidString.lowercased())
            } else {
                // Email confirmation required — no session yet. The user must
                // tap the link in the confirmation email; that hits
                // obius://auth/callback and the auth-state observer flips
                // isAuthenticated. The global signup flag won't survive until
                // .signedIn fires later, so mark the per-user pending flag
                // directly using the user id we got back from signUp — that
                // way AppState.runPendingOnboardingSeedIfNeeded picks it up
                // when the confirmed session arrives.
                OnboardingSeeder.markPending(userId: result.user.id.uuidString.lowercased())
                OnboardingSeeder.clearSignupInProgress()
                pendingEmailConfirmation = email
            }
        } catch {
            OnboardingSeeder.clearSignupInProgress()
            authError = error.localizedDescription
        }
    }

    /// Reset the "Check your email" state — called when the user backs out of
    /// the confirmation screen to try a different email.
    func clearPendingEmailConfirmation() {
        pendingEmailConfirmation = nil
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

        // Clear tier state up front so the UI doesn't briefly show the previous
        // user's plan while supabase.signOut + the auth-state observer chain run.
        // AppState.switchUser also calls this, but the observer fires async — so
        // we want a deterministic synchronous reset here.
        TierManager.shared.logout()

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

    // MARK: - Delete Account

    /// Permanently deletes the user's cloud account and all associated data.
    /// Server-side cascade removes every row in public.* owned by this user, and
    /// storage objects under the user's folder are wiped. The local sign-out and
    /// on-device wipe are performed by the caller after this returns.
    func deleteAccount() async throws {
        struct EmptyBody: Encodable {}
        try await supabase.invokeFunction("delete-account", body: EmptyBody())
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
            try await supabase.client.auth.resetPasswordForEmail(
                email,
                redirectTo: SupabaseManager.authCallbackURL
            )
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - Deep Link Callback

    /// Called from `DeepLinkRouter` when an `obius://auth/callback` URL is received.
    /// Exchanges the code/tokens in the URL for a session; `authStateChanges` then
    /// flips `isAuthenticated`.
    func handleAuthCallback(_ url: URL) async {
        do {
            _ = try await supabase.handleAuthCallback(url)
        } catch {
            authError = error.localizedDescription
            print("[AuthManager] Auth callback failed: \(error)")
        }
    }

    deinit {
        authStateTask?.cancel()
    }
}
