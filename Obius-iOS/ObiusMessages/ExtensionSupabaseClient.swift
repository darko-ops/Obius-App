import Foundation
import Supabase

/// Lightweight Supabase client for the iMessage extension.
/// Reads the auth session from the shared keychain (written by the main app).
final class ExtensionSupabaseClient {
    static let shared = ExtensionSupabaseClient()

    let client: SupabaseClient

    private init() {
        let url = URL(string: Self.supabaseURL) ?? URL(string: "https://placeholder.supabase.co")!
        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: Self.supabaseAnonKey,
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

    // MARK: - Configuration

    /// Read Supabase URL from the extension's Info.plist (set via xcconfig)
    private static var supabaseURL: String {
        guard let url = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
              !url.isEmpty, !url.hasPrefix("$(") else {
            return "https://placeholder.supabase.co"
        }
        return url
    }

    private static var supabaseAnonKey: String {
        guard let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String,
              !key.isEmpty, !key.hasPrefix("$(") else {
            return "placeholder-anon-key"
        }
        return key
    }

    // MARK: - Auth Helpers

    var currentUser: User? {
        client.auth.currentUser
    }

    var isAuthenticated: Bool {
        client.auth.currentSession != nil
    }

    /// Restore the auth session from the shared keychain.
    /// Must be called once when the extension activates, before checking isAuthenticated.
    func restoreSession() async {
        do {
            _ = try await client.auth.session
        } catch {
            print("[ExtensionSupabase] Failed to restore session: \(error)")
        }
    }
}
