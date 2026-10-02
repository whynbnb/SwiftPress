import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    // 关闭最后一个窗口后直接退出，不在 Dock 中残留
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // 退出时确保结束正在运行的 hdiutil 子进程，避免后台残留
    func applicationWillTerminate(_ notification: Notification) {
        ChildProcessRegistry.shared.terminate()
    }
}

@main
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
        .defaultSize(width: 520, height: 400)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutButton()
            }
        }

        Window(L10n.tr("about.title"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
        }
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
