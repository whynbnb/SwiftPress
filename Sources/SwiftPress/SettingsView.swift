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

            Section {
                if settings.watchPaths.isEmpty {
                    Text(L10n.tr("settings.watchPaths.empty"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ForEach($settings.watchPaths) { $watchPath in
                    WatchPathRow(watchPath: $watchPath) {
                        settings.watchPaths.removeAll { $0.id == watchPath.id }
                    }
                }

                Button {
                    addWatchPaths()
                } label: {
                    Label(L10n.tr("settings.watchPaths.add"), systemImage: "plus")
                }
            } header: {
                Text(L10n.tr("settings.watchPaths.title"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
        .background(WindowTitleSetter(title: L10n.tr("settings.windowTitle")))
        .preferredColorScheme(settings.resolvedColorScheme)
    }

    private func addWatchPaths() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.tr("settings.watchPaths.add")
        if panel.runModal() == .OK {
            for url in panel.urls where !settings.watchPaths.contains(where: { $0.path == url.path }) {
                settings.watchPaths.append(WatchPath(path: url.path))
            }
        }
    }
}

/// 单条监听路径：目录、启用开关、监听内容（扩展名）。
private struct WatchPathRow: View {
    @Binding var watchPath: WatchPath
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text(watchPath.path)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Toggle(isOn: $watchPath.enabled) {
                    Text(L10n.tr("settings.watchPaths.enabled"))
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                Button(action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L10n.tr("settings.watchPaths.remove"))
            }

            HStack(spacing: 8) {
                Text(L10n.tr("settings.watchPaths.content"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(L10n.tr("settings.watchPaths.extensionPlaceholder"), text: $watchPath.fileExtension)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text(L10n.tr("settings.watchPaths.extensionHint"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                Picker(L10n.tr("settings.watchPaths.depth"), selection: $watchPath.depth) {
                    Text(L10n.tr("settings.watchPaths.depth.top")).tag(WatchPath.ScanDepth.top)
                    Text(L10n.tr("settings.watchPaths.depth.oneLevel")).tag(WatchPath.ScanDepth.oneLevel)
                    Text(L10n.tr("settings.watchPaths.depth.recursive")).tag(WatchPath.ScanDepth.recursive)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding(.vertical, 2)
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
