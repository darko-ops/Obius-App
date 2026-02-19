import SwiftUI

/// Manages app-wide appearance (light/dark mode)
@MainActor
final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    private let key = "obius_appearance_mode"

    enum AppearanceMode: String, CaseIterable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }

        var icon: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
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
        let stored = UserDefaults.standard.string(forKey: key) ?? AppearanceMode.system.rawValue
        currentMode = AppearanceMode(rawValue: stored) ?? .system
    }
}
