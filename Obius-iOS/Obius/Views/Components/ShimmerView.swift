import SwiftUI

/// A frosted glass shimmer effect for locked sections
struct ShimmerView: View {
    let isAnimating: Bool
    
    @State private var phase: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Frosted glass background
            Rectangle()
                .fill(.ultraThinMaterial)
            
            // Shimmer gradient overlay
            if isAnimating {
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.3),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(Rectangle())
            }
            
            // Lock icon
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
                Text("Locked")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .opacity(0.8)
        }
        .onAppear {
            if isAnimating {
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true)
                ) {
                    phase = 100
                }
            }
        }
    }
}

/// A frosted glass overlay that hides locked content
struct FrostedGlassOverlay: View {
    @StateObject private var biometricManager = BiometricManager.shared
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        ZStack {
            // Strong frosted glass effect
            #if os(iOS)
            VisualEffectBlur(blurStyle: .systemUltraThinMaterial)
            #else
            VisualEffectBlur(blurStyle: NSVisualEffectView.Material.hudWindow)
            #endif

            // Additional frosted tint
            Color.white.opacity(0.1)

            // Subtle animated shimmer
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.15),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 100)
            .offset(x: shimmerOffset)
            .blur(radius: 10)

            // Lock indicator - shows correct biometric type
            VStack(spacing: 8) {
                Image(systemName: biometricManager.biometricIcon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Tap to unlock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: false)
            ) {
                shimmerOffset = 200
            }
        }
    }
}

/// Legacy alias for compatibility
typealias PulsingShimmerOverlay = FrostedGlassOverlay

/// UIKit visual effect blur wrapper for SwiftUI
#if os(iOS)
import UIKit

struct VisualEffectBlur: UIViewRepresentable {
    let blurStyle: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}
#else
import AppKit

struct VisualEffectBlur: NSViewRepresentable {
    let blurStyle: NSVisualEffectView.Material
    
    init(blurStyle: Any) {
        // Map iOS blur styles to macOS materials
        self.blurStyle = .hudWindow
    }
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = blurStyle
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = blurStyle
    }
}
#endif

/// Modifier to apply frosted glass effect conditionally
struct ShimmerModifier: ViewModifier {
    let isLocked: Bool
    let isAuthenticated: Bool
    let onTap: () -> Void

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: isLocked && !isAuthenticated ? 12 : 0)
                .opacity(isLocked && !isAuthenticated ? 0.3 : 1.0)

            if isLocked && !isAuthenticated {
                FrostedGlassOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        onTap()
                    }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isAuthenticated)
    }
}

extension View {
    /// Apply a shimmer lock effect to the view
    func shimmerLocked(
        isLocked: Bool,
        isAuthenticated: Bool,
        onUnlock: @escaping () -> Void
    ) -> some View {
        modifier(ShimmerModifier(
            isLocked: isLocked,
            isAuthenticated: isAuthenticated,
            onTap: onUnlock
        ))
    }
}

#Preview {
    VStack(spacing: 20) {
        // Shimmer view standalone
        ShimmerView(isAnimating: true)
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        
        // Pulsing shimmer overlay
        Text("This content is hidden behind the shimmer")
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shimmerLocked(isLocked: true, isAuthenticated: false) {
                print("Unlock tapped")
            }
        
        // Unlocked state
        Text("This content is visible")
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shimmerLocked(isLocked: true, isAuthenticated: true) {
                print("Unlock tapped")
            }
    }
    .padding()
}
