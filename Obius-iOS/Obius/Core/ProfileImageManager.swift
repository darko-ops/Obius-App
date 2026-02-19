import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Manages local storage of profile and banner images
@MainActor
final class ProfileImageManager: ObservableObject {
    static let shared = ProfileImageManager()

    private let fileManager = FileManager.default
    private let profileDirectory: URL

    @Published var profileImage: UIImage?
    @Published var bannerImage: UIImage?

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        profileDirectory = documents.appendingPathComponent("profile", isDirectory: true)
        try? fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        loadImages()
    }

    // MARK: - File Paths

    private var profileImageURL: URL {
        profileDirectory.appendingPathComponent("avatar.jpg")
    }

    private var bannerImageURL: URL {
        profileDirectory.appendingPathComponent("banner.jpg")
    }

    // MARK: - Load

    private func loadImages() {
        #if os(iOS)
        if let data = try? Data(contentsOf: profileImageURL),
           let image = UIImage(data: data) {
            profileImage = image
        }
        if let data = try? Data(contentsOf: bannerImageURL),
           let image = UIImage(data: data) {
            bannerImage = image
        }
        #endif
    }

    // MARK: - Save

    #if os(iOS)
    func saveProfileImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: profileImageURL)
        profileImage = image
    }

    func saveBannerImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: bannerImageURL)
        bannerImage = image
    }
    #endif

    // MARK: - Remove

    func removeProfileImage() {
        try? fileManager.removeItem(at: profileImageURL)
        profileImage = nil
    }

    func removeBannerImage() {
        try? fileManager.removeItem(at: bannerImageURL)
        bannerImage = nil
    }
}
