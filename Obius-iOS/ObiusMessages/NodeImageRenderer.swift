import SwiftUI
import UIKit

/// Renders a NodeCardView to a UIImage using SwiftUI's ImageRenderer (iOS 16+).
/// Falls back to the Core Graphics-based MessageCardRenderer on older iOS versions.
@available(iOS 16.0, *)
enum NodeImageRenderer {

    /// Renders a 300x200pt @2x card image from a MessageSharePayload.
    @MainActor static func renderCard(from payload: MessageSharePayload) -> UIImage {
        let view = NodeCardView(payload: payload)
            .frame(width: 300, height: 200)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        if let image = renderer.uiImage {
            return image
        }

        print("[NodeImageRenderer] ImageRenderer returned nil, falling back to CoreGraphics")
        // Fallback to Core Graphics renderer if ImageRenderer fails
        return MessageCardRenderer.renderCard(from: payload)
    }
}
