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
    private let profileDirectory: URL
    private let supabase = SupabaseManager.shared
    private let storageBucket = "profile-images"

    @Published var profileImage: PlatformImage?
    @Published var bannerImage: PlatformImage?

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        profileDirectory = documents.appendingPathComponent("profile", isDirectory: true)
        try? fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        loadLocalImages()
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

        await downloadAndSave(type: .avatar)
        await downloadAndSave(type: .banner)
    }

    private func downloadAndSave(type: ImageType) async {
        guard let path = remotePath(for: type) else { return }

        print("[ProfileImages] Downloading \(type) from: \(storageBucket)/\(path)")

        do {
            let data = try await supabase.client.storage
                .from(storageBucket)
                .download(path: path)

            print("[ProfileImages] Downloaded \(type): \(data.count) bytes")

            guard let image = PlatformImage(data: data) else {
                print("[ProfileImages] Failed to create image from downloaded \(type) data")
                return
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
        } catch {
            print("[ProfileImages] Cloud download FAILED for \(type): \(error)")
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
