import Foundation
import AppKit

/// 记录当前正在运行的子进程（hdiutil），便于退出/取消时一并结束后台进程。
final class ChildProcessRegistry: @unchecked Sendable {
    static let shared = ChildProcessRegistry()

    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process?) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let running = process
        lock.unlock()
        if running?.isRunning == true {
            running?.terminate()
        }
    }
}

/// 把非 Sendable 的值安全地传进 `@Sendable` 闭包（仅用于跨线程只读访问）。
private final class SendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// 应用信息工具（GUI 与 CLI 共用）。
enum AppInfo {
    /// 从 `Contents/Info.plist` 读取版本号，读不到返回 "development"。
    static func version(at appURL: URL) -> String {
        let plistPath = appURL.appendingPathComponent("Contents/Info.plist").path
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return "development"
        }
        if let version = plist["CFBundleShortVersionString"] as? String, !version.isEmpty {
            return version
        }
        if let version = plist["CFBundleVersion"] as? String, !version.isEmpty {
            return version
        }
        return "development"
    }

    /// 默认 DMG 文件名：`名称 v版本 日期.dmg`。
    static func defaultDMGFilename(for appURL: URL) -> String {
        let appName = appURL.deletingPathExtension().lastPathComponent
        let version = version(at: appURL)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        let versionPart = version == "development" ? "development" : "v\(version)"
        return "\(appName) \(versionPart) \(dateStr).dmg"
    }

    /// 默认输出路径（与 app 同目录）。
    static func defaultOutputURL(for appURL: URL) -> URL {
        appURL.deletingLastPathComponent().appendingPathComponent(defaultDMGFilename(for: appURL))
    }
}

@MainActor
class DMGViewModel: ObservableObject {
    @Published var appURL: URL?
    @Published var outputURL: URL?
    @Published var isCreating: Bool = false
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""
    @Published var showSuccess: Bool = false
    @Published var errorMessage: String?

    private var creationTask: Task<Void, Never>?

    var defaultOutputName: String {
        guard let appURL else { return "" }
        return AppInfo.defaultDMGFilename(for: appURL)
    }

    func setApp(_ url: URL) {
        appURL = url
        outputURL = AppInfo.defaultOutputURL(for: url)
    }

    func clearApp() {
        appURL = nil
        outputURL = nil
    }

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("panel.chooseApp")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK, let url = panel.url {
            setApp(url)
        }
    }

    func chooseOutput() {
        let panel = NSSavePanel()
        panel.title = L10n.tr("panel.saveDMG")
        panel.allowedContentTypes = [.diskImage]
        panel.nameFieldStringValue = defaultOutputName
        if let currentDir = outputURL?.deletingLastPathComponent() {
            panel.directoryURL = currentDir
        } else if let appDir = appURL?.deletingLastPathComponent() {
            panel.directoryURL = appDir
        }
        if panel.runModal() == .OK, let url = panel.url {
            outputURL = url
        }
    }

    func createDMG() {
        guard let appURL, let outputURL, !isCreating else { return }

        isCreating = true
        progress = 0
        statusMessage = L10n.tr("status.preparing")
        errorMessage = nil

        let dmgPath = outputURL.path
        let appName = appURL.lastPathComponent
        let volumeName = outputURL.deletingPathExtension().lastPathComponent
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftpress_\(UUID().uuidString)")

        creationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Self.performCreation(
                    appURL: appURL,
                    outputPath: dmgPath,
                    appName: appName,
                    volumeName: volumeName,
                    tempDir: tempDir
                ) { message, value in
                    await self.updateStatus(message, progress: value)
                }
                self.finishSuccess()
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: tempDir)
                ChildProcessRegistry.shared.terminate()
                self.finishCancelled()
            } catch {
                try? FileManager.default.removeItem(at: tempDir)
                self.finishFailure(error)
            }
        }
    }

    /// 取消正在进行的制作：结束 hdiutil 子进程并取消任务。
    func cancelCreation() {
        guard isCreating else { return }
        statusMessage = L10n.tr("status.cancelling")
        ChildProcessRegistry.shared.terminate()
        creationTask?.cancel()
    }

    private func finishSuccess() {
        isCreating = false
        progress = 1.0
        showSuccess = true
    }

    private func finishCancelled() {
        isCreating = false
        progress = 0
        statusMessage = L10n.tr("status.cancelled")
    }

    private func finishFailure(_ error: Error) {
        isCreating = false
        errorMessage = error.localizedDescription
    }

    private func updateStatus(_ message: String, progress: Double) {
        statusMessage = message
        self.progress = progress
    }

    // MARK: - 后台制作流程（不占用主线程，可取消）

    private nonisolated static func performCreation(
        appURL: URL,
        outputPath: String,
        appName: String,
        volumeName: String,
        tempDir: URL,
        report: @escaping @Sendable (String, Double) async -> Void
    ) async throws {
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Task.checkCancellation()
        await report(L10n.tr("status.tempDir"), 0.1)

        let staging = tempDir.appendingPathComponent(volumeName)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        await report(L10n.tr("status.copying"), 0.2)
        try fileManager.copyItem(at: appURL, to: staging.appendingPathComponent(appName))
        try Task.checkCancellation()

        await report(L10n.tr("status.symlink"), 0.5)
        let applicationsAlias = staging.appendingPathComponent("Applications")
        if fileManager.fileExists(atPath: applicationsAlias.path) {
            try fileManager.removeItem(at: applicationsAlias)
        }
        try fileManager.createSymbolicLink(
            atPath: applicationsAlias.path,
            withDestinationPath: "/Applications"
        )

        await report(L10n.tr("status.creating"), 0.6)
        try await createDMGWithHdiutil(
            stagingPath: staging.path,
            outputPath: outputPath,
            volumeName: volumeName
        )

        try Task.checkCancellation()
        await report(L10n.tr("status.cleaning"), 0.9)
        try? fileManager.removeItem(at: tempDir)
        await report(L10n.tr("status.done"), 1.0)
    }

    private nonisolated static func createDMGWithHdiutil(
        stagingPath: String,
        outputPath: String,
        volumeName: String
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "create",
            "-volname", volumeName,
            "-srcfolder", stagingPath,
            "-ov",
            "-format", "UDZO",
            outputPath
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // 后台线程持续读取输出，避免管道缓冲区写满导致 hdiutil 卡死
        let outputHandle = SendableBox(pipe.fileHandleForReading)
        let outputTask = Task.detached(priority: .utility) {
            outputHandle.value.readDataToEndOfFile()
        }

        // 异步等待进程退出，不阻塞主线程，确保退出/取消能立即响应
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
                ChildProcessRegistry.shared.set(process)
            } catch {
                continuation.resume(throwing: error)
            }
        }

        ChildProcessRegistry.shared.set(nil)
        let errorData = await outputTask.value

        if Task.isCancelled {
            throw CancellationError()
        }

        if status != 0 {
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "SwiftPress",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "hdiutil failed:\n\(errorMsg)"]
            )
        }
    }
}

/// 命令行支持：`SwiftPress --app <App.app> [--output <out.dmg>]`
enum CommandLineSupport {
    /// 检测到 CLI 参数时执行打包并退出；返回 false 表示按 GUI 启动。
    @discardableResult
    static func runIfNeeded() -> Bool {
        let args = Array(CommandLine.arguments.dropFirst())
        let isCLI = args.contains { arg in
            arg == "--app" || arg == "--output" || arg == "-o" || arg == "-h" || arg == "--help"
                || arg.hasPrefix("--app=") || arg.hasPrefix("--output=")
        }
        guard isCLI else {
            return false
        }

        if args.contains("-h") || args.contains("--help") {
            printUsage()
            exit(0)
        }

        var appPath: String?
        var outputPath: String?
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--app", index + 1 < args.count {
                appPath = args[index + 1]
                index += 2
                continue
            }
            if arg.hasPrefix("--app=") {
                appPath = String(arg.dropFirst("--app=".count))
                index += 1
                continue
            }
            if (arg == "--output" || arg == "-o"), index + 1 < args.count {
                outputPath = args[index + 1]
                index += 2
                continue
            }
            if arg.hasPrefix("--output=") {
                outputPath = String(arg.dropFirst("--output=".count))
                index += 1
                continue
            }
            index += 1
        }

        guard let appPath else {
            fail("缺少 --app 参数")
        }

        let appURL = fileURL(appPath)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            fail("找不到应用: \(appURL.path)")
        }

        let outputURL = outputPath.map(fileURL) ?? AppInfo.defaultOutputURL(for: appURL)

        do {
            try create(app: appURL, output: outputURL)
            print("✅ 已生成 \(outputURL.path)")
            exit(0)
        } catch {
            fail("制作失败: \(error.localizedDescription)")
        }
    }

    private static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    private static func printUsage() {
        print("""
        SwiftPress CLI

        用法:
          SwiftPress --app <path/to/App.app> [--output <path/to/out.dmg>]

        选项:
          --app            待打包的 .app 路径（必填）
          --output, -o     输出 DMG 路径（可选，默认与 app 同目录，按版本+日期命名）
          -h, --help       显示帮助
        """)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("❌ \(message)\n").utf8))
        exit(1)
    }

    private static func create(app: URL, output: URL) throws {
        let fileManager = FileManager.default
        let volumeName = output.deletingPathExtension().lastPathComponent
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("swiftpress_cli_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let staging = tempDir.appendingPathComponent(volumeName)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try fileManager.copyItem(at: app, to: staging.appendingPathComponent(app.lastPathComponent))

        let applicationsAlias = staging.appendingPathComponent("Applications")
        if fileManager.fileExists(atPath: applicationsAlias.path) {
            try fileManager.removeItem(at: applicationsAlias)
        }
        try fileManager.createSymbolicLink(
            atPath: applicationsAlias.path,
            withDestinationPath: "/Applications"
        )

        try runHdiutil(staging: staging.path, output: output.path, volumeName: volumeName)
    }

    private static func runHdiutil(staging: String, output: String, volumeName: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "create",
            "-volname", volumeName,
            "-srcfolder", staging,
            "-ov",
            "-format", "UDZO",
            output
        ]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "SwiftPress",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "hdiutil failed (status \(process.terminationStatus))"]
            )
        }
    }
}
