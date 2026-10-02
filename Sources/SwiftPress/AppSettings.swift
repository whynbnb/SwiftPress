import SwiftUI

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Language: String, CaseIterable {
        case system = "system"
        case zh = "zh"
        case en = "en"
    }

    enum Appearance: String, CaseIterable {
        case system = "system"
        case light = "light"
        case dark = "dark"
    }

    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "app_language") }
    }

    @Published var appearance: Appearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "app_appearance")
            applyAppearance()
        }
    }

    var resolvedColorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var currentLanguage: Language { language }

    init() {
        let savedLang = UserDefaults.standard.string(forKey: "app_language") ?? "zh"
        let savedAppearance = UserDefaults.standard.string(forKey: "app_appearance") ?? "system"
        self.language = Language(rawValue: savedLang) ?? .zh
        self.appearance = Appearance(rawValue: savedAppearance) ?? .system
    }

    private func applyAppearance() {
        switch appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func applyOnLaunch() {
        applyAppearance()
    }
}
