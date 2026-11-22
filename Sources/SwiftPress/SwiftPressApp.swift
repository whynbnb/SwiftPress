import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mouseMonitor: Any?

    // 关闭最后一个窗口后直接退出，不在 Dock 中残留
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // 启动即扫描一次，确保已有文件立刻出现在监听列表中
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyOnLaunch()
        WatchManager.shared.sync(with: AppSettings.shared.watchPaths)
        // 鼠标按下时立即激活 App 并使窗口成为 key，避免"第一下点击只用于激活、第二下才生效"
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            MainActor.assumeIsolated {
                if !NSApp.isActive {
                    NSApp.activate(ignoringOtherApps: true)
                }
                if let window = event.window, !window.isKeyWindow {
                    window.makeKey()
                }
            }
            return event
        }
    }

    // 退出时确保结束正在运行的 hdiutil 子进程，避免后台残留
    func applicationWillTerminate(_ notification: Notification) {
        ChildProcessRegistry.shared.terminate()
    }
}

@main
enum SwiftPressMain {
    static func main() {
        // 命令行模式：执行打包并退出，不启动 GUI
        CommandLineSupport.runIfNeeded()
        SwiftPressApp.main()
    }
}

struct SwiftPressApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = AppSettings.shared

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    DispatchQueue.main.async {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 560, height: 600)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutButton()
            }
            CommandGroup(replacing: .appSettings) {
                SettingsMenuButton()
            }
        }

        Window(L10n.tr("about.title"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)

        Window(L10n.tr("settings.windowTitle"), id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }
}

struct AboutButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.tr("about.title")) {
            openWindow(id: "about")
        }
    }
}

/// 自定义「设置…」菜单项，避免 SettingsLink 与系统默认项同时出现。
struct SettingsMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.tr("menu.settings")) {
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
