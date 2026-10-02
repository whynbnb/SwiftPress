import Foundation
import AppKit

/// 记录当前正在运行的子进程（hdiutil），便于退出时一并结束后台进程。
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

@MainActor
class DMGViewModel: ObservableObject {
    @Published var appURL: URL?
    @Published var outputURL: URL?
    @Published var isCreating: Bool = false
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""
    @Published var showSuccess: Bool = false
    @Published var errorMessage: String?

    var defaultOutputName: String {
        guard let appURL else { return "" }
        let appName = appURL.deletingPathExtension().lastPathComponent
        let version = readAppVersion(from: appURL)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        let versionPart = version == "development" ? "development" : "v\(version)"
        return "\(appName) \(versionPart) \(dateStr).dmg"
    }

    func setApp(_ url: URL) {
        appURL = url
        let appName = url.deletingPathExtension().lastPathComponent
        let version = readAppVersion(from: url)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        let versionPart = version == "development" ? "development" : "v\(version)"
        let dmgName = "\(appName) \(versionPart) \(dateStr).dmg"
        outputURL = url.deletingLastPathComponent().appendingPathComponent(dmgName)
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
        guard let appURL, let outputURL else { return }
        isCreating = true
        progress = 0
        statusMessage = L10n.tr("status.preparing")
        errorMessage = nil

        let dmgPath = outputURL.path
        let appName = appURL.lastPathComponent
        let volName = outputURL.deletingPathExtension().lastPathComponent

        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("swiftpress_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                await updateStatus(L10n.tr("status.tempDir"), progress: 0.1)

                let dmgStaging = tempDir.appendingPathComponent(volName)
                try FileManager.default.createDirectory(at: dmgStaging, withIntermediateDirectories: true)

                await updateStatus(L10n.tr("status.copying"), progress: 0.2)

                let destApp = dmgStaging.appendingPathComponent(appName)
                try FileManager.default.copyItem(at: appURL, to: destApp)

                await updateStatus(L10n.tr("status.symlink"), progress: 0.5)

                let applicationsAlias = dmgStaging.appendingPathComponent("Applications")
                try createApplicationsSymlink(at: applicationsAlias)

                await updateStatus(L10n.tr("status.creating"), progress: 0.6)

                try await createDMGWithHdiutil(
                    stagingPath: dmgStaging.path,
                    outputPath: dmgPath,
                    volumeName: volName
                )

                await updateStatus(L10n.tr("status.cleaning"), progress: 0.9)
                try FileManager.default.removeItem(at: tempDir)

                await updateStatus(L10n.tr("status.done"), progress: 1.0)

                isCreating = false
                showSuccess = true
            } catch {
                isCreating = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func readAppVersion(from url: URL) -> String {
        let plistPath = url.appendingPathComponent("Contents/Info.plist").path
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

    private func createApplicationsSymlink(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createSymbolicLink(
            atPath: url.path,
            withDestinationPath: "/Applications"
        )
    }

    private func createDMGWithHdiutil(
        stagingPath: String,
        outputPath: String,
        volumeName: String
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")

        let args = [
            "create",
            "-volname", volumeName,
            "-srcfolder", stagingPath,
            "-ov",
            "-format", "UDZO",
            outputPath
        ]
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // 后台线程持续读取输出，避免管道缓冲区写满导致 hdiutil 卡死
        let outputHandle = SendableBox(pipe.fileHandleForReading)
        let outputTask = Task.detached(priority: .utility) {
            outputHandle.value.readDataToEndOfFile()
        }

        // 异步等待进程退出，不阻塞主线程，确保退出操作能立即响应
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

        if status != 0 {
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "SwiftPress",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "hdiutil failed:\n\(errorMsg)"]
            )
        }
    }

    private func updateStatus(_ message: String, progress: Double) async {
        await MainActor.run {
            self.statusMessage = message
            self.progress = progress
        }
    }
}
