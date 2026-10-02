import SwiftUI

/// 一条监听路径配置：目录、是否启用、监听的文件扩展名（默认 app）、扫描深度。
struct WatchPath: Identifiable, Codable, Equatable {
    /// 扫描深度：不扫描子目录 / 只扫描一层子目录 / 递归所有子目录。
    enum ScanDepth: String, Codable, CaseIterable {
        case top
        case oneLevel
        case recursive

        /// 相对根目录允许的最大层级；nil 表示不限。
        var maxDepth: Int? {
            switch self {
            case .top: return 1
            case .oneLevel: return 2
            case .recursive: return nil
            }
        }
    }

    var id: UUID
    var path: String
    var enabled: Bool
    var fileExtension: String
    var depth: ScanDepth

    init(
        id: UUID = UUID(),
        path: String,
        enabled: Bool = true,
        fileExtension: String = "app",
        depth: ScanDepth = .recursive
    ) {
        self.id = id
        self.path = path
        self.enabled = enabled
        self.fileExtension = fileExtension
        self.depth = depth
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, enabled, fileExtension, depth
    }

    /// 解析失败一律回退默认值。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        path = (try? container.decode(String.self, forKey: .path)) ?? ""
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? true
        fileExtension = (try? container.decode(String.self, forKey: .fileExtension)) ?? "app"
        depth = (try? container.decode(ScanDepth.self, forKey: .depth)) ?? .recursive
    }
}

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let watchPathsKey = "watch_paths"

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

    @Published var watchPaths: [WatchPath] {
        didSet { Self.saveWatchPaths(watchPaths) }
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
        self.watchPaths = Self.loadWatchPaths()
    }

    private static func loadWatchPaths() -> [WatchPath] {
        guard let data = UserDefaults.standard.data(forKey: watchPathsKey),
              let list = try? JSONDecoder().decode([WatchPath].self, from: data) else {
            return []
        }
        return list
    }

    private static func saveWatchPaths(_ list: [WatchPath]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: watchPathsKey)
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
