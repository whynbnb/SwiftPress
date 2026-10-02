import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DMGViewModel()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
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

            if viewModel.isCreating {
                ProgressView(value: viewModel.progress) {
                    Text(viewModel.statusMessage)
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
        .padding()
        .frame(minWidth: 460, minHeight: 360)
        .overlay(alignment: .topTrailing) {
            SettingsButton()
                .padding(12)
        }
        .preferredColorScheme(settings.resolvedColorScheme)
        .alert(L10n.tr("alert.success"), isPresented: $viewModel.showSuccess) {
            Button(L10n.tr("alert.showInFinder")) {
                if let url = viewModel.outputURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button(L10n.tr("alert.ok")) {}
        } message: {
            Text(L10n.tr("alert.success.msg", viewModel.outputURL?.lastPathComponent ?? ""))
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
        .buttonStyle(.plain)
        .help(L10n.tr("btn.settings"))
    }
}
