import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DMGViewModel()

    var body: some View {
        VStack(spacing: 20) {
            Text("SwiftPress")
                .font(.title)
                .fontWeight(.bold)

            Text("简易 DMG 安装包制作工具")
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
                        Text("拖入 .app 文件")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Button("或点击浏览...") {
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
                        Text("输出:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(viewModel.defaultOutputName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button("更改...") {
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
                Label("制作 DMG", systemImage: "opticaldiscdrive")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.appURL == nil || viewModel.isCreating)
            .padding(.horizontal)
        }
        .padding()
        .frame(minWidth: 460, minHeight: 360)
        .alert("完成", isPresented: $viewModel.showSuccess) {
            Button("在 Finder 中显示") {
                if let url = viewModel.outputURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button("好") {}
        } message: {
            Text("DMG 已创建: \(viewModel.outputURL?.lastPathComponent ?? "")")
        }
        .alert("错误", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
