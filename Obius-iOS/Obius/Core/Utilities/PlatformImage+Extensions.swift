import Foundation

#if os(macOS)
import AppKit

extension NSImage {
    /// Match UIImage.jpegData(compressionQuality:)
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffData = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    /// Match UIImage.pngData()
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Match UIImage(systemName:)
    convenience init?(systemName: String) {
        self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }

    /// Match UIImage.withRenderingMode(.alwaysTemplate)
    func withRenderingMode(_ mode: Any) -> NSImage {
        let img = self.copy() as! NSImage
        img.isTemplate = true
        return img
    }

    /// Match UIImage.cgImage
    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Match UIImage.scale
    var scale: CGFloat { 1.0 }
}
#endif
