import Foundation
import SwiftUI
import Supabase

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Manages local storage and cloud sync of profile and banner images.
/// Images are stored locally for fast access and synced to Supabase Storage
/// so they appear on all devices (iOS + macOS).
@MainActor
final class ProfileImageManager: ObservableObject {
    static let shared = ProfileImageManager()

    private let fileManager = FileManager.default
    private var profileDirectory: URL
    private(set) var userId: String?
    private let supabase = SupabaseManager.shared
    private let storageBucket = "profile-images"

    @Published var profileImage: PlatformImage?
    @Published var bannerImage: PlatformImage?

    private init() {
        let userId: String? = nil
        self.userId = userId
        self.profileDirectory = Self.directory(forUserId: userId)
        try? fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        loadLocalImages()
    }

    /// Returns the per-user profile-image directory. Anonymous users get a
    /// dedicated `users/anon` scope so account A's avatar/banner never leak
    /// into account B.
    private static func directory(forUserId userId: String?) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let scope = (userId?.isEmpty == false ? userId!.lowercased() : "anon")
        return documents
            .appendingPathComponent("users", isDirectory: true)
            .appendingPathComponent(scope, isDirectory: true)
            .appendingPathComponent("profile", isDirectory: true)
    }

    /// Re-point storage at a different user. Clears in-memory images first so
    /// the previous user's avatar/banner don't briefly remain visible while
    /// the new user's local files load.
    func switchUser(_ userId: String?) {
        guard userId != self.userId else { return }
        self.userId = userId
        self.profileDirectory = Self.directory(forUserId: userId)
        try? fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        profileImage = nil
        bannerImage = nil
        loadLocalImages()
    }

    /// One-time migration of the legacy single-tenant `Documents/profile/`
    /// into the booting user's scope. Safe to call repeatedly.
    static func migrateLegacyDirectoryIfNeeded(currentUserId: String?) {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let legacy = documents.appendingPathComponent("profile", isDirectory: true)
        guard fm.fileExists(atPath: legacy.path) else { return }

        let destination = directory(forUserId: currentUserId)
        try? fm.createDirectory(at: destination.deletingLastPathComponent(),
                                withIntermediateDirectories: true)

        if !fm.fileExists(atPath: destination.path) {
            do {
                try fm.moveItem(at: legacy, to: destination)
                print("[ProfileImages] Migrated legacy profile/ → \(destination.path)")
                return
            } catch {
                print("[ProfileImages] Legacy move failed: \(error)")
            }
        }

        // Destination already exists — merge contents.
        if let contents = try? fm.contentsOfDirectory(atPath: legacy.path) {
            for item in contents {
                let src = legacy.appendingPathComponent(item)
                let dst = destination.appendingPathComponent(item)
                if !fm.fileExists(atPath: dst.path) {
                    try? fm.moveItem(at: src, to: dst)
                }
            }
            if let remaining = try? fm.contentsOfDirectory(atPath: legacy.path), remaining.isEmpty {
                try? fm.removeItem(at: legacy)
            }
        }
    }

    // MARK: - File Paths

    private var profileImageURL: URL {
        profileDirectory.appendingPathComponent("avatar.jpg")
    }

    private var bannerImageURL: URL {
        profileDirectory.appendingPathComponent("banner.jpg")
    }

    // MARK: - Remote Paths

    private func remotePath(for type: ImageType) -> String? {
        guard let userId = supabase.currentUser?.id.uuidString.lowercased() else {
            print("[ProfileImages] No authenticated user — skipping cloud \(type)")
            return nil
        }
        return "\(userId)/\(type == .avatar ? "avatar" : "banner").jpg"
    }

    enum ImageType: CustomStringConvertible {
        case avatar, banner
        var description: String {
            switch self {
            case .avatar: return "avatar"
            case .banner: return "banner"
            }
        }
    }

    // MARK: - Load Local

    private func loadLocalImages() {
        if let data = try? Data(contentsOf: profileImageURL),
           let image = PlatformImage(data: data) {
            profileImage = image
            print("[ProfileImages] Loaded local avatar (\(data.count) bytes)")
        }
        if let data = try? Data(contentsOf: bannerImageURL),
           let image = PlatformImage(data: data) {
            bannerImage = image
            print("[ProfileImages] Loaded local banner (\(data.count) bytes)")
        }
    }

    // MARK: - Sync from Cloud

    /// Download profile images from Supabase Storage if they exist.
    /// Call this after authentication or on app launch when authenticated.
    func syncFromCloud() async {
        guard supabase.isAuthenticated else {
            print("[ProfileImages] syncFromCloud skipped — not authenticated")
            return
        }
        print("[ProfileImages] syncFromCloud starting for user: \(supabase.currentUser?.id.uuidString ?? "nil")")

        await syncOne(type: .avatar)
        await syncOne(type: .banner)
    }

    /// Two-way reconciliation for a single image type:
    ///   - If cloud has it: download and overwrite local.
    ///   - If cloud is missing it (404) but local has a copy: upload local.
    /// This self-heals past upload misses (e.g. banner set while signed out
    /// so the original `uploadToCloud` was silently skipped).
    private func syncOne(type: ImageType) async {
        let downloaded = await downloadAndSave(type: type)
        guard !downloaded else { return }

        let localURL = type == .avatar ? profileImageURL : bannerImageURL
        guard let localData = try? Data(contentsOf: localURL), !localData.isEmpty else {
            return
        }
        print("[ProfileImages] Cloud missing \(type) but local exists — pushing local to cloud (\(localData.count) bytes)")
        await uploadToCloud(data: localData, type: type)
    }

    /// Returns `true` if a cloud copy was found and saved locally.
    @discardableResult
    private func downloadAndSave(type: ImageType) async -> Bool {
        guard let path = remotePath(for: type) else { return false }

        print("[ProfileImages] Downloading \(type) from: \(storageBucket)/\(path)")

        do {
            let data = try await supabase.client.storage
                .from(storageBucket)
                .download(path: path)

            print("[ProfileImages] Downloaded \(type): \(data.count) bytes")

            guard let image = PlatformImage(data: data) else {
                print("[ProfileImages] Failed to create image from downloaded \(type) data")
                return false
            }

            // Save locally
            let localURL = type == .avatar ? profileImageURL : bannerImageURL
            try data.write(to: localURL)
            print("[ProfileImages] Saved \(type) locally to: \(localURL.path)")

            // Update published property
            switch type {
            case .avatar: profileImage = image
            case .banner: bannerImage = image
            }
            return true
        } catch {
            print("[ProfileImages] Cloud download FAILED for \(type): \(error)")
            return false
        }
    }

    // MARK: - Save (Local + Cloud)

    func saveProfileImage(_ image: PlatformImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            print("[ProfileImages] Failed to encode avatar as JPEG")
            return
        }
        try? data.write(to: profileImageURL)
        profileImage = image
        print("[ProfileImages] Saved avatar locally (\(data.count) bytes)")

        Task { await uploadToCloud(data: data, type: .avatar) }
    }

    func saveBannerImage(_ image: PlatformImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            print("[ProfileImages] Failed to encode banner as JPEG")
            return
        }
        try? data.write(to: bannerImageURL)
        bannerImage = image
        print("[ProfileImages] Saved banner locally (\(data.count) bytes)")

        Task { await uploadToCloud(data: data, type: .banner) }
    }

    private func uploadToCloud(data: Data, type: ImageType) async {
        guard let path = remotePath(for: type) else { return }

        print("[ProfileImages] Uploading \(type) to: \(storageBucket)/\(path) (\(data.count) bytes)")

        do {
            try await supabase.client.storage
                .from(storageBucket)
                .upload(
                    path: path,
                    file: data,
                    options: .init(contentType: "image/jpeg", upsert: true)
                )
            print("[ProfileImages] Upload SUCCESS for \(type)")
        } catch {
            print("[ProfileImages] Upload FAILED for \(type): \(error)")
        }
    }

    // MARK: - Remove

    func removeProfileImage() {
        try? fileManager.removeItem(at: profileImageURL)
        profileImage = nil
        Task { await deleteFromCloud(type: .avatar) }
    }

    func removeBannerImage() {
        try? fileManager.removeItem(at: bannerImageURL)
        bannerImage = nil
        Task { await deleteFromCloud(type: .banner) }
    }

    private func deleteFromCloud(type: ImageType) async {
        guard let path = remotePath(for: type) else { return }

        do {
            try await supabase.client.storage
                .from(storageBucket)
                .remove(paths: [path])
            print("[ProfileImages] Deleted \(type) from cloud")
        } catch {
            print("[ProfileImages] Cloud delete failed for \(type): \(error)")
        }
    }
}
