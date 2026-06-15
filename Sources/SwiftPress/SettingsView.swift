import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker(L10n.tr("settings.language"), selection: $settings.language) {
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
        .frame(width: 360, height: 160)
        .preferredColorScheme(settings.resolvedColorScheme)
    }
}
