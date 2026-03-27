import SwiftUI

// MARK: - Cross-Platform Image Helper

/// Creates a SwiftUI Image from a PlatformImage (UIImage on iOS, NSImage on macOS)
func platformImage(_ image: PlatformImage) -> Image {
    #if os(iOS)
    Image(uiImage: image)
    #else
    Image(nsImage: image)
    #endif
}

extension View {
    /// Cross-platform inline navigation title display mode.
    /// On iOS uses .inline, on macOS this is a no-op.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Cross-platform full screen cover that falls back to .sheet on macOS.
    @ViewBuilder
    func platformFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(item: item, content: content)
        #else
        self.sheet(item: item, content: content)
        #endif
    }

    /// Cross-platform full screen cover (Bool version) that falls back to .sheet on macOS.
    @ViewBuilder
    func platformFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// Cross-platform list style — insetGrouped on iOS, inset on macOS.
    @ViewBuilder
    func platformGroupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    /// Apply navigation bar toolbar background on iOS; on macOS the window-level
    /// WindowAccessor handles the titlebar appearance globally.
    @ViewBuilder
    func platformToolbarBackground(_ color: Color) -> some View {
        #if os(iOS)
        self.toolbarBackground(color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }
}
