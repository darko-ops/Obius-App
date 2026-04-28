import Foundation
import SwiftUI

/// Routes deep links (universal links and custom URL scheme) to the appropriate views.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    /// The slug of a shared link waiting to be displayed
    @Published var pendingShareSlug: String?

    private init() {}

    /// Handles an incoming URL and extracts a share slug if present.
    /// - Parameter url: The incoming URL
    /// - Returns: The extracted slug, or nil if the URL doesn't match
    @discardableResult
    func handleURL(_ url: URL) -> String? {
        // Auth callback: obius://auth/callback?code=... (PKCE) or #access_token=... (implicit)
        if url.scheme == "obius", url.host == "auth" {
            Task { await AuthManager.shared.handleAuthCallback(url) }
            return nil
        }

        // Universal link: https://obius.io/s/{slug}
        if let host = url.host,
           (host == "obius.io" || host == "www.obius.io"),
           url.pathComponents.count >= 3,
           url.pathComponents[1] == "s" {
            let slug = url.pathComponents[2]
            pendingShareSlug = slug
            return slug
        }

        // Custom scheme: obius://share/{slug}
        if url.scheme == "obius",
           url.host == "share",
           let slug = url.pathComponents.last,
           slug != "/" {
            pendingShareSlug = slug
            return slug
        }

        return nil
    }

    /// Identifiable wrapper for use with `.fullScreenCover(item:)`
    var pendingShareSlugItem: ShareSlugItem? {
        get {
            pendingShareSlug.map { ShareSlugItem(slug: $0) }
        }
        set {
            pendingShareSlug = newValue?.slug
        }
    }

    /// Clears the pending slug after navigation has occurred.
    func clearPending() {
        pendingShareSlug = nil
    }
}

/// Identifiable wrapper for a share slug string.
struct ShareSlugItem: Identifiable {
    let slug: String
    var id: String { slug }
}
