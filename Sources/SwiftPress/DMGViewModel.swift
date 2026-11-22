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

/// 可打包应用包的校验，GUI 与 CLI 共用。
enum AppBundle {
    /// 是否为有效的 `.app`：目录，且包含 `Contents/Info.plist`。
    static func isValid(at url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "app" else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        return FileManager.default.fileExists(
            atPath: url.appendingPathComponent("Contents/Info.plist").path
        )
    }
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
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        let versionPart = version == "development" ? "development" : "v\(version)"
        return "\(appName) \(versionPart) \(dateStr).dmg"
    }

    /// 默认输出路径：优先 app 同目录；不可写时回退到下载目录，并避免覆盖同名文件。
    static func defaultOutputURL(for appURL: URL) -> URL {
        let appDirectory = appURL.deletingLastPathComponent()
        let directory: URL
        if FileManager.default.isWritableFile(atPath: appDirectory.path) {
            directory = appDirectory
        } else {
            directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? appDirectory
        }
        return uniqueOutputURL(in: directory, filename: defaultDMGFilename(for: appURL))
    }

    /// 在目录中找一个不冲突的文件名，例如 `Foo.dmg`、`Foo 2.dmg`。
    static func uniqueOutputURL(in directory: URL, filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let pathExtension = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index).\(pathExtension)")
            index += 1
        }
        return candidate
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
    @Published var warningMessage: String?
    /// 最近一次成功生成的 DMG 路径（创建过程中 outputURL 可能被修改）。
    @Published private(set) var lastOutputURL: URL?

    private var creationTask: Task<Void, Never>?
    private var outputWasChosen = false

    var defaultOutputName: String {
        guard let appURL else { return "" }
        return AppInfo.defaultDMGFilename(for: appURL)
    }

    func setApp(_ url: URL) {
        guard !isCreating, AppBundle.isValid(at: url) else { return }
        appURL = url
        outputWasChosen = false
        outputURL = AppInfo.defaultOutputURL(for: url)
    }

    func clearApp() {
        guard !isCreating else { return }
        appURL = nil
        outputURL = nil
        outputWasChosen = false
    }

    func chooseApp() {
        guard !isCreating else { return }
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
        guard !isCreating else { return }
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
            outputWasChosen = true
            outputURL = url
        }
    }

    func createDMG() {
        guard let appURL, var outputURL, !isCreating else { return }

        // 使用默认输出名时，如果同名文件已存在，自动换一个不冲突的名字。
        if !outputWasChosen, FileManager.default.fileExists(atPath: outputURL.path) {
            outputURL = AppInfo.uniqueOutputURL(
                in: outputURL.deletingLastPathComponent(),
                filename: outputURL.lastPathComponent
            )
            self.outputURL = outputURL
        }

        isCreating = true
        progress = 0
        statusMessage = L10n.tr("status.preparing")
        errorMessage = nil
        warningMessage = nil
        lastOutputURL = nil

        let dmgPath = outputURL.path
        let appName = appURL.lastPathComponent
        let volumeName = outputURL.deletingPathExtension().lastPathComponent
        let windowSize = DMGWindowPreferences.currentSize
        let iconSize = DMGIconPreferences.currentSize
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftpress_\(UUID().uuidString)")

        creationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let warning = try await Self.performCreation(
                    appURL: appURL,
                    outputPath: dmgPath,
                    appName: appName,
                    volumeName: volumeName,
                    windowSize: windowSize,
                    iconSize: iconSize,
                    tempDir: tempDir
                ) { message, value in
                    await self.updateStatus(message, progress: value)
                }
                self.finishSuccess(outputURL: outputURL, warning: warning)
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: tempDir)
                ChildProcessRegistry.shared.terminate()
                self.finishCancelled()
            } catch {
                try? FileManager.default.removeItem(at: tempDir)
                ChildProcessRegistry.shared.terminate()
                if Task.isCancelled {
                    self.finishCancelled()
                } else {
                    self.finishFailure(error)
                }
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

    private func finishSuccess(outputURL: URL, warning: String?) {
        isCreating = false
        progress = 1.0
        warningMessage = warning
        lastOutputURL = outputURL
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
        windowSize: (width: Int, height: Int)?,
        iconSize: Int?,
        tempDir: URL,
        report: @escaping @Sendable (String, Double) async -> Void
    ) async throws -> String? {
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Task.checkCancellation()
        await report(L10n.tr("status.tempDir"), 0.1)

        let staging = tempDir.appendingPathComponent(volumeName)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        await report(L10n.tr("status.copying"), 0.2)
        try fileManager.copyItem(at: appURL, to: staging.appendingPathComponent(appName))
        try Task.checkCancellation()

        await report(L10n.tr("status.symlink"), 0.4)
        let applicationsAlias = staging.appendingPathComponent("Applications")
        if fileManager.fileExists(atPath: applicationsAlias.path) {
            try fileManager.removeItem(at: applicationsAlias)
        }
        try fileManager.createSymbolicLink(
            atPath: applicationsAlias.path,
            withDestinationPath: "/Applications"
        )

        var warning: String?

        // 直接把窗口/图标布局写进 .DS_Store，不调用 Finder，也不会弹出任何窗口。
        await report(L10n.tr("status.layout"), 0.5)
        do {
            try DMGLayout.writeDSStore(
                to: staging,
                windowSize: windowSize,
                iconSize: iconSize
            )
        } catch {
            warning = L10n.tr("warning.windowLayout")
        }

        try Task.checkCancellation()
        await report(L10n.tr("status.creating"), 0.7)

        // 先写到同目录的隐藏临时文件，成功后再替换目标文件。
        // 取消/失败时目标文件保持不变，也不会留下半成品 DMG。
        let finalOutputURL = URL(fileURLWithPath: outputPath)
        let tempOutputURL = finalOutputURL.deletingLastPathComponent()
            .appendingPathComponent(".swiftpress-\(UUID().uuidString).dmg")
        defer { try? fileManager.removeItem(at: tempOutputURL) }

        try DMGImageBuilder.createCompressedImage(
            stagingPath: staging.path,
            outputPath: tempOutputURL.path,
            volumeName: volumeName
        )
        try Task.checkCancellation()
        try DMGImageBuilder.publish(tempOutput: tempOutputURL, finalOutput: finalOutputURL)

        await report(L10n.tr("status.cleaning"), 0.95)
        try? fileManager.removeItem(at: tempDir)
        await report(L10n.tr("status.done"), 1.0)
        return warning
    }
}

/// 生成 DMG 的系统命令封装（hdiutil），GUI 与 CLI 共用。
enum DMGImageBuilder {
    struct CommandError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 运行命令并返回标准输出；命令失败或任务被取消时抛错。
    static func run(_ executable: String, _ arguments: [String], register: Bool = true) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        if register { ChildProcessRegistry.shared.set(process) }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if register { ChildProcessRegistry.shared.set(nil) }

        if Task.isCancelled {
            throw CancellationError()
        }

        guard process.terminationStatus == 0 else {
            let stderr = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw CommandError(
                message: stderr.isEmpty
                    ? "\(executable) exited with status \(process.terminationStatus)"
                    : stderr
            )
        }
        return outData
    }

    /// 把临时输出原子地替换到最终路径；目标已存在时保留其原有属性。
    static func publish(tempOutput: URL, finalOutput: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: finalOutput.path) {
            _ = try fileManager.replaceItemAt(finalOutput, withItemAt: tempOutput)
        } else {
            try fileManager.moveItem(at: tempOutput, to: finalOutput)
        }
    }

    /// 创建压缩（UDZO）镜像。
    static func createCompressedImage(stagingPath: String, outputPath: String, volumeName: String) throws {
        _ = try run("/usr/bin/hdiutil", [
            "create",
            "-volname", volumeName,
            "-srcfolder", stagingPath,
            "-fs", "HFS+",
            "-ov",
            "-format", "UDZO",
            outputPath
        ])
    }
}

/// 直接写入 `.DS_Store`，让 DMG 打开时呈现干净的安装器布局。
///
/// 使用一份由 Finder 生成的空白卷模板（隐藏工具栏/侧栏/状态栏、图标按名称排列），
/// 打包时只替换窗口尺寸和图标大小。整个流程不调用 Finder，因此不会弹窗、也不需要自动化权限。
enum DMGLayout {
    enum LayoutError: LocalizedError {
        case templateMissing
        case invalidTemplate

        var errorDescription: String? {
            switch self {
            case .templateMissing: return "找不到 DMG 布局模板"
            case .invalidTemplate: return "DMG 布局模板无效"
            }
        }
    }

    /// 模板中由 Finder 写入的原始值，替换时要求长度一致。
    private static let templateBounds = "{{200, -40}, {1000, 1000}}"
    private static let templateIconSize = 76.0

    static func writeDSStore(
        to directory: URL,
        windowSize: (width: Int, height: Int)?,
        iconSize: Int?
    ) throws {
        guard let url = templateURL, var data = try? Data(contentsOf: url) else {
            throw LayoutError.templateMissing
        }

        if let windowSize {
            // .DS_Store 的 WindowBounds 使用左下角原点；换算成距顶部 120pt。
            let screenHeight = Int(CGDisplayBounds(CGMainDisplayID()).height)
            let bottomY = max(0, min(screenHeight - 120 - windowSize.height, 999))
            let bounds = "{{200, \(String(format: "%3d", bottomY))}, {\(padded(windowSize.width)), \(padded(windowSize.height))}}"
            guard bounds.utf8.count == templateBounds.utf8.count,
                  let boundsRange = data.range(of: Data(templateBounds.utf8)) else {
                throw LayoutError.invalidTemplate
            }
            data.replaceSubrange(boundsRange, with: Data(bounds.utf8))
        } else {
            // 不设置窗口大小：把键名改成同长度的未知键，Finder 会回落默认尺寸。
            let key = Data("WindowBounds".utf8)
            guard let keyRange = data.range(of: key) else {
                throw LayoutError.invalidTemplate
            }
            data.replaceSubrange(keyRange, with: Data("WindowBoundX".utf8))
        }

        // 不设置图标大小时使用 Finder 默认值，同时保留按名称排列等视图设置。
        let effectiveIconSize = iconSize ?? DMGIconPreferences.unsetFallbackSize
        var oldIconBits = templateIconSize.bitPattern.bigEndian
        let oldIconData = withUnsafeBytes(of: &oldIconBits) { Data($0) }
        guard let iconRange = data.range(of: oldIconData) else {
            throw LayoutError.invalidTemplate
        }
        var newIconBits = Double(effectiveIconSize).bitPattern.bigEndian
        let newIconData = withUnsafeBytes(of: &newIconBits) { Data($0) }
        data.replaceSubrange(iconRange, with: newIconData)

        try data.write(to: directory.appendingPathComponent(".DS_Store"))
    }

    /// 4 位宽、空格补位，保证替换后的字符串与模板等长。
    private static func padded(_ value: Int) -> String {
        String(format: "%4d", value)
    }

    private static var templateURL: URL? {
        #if SWIFT_PACKAGE
        Bundle.module.url(forResource: "dmg-layout", withExtension: "dsstore")
        #else
        Bundle.main.url(forResource: "dmg-layout", withExtension: "dsstore")
        #endif
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
        guard AppBundle.isValid(at: appURL) else {
            fail("不是有效的 .app 包: \(appURL.path)")
        }

        let outputURL = outputPath.map(fileURL) ?? AppInfo.defaultOutputURL(for: appURL)

        do {
            let warning = try create(app: appURL, output: outputURL)
            if let warning {
                print("⚠️ \(warning)")
            }
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

    private static func create(app: URL, output: URL) throws -> String? {
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

        var warning: String?
        do {
            try DMGLayout.writeDSStore(
                to: staging,
                windowSize: DMGWindowPreferences.currentSize,
                iconSize: DMGIconPreferences.currentSize
            )
        } catch {
            warning = L10n.tr("warning.windowLayout")
        }

        let tempOutput = output.deletingLastPathComponent()
            .appendingPathComponent(".swiftpress-\(UUID().uuidString).dmg")
        defer { try? fileManager.removeItem(at: tempOutput) }

        try DMGImageBuilder.createCompressedImage(
            stagingPath: staging.path,
            outputPath: tempOutput.path,
            volumeName: volumeName
        )
        try DMGImageBuilder.publish(tempOutput: tempOutput, finalOutput: output)
        return warning
    }
}
