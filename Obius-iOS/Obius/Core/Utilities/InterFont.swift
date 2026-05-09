import SwiftUI
import CoreText
#if os(iOS)
import UIKit
#endif

// MARK: - Inter Font Extension

extension Font {
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .light, .ultraLight, .thin:
            return .custom("Inter-Light", size: size)
        case .medium:
            return .custom("Inter-Medium", size: size)
        case .semibold:
            return .custom("Inter-SemiBold", size: size)
        case .bold, .heavy, .black:
            return .custom("Inter-Bold", size: size)
        default:
            return .custom("Inter-Regular", size: size)
        }
    }
}

// MARK: - Global Font Registration

enum InterFontRegistration {
    /// Overrides the default font appearance with Inter so that
    /// SwiftUI text styles (`.body`, `.headline`, etc.) use Inter.
    static func registerAsDefault() {
        #if os(iOS)
        let fontDescriptors: [(String, UIFont.Weight)] = [
            ("Inter-Regular", .regular),
            ("Inter-Medium", .medium),
            ("Inter-SemiBold", .semibold),
            ("Inter-Bold", .bold),
            ("Inter-Light", .light),
        ]

        // Verify fonts are loaded
        for (name, _) in fontDescriptors {
            if UIFont(name: name, size: 12) == nil {
                print("[InterFont] Warning: '\(name)' not found. Check Info.plist UIAppFonts.")
            }
        }

        #if DEBUG
        // Verify Lexend Exa is registered too — used for the welcome / auth headlines.
        let lexendName = "LexendExa-SemiBold"
        if UIFont(name: lexendName, size: 12) == nil {
            print("[Fonts] '\(lexendName)' NOT registered — falling back to system. Delete the app + clean build.")
            // List anything Lexend-ish that IS available, in case the PostScript name is different
            let lexendish = UIFont.familyNames
                .filter { $0.lowercased().contains("lexend") }
                .flatMap { UIFont.fontNames(forFamilyName: $0) }
            if !lexendish.isEmpty {
                print("[Fonts] But these Lexend variants ARE registered: \(lexendish)")
            }
        } else {
            print("[Fonts] '\(lexendName)' registered ✓")
        }
        #endif

        // Override UILabel default font via appearance
        let labelAppearance = UILabel.appearance()
        labelAppearance.font = UIFont(name: "Inter-Regular", size: UIFont.labelFontSize)

        // Override UITextField
        let textFieldAppearance = UITextField.appearance()
        textFieldAppearance.defaultTextAttributes[.font] = UIFont(name: "Inter-Regular", size: UIFont.labelFontSize)

        // Override UITextView
        UITextView.appearance().font = UIFont(name: "Inter-Regular", size: UIFont.labelFontSize)

        // Override navigation bar titles
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithDefaultBackground()
        navBarAppearance.shadowColor = .clear
        if let semibold = UIFont(name: "Inter-SemiBold", size: 17) {
            navBarAppearance.titleTextAttributes = [.font: semibold]
        }
        if let bold = UIFont(name: "Inter-Bold", size: 34) {
            navBarAppearance.largeTitleTextAttributes = [.font: bold]
        }
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        #elseif os(macOS)
        // On macOS, register fonts via CTFontManager. SwiftUI .custom() handles the rest.
        let fontNames = ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold", "Inter-Light"]
        for name in fontNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        #endif
    }
}
