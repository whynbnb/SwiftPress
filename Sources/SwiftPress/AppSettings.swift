import SwiftUI

/// DMG 打开时的 Finder 窗口尺寸预设。
enum DMGWindowPreset: String, CaseIterable, Codable {
    case small
    case medium
    case large
    case extraLarge
    case custom
    case unset

    /// 固定尺寸预设；`nil` 表示自定义或不设置。
    var fixedSize: (width: Int, height: Int)? {
        switch self {
        case .custom, .unset: return nil
        case .small: return (480, 320)
        case .medium: return (640, 400)
        case .large: return (800, 500)
        case .extraLarge: return (1000, 620)
        }
    }
}

/// DMG 打开时的图标大小预设。
enum DMGIconPreset: String, CaseIterable, Codable {
    case small
    case medium
    case large
    case extraLarge
    case custom
    case unset

    var fixedSize: Int? {
        switch self {
        case .small: return 64
        case .medium: return 96
        case .large: return 128
        case .extraLarge: return 160
        case .custom, .unset: return nil
        }
    }
}

extension DMGWindowPreset {
    var title: String {
        switch self {
        case .small: return L10n.tr("settings.dmgWindow.small")
        case .medium: return L10n.tr("settings.dmgWindow.medium")
        case .large: return L10n.tr("settings.dmgWindow.large")
        case .extraLarge: return L10n.tr("settings.dmgWindow.extraLarge")
        case .custom: return L10n.tr("settings.dmgWindow.custom")
        case .unset: return L10n.tr("settings.dmgWindow.unset")
        }
    }
}

extension DMGIconPreset {
    var title: String {
        switch self {
        case .small: return L10n.tr("settings.dmgIcon.small")
        case .medium: return L10n.tr("settings.dmgIcon.medium")
        case .large: return L10n.tr("settings.dmgIcon.large")
        case .extraLarge: return L10n.tr("settings.dmgIcon.extraLarge")
        case .custom: return L10n.tr("settings.dmgIcon.custom")
        case .unset: return L10n.tr("settings.dmgIcon.unset")
        }
    }
}

/// GUI 与 CLI 共用的 DMG 窗口尺寸读取。只读写 `UserDefaults`，可在任意线程访问。
enum DMGWindowPreferences {
    static let presetKey = "dmg_window_preset"
    static let widthKey = "dmg_window_width"
    static let heightKey = "dmg_window_height"

    static let defaultWidth = 640
    static let defaultHeight = 400
    static let widthRange = 320...1600
    static let heightRange = 240...1200

    static var preset: DMGWindowPreset {
        DMGWindowPreset(rawValue: UserDefaults.standard.string(forKey: presetKey) ?? "") ?? .medium
    }

    /// 当前生效尺寸；`nil` 表示不设置，沿用 Finder 默认。
    static var currentSize: (width: Int, height: Int)? {
        if preset == .unset {
            return nil
        }
        if let size = preset.fixedSize {
            return size
        }
        let defaults = UserDefaults.standard
        let storedWidth = defaults.integer(forKey: widthKey)
        let storedHeight = defaults.integer(forKey: heightKey)
        let width = storedWidth == 0 ? defaultWidth : storedWidth
        let height = storedHeight == 0 ? defaultHeight : storedHeight
        return (clamp(width, to: widthRange), clamp(height, to: heightRange))
    }

    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// GUI 与 CLI 共用的 DMG 图标大小读取。
enum DMGIconPreferences {
    static let presetKey = "dmg_icon_preset"
    static let sizeKey = "dmg_icon_size"

    static let defaultSize = 96
    static let unsetFallbackSize = 48
    static let sizeRange = 32...256

    static var preset: DMGIconPreset {
        DMGIconPreset(rawValue: UserDefaults.standard.string(forKey: presetKey) ?? "") ?? .medium
    }

    /// 当前生效大小；`nil` 表示不设置，沿用 Finder 默认。
    static var currentSize: Int? {
        if preset == .unset {
            return nil
        }
        if let fixed = preset.fixedSize {
            return fixed
        }
        let stored = UserDefaults.standard.integer(forKey: sizeKey)
        let size = stored == 0 ? defaultSize : stored
        return DMGWindowPreferences.clamp(size, to: sizeRange)
    }
}

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

    @Published var dmgWindowPreset: DMGWindowPreset {
        didSet { UserDefaults.standard.set(dmgWindowPreset.rawValue, forKey: DMGWindowPreferences.presetKey) }
    }

    @Published var dmgWindowWidth: Int {
        didSet { UserDefaults.standard.set(dmgWindowWidth, forKey: DMGWindowPreferences.widthKey) }
    }

    @Published var dmgWindowHeight: Int {
        didSet { UserDefaults.standard.set(dmgWindowHeight, forKey: DMGWindowPreferences.heightKey) }
    }

    @Published var dmgIconPreset: DMGIconPreset {
        didSet { UserDefaults.standard.set(dmgIconPreset.rawValue, forKey: DMGIconPreferences.presetKey) }
    }

    @Published var dmgIconSize: Int {
        didSet { UserDefaults.standard.set(dmgIconSize, forKey: DMGIconPreferences.sizeKey) }
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
        self.dmgWindowPreset = DMGWindowPreferences.preset
        let storedWidth = UserDefaults.standard.integer(forKey: DMGWindowPreferences.widthKey)
        let storedHeight = UserDefaults.standard.integer(forKey: DMGWindowPreferences.heightKey)
        self.dmgWindowWidth = DMGWindowPreferences.clamp(
            storedWidth == 0 ? DMGWindowPreferences.defaultWidth : storedWidth,
            to: DMGWindowPreferences.widthRange
        )
        self.dmgWindowHeight = DMGWindowPreferences.clamp(
            storedHeight == 0 ? DMGWindowPreferences.defaultHeight : storedHeight,
            to: DMGWindowPreferences.heightRange
        )
        self.dmgIconPreset = DMGIconPreferences.preset
        let storedIconSize = UserDefaults.standard.integer(forKey: DMGIconPreferences.sizeKey)
        self.dmgIconSize = DMGWindowPreferences.clamp(
            storedIconSize == 0 ? DMGIconPreferences.defaultSize : storedIconSize,
            to: DMGIconPreferences.sizeRange
        )
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
