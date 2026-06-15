import SwiftUI

enum L10n {
    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = localized[key] ?? key
        return String(format: format, arguments: args)
    }

    private static var localized: [String: String] {
        let lang = UserDefaults.standard.string(forKey: "app_language") ?? "zh"
        return lang == "en" ? en : zh
    }

    private static let zh: [String: String] = [
        "app.title": "SwiftPress",
        "app.subtitle": "简易 DMG 安装包制作工具",
        "drop.hint": "拖入 .app 文件",
        "drop.browse": "或点击浏览...",
        "output.label": "输出:",
        "output.change": "更改...",
        "btn.create": "制作 DMG",
        "panel.chooseApp": "选择 .app 文件",
        "panel.saveDMG": "保存 DMG",
        "status.preparing": "准备中...",
        "status.tempDir": "创建临时目录...",
        "status.copying": "拷贝 .app 文件...",
        "status.symlink": "创建 /Applications 替身...",
        "status.creating": "正在制作 DMG...",
        "status.cleaning": "清理临时文件...",
        "status.done": "完成!",
        "alert.success": "完成",
        "alert.success.msg": "DMG 已创建: %@",
        "alert.showInFinder": "在 Finder 中显示",
        "alert.ok": "好",
        "alert.error": "错误",
        "about.subtitle": "简易 DMG 安装包制作工具",
        "about.license": "开源许可:",
        "about.repo": "源码仓库:",
        "about.copyright": "Copyright © 2026 WHYBBE",
        "settings.language": "语言",
        "settings.appearance": "外观",
        "settings.appearance.system": "跟随系统",
        "settings.appearance.light": "浅色",
        "settings.appearance.dark": "深色",
    ]

    private static let en: [String: String] = [
        "app.title": "SwiftPress",
        "app.subtitle": "Simple DMG Installer Maker",
        "drop.hint": "Drop .app file here",
        "drop.browse": "or click to browse...",
        "output.label": "Output:",
        "output.change": "Change...",
        "btn.create": "Create DMG",
        "panel.chooseApp": "Choose .app File",
        "panel.saveDMG": "Save DMG",
        "status.preparing": "Preparing...",
        "status.tempDir": "Creating temp directory...",
        "status.copying": "Copying .app file...",
        "status.symlink": "Creating /Applications symlink...",
        "status.creating": "Creating DMG...",
        "status.cleaning": "Cleaning up...",
        "status.done": "Done!",
        "alert.success": "Success",
        "alert.success.msg": "DMG created: %@",
        "alert.showInFinder": "Show in Finder",
        "alert.ok": "OK",
        "alert.error": "Error",
        "about.subtitle": "Simple DMG Installer Maker",
        "about.license": "License:",
        "about.repo": "Repository:",
        "about.copyright": "Copyright © 2026 WHYBBE",
        "settings.language": "Language",
        "settings.appearance": "Appearance",
        "settings.appearance.system": "System",
        "settings.appearance.light": "Light",
        "settings.appearance.dark": "Dark",
    ]
}
