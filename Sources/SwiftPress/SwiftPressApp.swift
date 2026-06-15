import SwiftUI

@main
struct SwiftPressApp: App {
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

        Window("关于 SwiftPress", id: "about") {
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
        Button("关于 SwiftPress") {
            openWindow(id: "about")
        }
    }
}
