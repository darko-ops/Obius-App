import SwiftUI

#if os(iOS)
import PhotosUI

/// A UIViewControllerRepresentable wrapping PHPickerViewController for multi-image selection.
/// Supports pre-selecting assets that are already in the node.
struct ImagePickerView: UIViewControllerRepresentable {
    let preselectedAssetIdentifiers: [String]
    let onImagesPicked: ([(UIImage, String?)]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 0 // Unlimited selection
        config.selection = .ordered
        config.preferredAssetRepresentationMode = .current
        config.preselectedAssetIdentifiers = preselectedAssetIdentifiers

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePickerView

        init(_ parent: ImagePickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.dismiss()
                return
            }

            let lock = NSLock()
            // Pre-size array to preserve picker selection order despite async loading
            var loadedResults: [(UIImage, String?)?] = Array(repeating: nil, count: results.count)
            let group = DispatchGroup()

            for (index, result) in results.enumerated() {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                let assetId = result.assetIdentifier

                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { group.leave() }
                    if let image = object as? UIImage {
                        lock.lock()
                        loadedResults[index] = (image, assetId)
                        lock.unlock()
                    }
                }
            }

            group.notify(queue: .main) { [weak self] in
                self?.parent.onImagesPicked(loadedResults.compactMap { $0 })
                self?.parent.dismiss()
            }
        }
    }
}

#elseif os(macOS)
import AppKit
import UniformTypeIdentifiers

/// macOS image picker using NSOpenPanel for multi-image selection.
/// Not used as a SwiftUI view — call `MacImagePicker.pick()` directly instead.
struct ImagePickerView: View {
    let preselectedAssetIdentifiers: [String]  // Not used on macOS
    let onImagesPicked: ([(NSImage, String?)]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                let images = MacImagePicker.pick()
                if !images.isEmpty {
                    onImagesPicked(images)
                }
                dismiss()
            }
    }
}

/// Standalone macOS image picker that runs an NSOpenPanel synchronously.
enum MacImagePicker {
    @MainActor
    static func pick() -> [(NSImage, String?)] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .heic, .heif, .tiff, .bmp]
        panel.message = "Select images to add"
        panel.prompt = "Add"

        guard panel.runModal() == .OK else { return [] }

        return panel.urls.compactMap { url in
            guard let image = NSImage(contentsOf: url) else { return nil }
            return (image, url.lastPathComponent)
        }
    }
}
#endif
