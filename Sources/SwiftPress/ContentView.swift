import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DMGViewModel()
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var watchManager = WatchManager.shared

    private enum Tab: Hashable {
        case create
        case watched
    }

    @State private var selectedTab: Tab = .create
    /// 高级设置的展开状态，默认折叠并持久化。
    @AppStorage("advanced_settings_expanded") private var advancedExpanded = false

    var body: some View {
        Group {
            switch selectedTab {
            case .create:
                createTab
            case .watched:
                watchedTab
            }
        }
        .frame(minWidth: 500, minHeight: 440)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    Text(L10n.tr("tab.create")).tag(Tab.create)
                    Text(L10n.tr("tab.watched")).tag(Tab.watched)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                // 语言切换后文字长度变化，强制重建以重新布局，避免选中指示块错位/文字被裁
                .id(settings.language)
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsButton()
            }
        }
        .background(WindowDragConfigurator())
        .preferredColorScheme(settings.resolvedColorScheme)
        .onAppear {
            watchManager.sync(with: settings.watchPaths)
        }
        .onChange(of: settings.watchPaths) { _, newValue in
            watchManager.sync(with: newValue)
        }
        .alert(L10n.tr("alert.success"), isPresented: $viewModel.showSuccess) {
            Button(L10n.tr("alert.showInFinder")) {
                if let url = viewModel.outputURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button(L10n.tr("alert.ok")) {}
        } message: {
            Text(L10n.tr("alert.success.msg", viewModel.outputURL?.lastPathComponent ?? "")
                + (viewModel.warningMessage.map { "\n\n" + $0 } ?? ""))
        }
        .alert(L10n.tr("alert.error"), isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button(L10n.tr("alert.ok")) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - 制作（默认功能）

    private var createTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(L10n.tr("app.title"))
                    .font(.title)
                    .fontWeight(.bold)

                Text(L10n.tr("app.subtitle"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 12) {
                    if let appURL = viewModel.appURL {
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                .resizable()
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading) {
                                Text(appURL.deletingPathExtension().lastPathComponent)
                                    .font(.headline)
                                Text(appURL.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                viewModel.clearApp()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text(L10n.tr("drop.hint"))
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Button(L10n.tr("drop.browse")) {
                                viewModel.chooseApp()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                                .foregroundColor(.secondary)
                        )
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                        guard let data = data as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil),
                              url.pathExtension == "app" else { return }
                        Task { @MainActor in
                            viewModel.setApp(url)
                        }
                    }
                    return true
                }

                if viewModel.appURL != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.tr("output.label"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(viewModel.defaultOutputName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Button(L10n.tr("output.change")) {
                                viewModel.chooseOutput()
                            }
                        }
                        Text(viewModel.outputURL?.deletingLastPathComponent().path ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
                }

                advancedSettings
                    .disabled(viewModel.isCreating)

                if viewModel.isCreating {
                    HStack(spacing: 12) {
                        ProgressView(value: viewModel.progress) {
                            Text(viewModel.statusMessage)
                        }
                        Button(L10n.tr("btn.cancel")) {
                            viewModel.cancelCreation()
                        }
                    }
                    .padding(.horizontal)
                }

                Button {
                    viewModel.createDMG()
                } label: {
                    Label(L10n.tr("btn.create"), systemImage: "opticaldiscdrive")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.appURL == nil || viewModel.isCreating)
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    private var advancedSettings: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(L10n.tr("settings.dmgIcon.title"))
                    Spacer()
                    Picker("", selection: $settings.dmgIconPreset) {
                        ForEach(DMGIconPreset.allCases, id: \.self) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 130)

                    Button {
                        settings.dmgIconPreset = .medium
                        settings.dmgIconSize = DMGIconPreferences.defaultSize
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("advanced.reset"))

                    Button {
                        settings.dmgIconPreset = .unset
                    } label: {
                        Image(systemName: "nosign")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("advanced.unset"))
                    .disabled(settings.dmgIconPreset == .unset)
                }

                if settings.dmgIconPreset == .custom {
                    Stepper(value: $settings.dmgIconSize, in: DMGIconPreferences.sizeRange) {
                        Text("\(L10n.tr("settings.dmgIcon.size")): \(settings.dmgIconSize)")
                            .monospacedDigit()
                    }
                    .font(.callout)
                }

                Divider()

                HStack(spacing: 8) {
                    Text(L10n.tr("settings.dmgWindow.title"))
                    Spacer()
                    Picker("", selection: $settings.dmgWindowPreset) {
                        ForEach(DMGWindowPreset.allCases, id: \.self) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)

                    Button {
                        settings.dmgWindowPreset = .medium
                        settings.dmgWindowWidth = DMGWindowPreferences.defaultWidth
                        settings.dmgWindowHeight = DMGWindowPreferences.defaultHeight
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("advanced.reset"))

                    Button {
                        settings.dmgWindowPreset = .unset
                    } label: {
                        Image(systemName: "nosign")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("advanced.unset"))
                    .disabled(settings.dmgWindowPreset == .unset)
                }

                if settings.dmgWindowPreset == .custom {
                    HStack(spacing: 16) {
                        Stepper(value: $settings.dmgWindowWidth, in: DMGWindowPreferences.widthRange) {
                            Text("\(L10n.tr("settings.dmgWindow.width")): \(settings.dmgWindowWidth)")
                                .monospacedDigit()
                        }
                        Stepper(value: $settings.dmgWindowHeight, in: DMGWindowPreferences.heightRange) {
                            Text("\(L10n.tr("settings.dmgWindow.height")): \(settings.dmgWindowHeight)")
                                .monospacedDigit()
                        }
                    }
                    .font(.callout)
                }

            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.secondary)
                Text(L10n.tr("advanced.title"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .help(L10n.tr("advanced.hint"))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    // MARK: - 监听发现

    private var watchedTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .foregroundColor(.secondary)
                Text(L10n.tr("watch.title"))
                    .font(.headline)
                Spacer()
                if watchManager.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("\(watchManager.discovered.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if watchManager.monitoredCount > 0 {
                    Text(L10n.tr("watch.monitoring", watchManager.monitoredCount))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if watchManager.eventCount > 0 {
                    Text(L10n.tr("watch.events", watchManager.eventCount))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Button {
                    watchManager.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(L10n.tr("watch.refresh"))
            }

            if watchManager.discovered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(L10n.tr("watch.empty"))
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(watchManager.monitoredCount == 0
                         ? L10n.tr("watch.empty.hint")
                         : L10n.tr("watch.empty.monitoring", watchManager.monitoredCount))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if watchManager.monitoredCount > 0 {
                        VStack(spacing: 3) {
                            ForEach(watchManager.monitoredPaths, id: \.self) { path in
                                HStack(spacing: 4) {
                                    Image(systemName: watchManager.unreadablePaths.contains(path)
                                          ? "exclamationmark.triangle.fill"
                                          : "folder")
                                        .font(.caption2)
                                        .foregroundColor(watchManager.unreadablePaths.contains(path) ? .orange : .secondary)
                                    Text(path)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(watchManager.discovered) { item in
                            watchedRow(item)
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func watchedRow(_ item: DiscoveredApp) -> some View {
        Button {
            watchManager.select(item.id)
            viewModel.setApp(item.url)
            selectedTab = .create
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.headline)
                            .lineLimit(1)
                        if !item.version.isEmpty {
                            Text("v\(item.version)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if watchManager.newIDs.contains(item.id) {
                            Text(L10n.tr("watch.new"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor))
                        }
                    }
                    Text(item.url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(watchManager.selectedID == item.id
                          ? Color.accentColor.opacity(0.22)
                          : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 打开设置窗口的按钮：与菜单栏“设置…”（⌘,）功能一致。
struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape")
        }
        .help(L10n.tr("btn.settings"))
    }
}

/// 允许按住窗口背景（含页签栏等非控件区域）拖动窗口。
private struct WindowDragConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.isMovableByWindowBackground = true }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.isMovableByWindowBackground = true }
    }
}