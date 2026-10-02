import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker(L10n.tr("settings.language"), selection: $settings.language) {
                    Text(L10n.tr("settings.language.system")).tag(AppSettings.Language.system)
                    Text("中文").tag(AppSettings.Language.zh)
                    Text("English").tag(AppSettings.Language.en)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker(L10n.tr("settings.appearance"), selection: $settings.appearance) {
                    Text(L10n.tr("settings.appearance.system")).tag(AppSettings.Appearance.system)
                    Text(L10n.tr("settings.appearance.light")).tag(AppSettings.Appearance.light)
                    Text(L10n.tr("settings.appearance.dark")).tag(AppSettings.Appearance.dark)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 180)
        .background(WindowTitleSetter(title: L10n.tr("settings.windowTitle")))
        .preferredColorScheme(settings.resolvedColorScheme)
    }
}

/// 直接把宿主窗口的标题设为指定文本，用于本地化 `Settings` 场景的窗口标题。
private struct WindowTitleSetter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.title = title }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.title = title }
    }
}
