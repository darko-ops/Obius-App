import SwiftUI

#if os(macOS)
import AppKit

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowAccessorView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class WindowAccessorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    override func layout() {
        super.layout()
        configureWindow()
    }

    private func configureWindow() {
        guard let window = self.window else { return }
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarSeparatorStyle = .none
        if let toolbar = window.toolbar {
            toolbar.displayMode = .iconOnly
        }
    }
}

extension View {
    func configureWindowBackground() -> some View {
        self.onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                for window in NSApplication.shared.windows {
                    window.titlebarAppearsTransparent = true
                    window.isOpaque = false
                    window.backgroundColor = .black
                    window.appearance = NSAppearance(named: .darkAqua)
                    window.titlebarSeparatorStyle = .none
                }
            }
        }
    }
}
#else
struct WindowAccessor: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension View {
    func configureWindowBackground() -> some View { self }
}
#endif
