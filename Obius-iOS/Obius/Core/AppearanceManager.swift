import SwiftUI

/// Manages app-wide appearance (light/dark mode)
@MainActor
final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    private let key = "obius_appearance_mode"

    enum AppearanceMode: String, CaseIterable {
        case light = "Light"
        case dark = "Dark"

        var colorScheme: ColorScheme? {
            switch self {
            case .light: return .light
            case .dark: return .dark
            }
        }

        var icon: String {
            switch self {
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            }
        }
    }

    @Published var currentMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(currentMode.rawValue, forKey: key)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: key) ?? AppearanceMode.dark.rawValue
        currentMode = AppearanceMode(rawValue: stored) ?? .dark
    }
}
