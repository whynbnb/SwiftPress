import SwiftUI

enum L10n {
    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = localized[key] ?? key
        return String(format: format, arguments: args)
    }

    private static var localized: [String: String] {
        let stored = Preferences.defaults.string(forKey: "app_language") ?? "zh"
        let code: String
        if stored == "system" {
            code = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? "zh" : "en"
        } else {
            code = stored
        }
        return code == "en" ? en : zh
    }

    private static let zh: [String: String] = [
        "app.title": "SwiftPress",
        "app.subtitle": "简易 DMG 安装包制作工具",
        "drop.hint": "拖入 .app 文件",
        "drop.browse": "或点击浏览...",
        "drop.clear": "移除已选应用",
        "output.label": "输出:",
        "output.change": "更改...",
        "btn.create": "制作 DMG",
        "btn.cancel": "取消",
        "btn.settings": "设置",
        "menu.settings": "设置…",
        "panel.chooseApp": "选择 .app 文件",
        "panel.saveDMG": "保存 DMG",
        "status.preparing": "准备中...",
        "status.tempDir": "创建临时目录...",
        "status.copying": "拷贝 .app 文件...",
        "status.symlink": "创建 /Applications 替身...",
        "status.creating": "正在制作 DMG...",
        "status.layout": "设置 DMG 布局...",
        "status.cleaning": "清理临时文件...",
        "status.done": "完成!",
        "status.cancelling": "正在取消...",
        "status.cancelled": "已取消",
        "warning.windowLayout": "未能写入 DMG 窗口/图标布局（布局模板缺失或无效）。",
        "alert.success": "完成",
        "alert.success.msg": "DMG 已创建: %@",
        "alert.showInFinder": "在 Finder 中显示",
        "alert.ok": "好",
        "alert.error": "错误",
        "about.subtitle": "简易 DMG 安装包制作工具",
        "about.title": "关于 SwiftPress",
        "about.license": "开源许可:",
        "about.repo": "源码仓库:",
        "about.copyright": "Copyright © 2026 whynbnb",
        "cli.usage": """
        SwiftPress CLI

        用法:
          SwiftPress --app <path/to/App.app> [--output <path/to/out.dmg>]

        选项:
          --app            待打包的 .app 路径（必填）
          --output, -o     输出 DMG 路径（可选，默认与 app 同目录，按版本+日期命名）
          -h, --help       显示帮助
        """,
        "cli.error.missingApp": "缺少 --app 参数",
        "cli.error.appNotFound": "找不到应用: %@",
        "cli.error.notApp": "不是有效的 .app 包: %@",
        "cli.error.createFailed": "制作失败: %@",
        "cli.success": "✅ 已生成 %@",
        "settings.language": "语言",
        "settings.language.system": "跟随系统",
        "settings.windowTitle": "SwiftPress 设置",
        "settings.watchPaths.title": "监听路径",
        "settings.watchPaths.empty": "尚未添加监听目录",
        "settings.watchPaths.add": "添加目录…",
        "settings.watchPaths.content": "内容",
        "settings.watchPaths.extensionPlaceholder": "app",
        "settings.watchPaths.extensionHint": ".app / .dmg / 留空为全部",
        "settings.watchPaths.depth": "子目录",
        "settings.watchPaths.depth.top": "不扫描子目录",
        "settings.watchPaths.depth.oneLevel": "只扫描一层",
        "settings.watchPaths.depth.recursive": "递归所有",
        "settings.watchPaths.enabled": "监听",
        "settings.watchPaths.remove": "移除",
        "watch.title": "监听",
        "watch.new": "新",
        "watch.notApp": "非 .app",
        "watch.empty": "暂无匹配文件",
        "watch.empty.hint": "在设置中添加监听目录",
        "watch.monitoring": "监听 %d 个目录",
        "watch.events": "事件 %d",
        "watch.empty.monitoring": "正在监听 %d 个目录，暂未发现匹配文件",
        "watch.refresh": "刷新",
        "tab.create": "制作",
        "tab.watched": "监听",
        "settings.appearance": "外观",
        "settings.appearance.system": "跟随系统",
        "settings.appearance.light": "浅色",
        "settings.appearance.dark": "深色",
        "settings.dmgWindow.title": "DMG 窗口大小",
        "settings.dmgWindow.small": "小 480 × 320",
        "settings.dmgWindow.medium": "中 640 × 400",
        "settings.dmgWindow.large": "大 800 × 500",
        "settings.dmgWindow.extraLarge": "超大 1000 × 620",
        "settings.dmgWindow.custom": "自定义",
        "settings.dmgWindow.unset": "不设置",
        "settings.dmgWindow.width": "宽",
        "settings.dmgWindow.height": "高",
        "settings.dmgIcon.title": "图标大小",
        "settings.dmgIcon.small": "小 64",
        "settings.dmgIcon.medium": "中 96",
        "settings.dmgIcon.large": "大 128",
        "settings.dmgIcon.extraLarge": "超大 160",
        "settings.dmgIcon.custom": "自定义",
        "settings.dmgIcon.unset": "不设置",
        "settings.dmgIcon.size": "大小",
        "advanced.title": "高级设置",
        "advanced.reset": "恢复默认",
        "advanced.unset": "不设置（使用系统默认）",
        "advanced.hint": "设置会被记住，并应用到之后制作的 DMG。选择「不设置」则沿用系统默认。",
    ]

    private static let en: [String: String] = [
        "app.title": "SwiftPress",
        "app.subtitle": "Simple DMG Installer Maker",
        "drop.hint": "Drop .app file here",
        "drop.browse": "or click to browse...",
        "drop.clear": "Remove selected app",
        "output.label": "Output:",
        "output.change": "Change...",
        "btn.create": "Create DMG",
        "btn.cancel": "Cancel",
        "btn.settings": "Settings",
        "menu.settings": "Settings…",
        "panel.chooseApp": "Choose .app File",
        "panel.saveDMG": "Save DMG",
        "status.preparing": "Preparing...",
        "status.tempDir": "Creating temp directory...",
        "status.copying": "Copying .app file...",
        "status.symlink": "Creating /Applications symlink...",
        "status.creating": "Creating DMG...",
        "status.layout": "Configuring DMG layout...",
        "status.cleaning": "Cleaning up...",
        "status.done": "Done!",
        "status.cancelling": "Cancelling...",
        "status.cancelled": "Cancelled",
        "warning.windowLayout": "Couldn't write the DMG window/icon layout (layout template missing or invalid).",
        "alert.success": "Success",
        "alert.success.msg": "DMG created: %@",
        "alert.showInFinder": "Show in Finder",
        "alert.ok": "OK",
        "alert.error": "Error",
        "about.subtitle": "Simple DMG Installer Maker",
        "about.title": "About SwiftPress",
        "about.license": "License:",
        "about.repo": "Repository:",
        "about.copyright": "Copyright © 2026 whynbnb",
        "cli.usage": """
        SwiftPress CLI

        Usage:
          SwiftPress --app <path/to/App.app> [--output <path/to/out.dmg>]

        Options:
          --app            Path to the .app to package (required)
          --output, -o     Output DMG path (optional; defaults next to the app, named by version + date)
          -h, --help       Show this help
        """,
        "cli.error.missingApp": "Missing --app argument",
        "cli.error.appNotFound": "App not found: %@",
        "cli.error.notApp": "Not a valid .app bundle: %@",
        "cli.error.createFailed": "Creation failed: %@",
        "cli.success": "✅ Created %@",
        "settings.language": "Language",
        "settings.language.system": "System",
        "settings.windowTitle": "SwiftPress Settings",
        "settings.watchPaths.title": "Watched Folders",
        "settings.watchPaths.empty": "No watched folders yet",
        "settings.watchPaths.add": "Add Folder…",
        "settings.watchPaths.content": "Content",
        "settings.watchPaths.extensionPlaceholder": "app",
        "settings.watchPaths.extensionHint": ".app / .dmg / blank = all",
        "settings.watchPaths.depth": "Subfolders",
        "settings.watchPaths.depth.top": "None",
        "settings.watchPaths.depth.oneLevel": "One level",
        "settings.watchPaths.depth.recursive": "Recursive",
        "settings.watchPaths.enabled": "Watch",
        "settings.watchPaths.remove": "Remove",
        "watch.title": "Watch",
        "watch.new": "NEW",
        "watch.notApp": "Not .app",
        "watch.empty": "No matching files",
        "watch.empty.hint": "Add watched folders in Settings",
        "watch.monitoring": "Monitoring %d folders",
        "watch.events": "%d events",
        "watch.empty.monitoring": "Monitoring %d folders, no matches yet",
        "watch.refresh": "Refresh",
        "tab.create": "Create",
        "tab.watched": "Watch",
        "settings.appearance": "Appearance",
        "settings.appearance.system": "System",
        "settings.appearance.light": "Light",
        "settings.appearance.dark": "Dark",
        "settings.dmgWindow.title": "DMG Window Size",
        "settings.dmgWindow.small": "Small 480 × 320",
        "settings.dmgWindow.medium": "Medium 640 × 400",
        "settings.dmgWindow.large": "Large 800 × 500",
        "settings.dmgWindow.extraLarge": "Extra Large 1000 × 620",
        "settings.dmgWindow.custom": "Custom",
        "settings.dmgWindow.unset": "No setting",
        "settings.dmgWindow.width": "Width",
        "settings.dmgWindow.height": "Height",
        "settings.dmgIcon.title": "Icon Size",
        "settings.dmgIcon.small": "Small 64",
        "settings.dmgIcon.medium": "Medium 96",
        "settings.dmgIcon.large": "Large 128",
        "settings.dmgIcon.extraLarge": "Extra Large 160",
        "settings.dmgIcon.custom": "Custom",
        "settings.dmgIcon.unset": "No setting",
        "settings.dmgIcon.size": "Size",
        "advanced.title": "Advanced Settings",
        "advanced.reset": "Reset to Default",
        "advanced.unset": "No setting (use system default)",
        "advanced.hint": "Remembered and applied to subsequent DMGs. Choose “No setting” to use the system default.",
    ]
}
