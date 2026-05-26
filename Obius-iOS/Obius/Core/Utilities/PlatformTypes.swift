import SwiftUI

#if os(iOS)
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#elseif os(macOS)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
#endif

// MARK: - Cross-Platform System Colors

extension Color {
    /// Background color that adapts to platform (systemBackground on iOS, black on macOS to match iOS dark style)
    static var systemBackground: Color {
        #if os(iOS)
        Color(UIColor.systemBackground)
        #else
        Color.black
        #endif
    }

    /// Secondary system background
    static var secondarySystemBackground: Color {
        #if os(iOS)
        Color(UIColor.secondarySystemBackground)
        #else
        Color(red: 0.11, green: 0.11, blue: 0.12) // matches iOS dark secondarySystemBackground
        #endif
    }

    /// Tertiary system grouped background
    static var tertiarySystemGroupedBackground: Color {
        #if os(iOS)
        Color(UIColor.tertiarySystemGroupedBackground)
        #else
        Color(red: 0.17, green: 0.17, blue: 0.18) // matches iOS dark tertiarySystemGroupedBackground
        #endif
    }

    /// System gray
    static var platformSystemGray: Color {
        #if os(iOS)
        Color(UIColor.systemGray)
        #else
        Color(red: 0.56, green: 0.56, blue: 0.58) // matches iOS systemGray
        #endif
    }

    /// System gray4
    static var systemGray4: Color {
        #if os(iOS)
        Color(UIColor.systemGray4)
        #else
        Color(red: 0.27, green: 0.27, blue: 0.29) // matches iOS dark systemGray4
        #endif
    }

    /// System gray5
    static var systemGray5: Color {
        #if os(iOS)
        Color(UIColor.systemGray5)
        #else
        Color(red: 0.17, green: 0.17, blue: 0.18) // matches iOS dark systemGray5
        #endif
    }

    /// System gray6
    static var systemGray6: Color {
        #if os(iOS)
        Color(UIColor.systemGray6)
        #else
        Color(red: 0.11, green: 0.11, blue: 0.12) // matches iOS dark systemGray6
        #endif
    }

    /// Label color
    static var platformLabel: Color {
        #if os(iOS)
        Color(UIColor.label)
        #else
        Color(nsColor: .labelColor)
        #endif
    }
}
