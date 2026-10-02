import Foundation
import Combine
import CoreServices

/// 监听目录中发现的一个候选文件。
struct DiscoveredApp: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let version: String
    let modifiedAt: Date

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.version = Self.readVersion(from: url)
        self.modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap { $0.contentModificationDate } ?? Date()
    }

    private static func readVersion(from url: URL) -> String {
        let plistPath = url.appendingPathComponent("Contents/Info.plist").path
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return ""
        }
        if let version = plist["CFBundleShortVersionString"] as? String, !version.isEmpty {
            return version
        }
        if let version = plist["CFBundleVersion"] as? String, !version.isEmpty {
            return version
        }
        return ""
    }
}

/// 监听多个目录，发现符合各自扩展名（及是否递归）要求的文件后在列表中呈现。
///
/// FSEvents 做增量更新（实时、只处理变化路径）；全量扫描只在启动 / 改配置 /
/// 手动刷新时执行一次，并且边扫边出结果，避免大目录长时间空列表。
@MainActor
final class WatchManager: ObservableObject {
    static let shared = WatchManager()

    @Published private(set) var discovered: [DiscoveredApp] = []
    /// 用户手动点击选中的项（仅用于列表高亮，不自动选中）。
    @Published var selectedID: UUID?
    /// 新检测到、尚未点击查看的项，用于显示 NEW 标记。
    @Published private(set) var newIDs: Set<UUID> = []
    @Published private(set) var monitoredCount = 0
    @Published private(set) var monitoredPaths: [String] = []
    @Published private(set) var unreadablePaths: Set<String> = []
    /// 是否正在做全量扫描（大目录较慢）。
    @Published private(set) var isScanning = false
    /// 已接收到的 FSEvents 事件数（用于确认实时监听是否生效）。
    @Published private(set) var eventCount = 0

    private var eventStream: FSEventStreamRef?
    private var activeWatchPaths: [WatchPath] = []
    private var knownPaths: Set<String> = []
    private var hasScanned = false

    private var scanGeneration = 0
    private var scanInFlight = false
    private var pendingRescan = false

    private var pollTask: Task<Void, Never>?

    private let maxItems = 200

    private init() {}

    /// 根据当前设置重建监听。设置变化时调用。
    func sync(with watchPaths: [WatchPath]) {
        activeWatchPaths = watchPaths.filter { $0.enabled && !$0.path.isEmpty }
        monitoredCount = activeWatchPaths.count
        monitoredPaths = activeWatchPaths.map(\.path)
        unreadablePaths = Set(monitoredPaths.filter { !FileManager.default.isReadableFile(atPath: $0) })
        restartStream()
        startPolling()
        rescan()
    }

    /// 手动立即刷新一次（全量扫描）。
    func refresh() {
        rescan()
    }

    /// 用户点击某项：清除它的 NEW 标记并设为选中。
    func select(_ id: UUID) {
        selectedID = id
        newIDs.remove(id)
    }

    /// 低频兜底轮询，仅做周期性校正（正常情况下靠 FSEvents 实时更新）。
    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                self?.rescan()
            }
        }
    }

    // MARK: - FSEvents

    private func restartStream() {
        if let eventStream {
            FSEventStreamStop(eventStream)
            FSEventStreamInvalidate(eventStream)
            self.eventStream = nil
        }

        let roots = activeWatchPaths.map(\.path)
        guard !roots.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, paths, flags, _ in
            guard let info else { return }
            let manager = Unmanaged<WatchManager>.fromOpaque(info).takeUnretainedValue()
            let pathList = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []

            var dropped = false
            for index in 0..<numEvents {
                let flag = flags[index]
                if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped) != 0
                    || flag & FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped) != 0 {
                    dropped = true
                }
            }

            MainActor.assumeIsolated {
                manager.handleEvents(paths: pathList, dropped: dropped)
            }
        }

        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            roots as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        eventStream = stream
    }

    /// FSEvents 增量更新：只处理变化的路径，避免全量扫描。
    private func handleEvents(paths: [String], dropped: Bool) {
        eventCount += paths.count

        // 只有在真正丢事件时才做一次全量校正
        if dropped {
            rescan()
            return
        }

        let fileManager = FileManager.default
        var changed = false

        for path in paths {
            if fileManager.fileExists(atPath: path) {
                guard candidateMatches(path) else { continue }
                if !discovered.contains(where: { $0.url.path == path }) {
                    discovered.append(DiscoveredApp(url: URL(fileURLWithPath: path)))
                    changed = true
                }
            } else {
                // 路径已删除（可能是文件夹）：连同其下所有已发现项一并移除，
                // 不要求该路径本身扩展名匹配。
                let before = discovered.count
                discovered.removeAll { $0.url.path == path || $0.url.path.hasPrefix(path + "/") }
                if discovered.count != before {
                    changed = true
                }
            }
        }

        if changed {
            finalizeChanges()
        }
    }

    /// 判断某个路径是否符合任一监听配置（前缀、扫描深度、包内、扩展名）。
    private func candidateMatches(_ path: String) -> Bool {
        for watchPath in activeWatchPaths {
            let rootPath = URL(fileURLWithPath: watchPath.path).path
            let prefix = rootPath + "/"
            guard path.hasPrefix(prefix) else { continue }

            let relativeDepth = path.dropFirst(prefix.count).split(separator: "/").count
            if let maxDepth = watchPath.depth.maxDepth, relativeDepth > maxDepth {
                continue
            }

            if Self.isInsidePackage(path, root: rootPath) {
                continue
            }

            let wantedExtension = watchPath.fileExtension
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                .lowercased()
            if wantedExtension.isEmpty || URL(fileURLWithPath: path).pathExtension.lowercased() == wantedExtension {
                return true
            }
        }
        return false
    }

    private nonisolated static let packageExtensions: Set<String> = [
        "app", "framework", "bundle", "xpc", "appex", "plugin", "kext",
        "prefpane", "qlgenerator", "mdimporter", "saver", "wdgt"
    ]

    private nonisolated static func isInsidePackage(_ path: String, root: String) -> Bool {
        let prefix = root + "/"
        let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        var components = relative.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return false }
        components.removeLast()
        return components.contains { component in
            packageExtensions.contains((component as NSString).pathExtension.lowercased())
        }
    }

    // MARK: - Full scan (background, progressive)

    /// 触发一次全量扫描。磁盘枚举与 Info.plist 读取都在后台线程进行，避免卡住界面。
    private func rescan() {
        scanGeneration += 1
        let generation = scanGeneration

        if scanInFlight {
            pendingRescan = true
            return
        }
        scanInFlight = true
        isScanning = true

        let snapshot = activeWatchPaths
        Task.detached(priority: .utility) {
            let matches = Self.scan(watchPaths: snapshot) { partial in
                Task { @MainActor in
                    self.publishPartial(partial, generation: generation)
                }
            }
            await MainActor.run {
                self.scanInFlight = false
                self.isScanning = false
                if generation == self.scanGeneration {
                    self.applyScan(matches)
                }
                if self.pendingRescan {
                    self.pendingRescan = false
                    self.rescan()
                }
            }
        }
    }

    /// 边扫边发布部分结果，让大目录也能较快看到内容。
    private func publishPartial(_ partial: [DiscoveredApp], generation: Int) {
        guard generation == scanGeneration, isScanning else { return }
        discovered = deduplicated(partial)
    }

    /// 纯计算、无 UI 依赖，可安全地在后台运行。
    private nonisolated static func scan(
        watchPaths: [WatchPath],
        onPartial: @escaping @Sendable ([DiscoveredApp]) -> Void
    ) -> [DiscoveredApp] {
        let fileManager = FileManager.default
        var matches: [DiscoveredApp] = []
        var processed = 0

        for watchPath in watchPaths {
            let baseURL = URL(fileURLWithPath: watchPath.path)
            let wantedExtension = watchPath.fileExtension
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                .lowercased()

            func matchesExtension(_ url: URL) -> Bool {
                wantedExtension.isEmpty || url.pathExtension.lowercased() == wantedExtension
            }

            switch watchPath.depth {
            case .top:
                guard let entries = try? fileManager.contentsOfDirectory(atPath: watchPath.path) else {
                    continue
                }
                for entry in entries where !entry.hasPrefix(".") {
                    let url = baseURL.appendingPathComponent(entry)
                    if matchesExtension(url) {
                        matches.append(DiscoveredApp(url: url))
                    }
                }

            case .oneLevel:
                guard let enumerator = fileManager.enumerator(
                    at: baseURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    continue
                }
                let rootPrefix = baseURL.path + "/"
                let maxDepth = watchPath.depth.maxDepth ?? 2
                for case let url as URL in enumerator {
                    processed += 1
                    let relativeDepth = url.path.hasPrefix(rootPrefix)
                        ? url.path.dropFirst(rootPrefix.count).split(separator: "/").count
                        : Int.max
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

                    if relativeDepth > maxDepth {
                        if isDirectory { enumerator.skipDescendants() }
                        continue
                    }
                    if matchesExtension(url) {
                        matches.append(DiscoveredApp(url: url))
                    }
                    if isDirectory, relativeDepth == maxDepth {
                        enumerator.skipDescendants()
                    }
                    if processed % 3000 == 0 {
                        onPartial(matches)
                    }
                }

            case .recursive:
                guard let enumerator = fileManager.enumerator(
                    at: baseURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    continue
                }
                for case let url as URL in enumerator {
                    processed += 1
                    if matchesExtension(url) {
                        matches.append(DiscoveredApp(url: url))
                    }
                    if processed % 3000 == 0 {
                        onPartial(matches)
                    }
                }
            }

            onPartial(matches)
        }

        return matches
    }

    /// 在主线程合并全量扫描结果。
    private func applyScan(_ matches: [DiscoveredApp]) {
        discovered = deduplicated(matches)
        finalizeChanges()
        hasScanned = true
    }

    private func deduplicated(_ matches: [DiscoveredApp]) -> [DiscoveredApp] {
        var seen = Set<String>()
        return matches
            .filter { seen.insert($0.url.path).inserted }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(maxItems)
            .map { $0 }
    }

    /// 排序、限流、维护选中项与高亮。
    private func finalizeChanges() {
        discovered.sort { $0.modifiedAt > $1.modifiedAt }
        if discovered.count > maxItems {
            discovered = Array(discovered.prefix(maxItems))
        }

        let newPaths = Set(discovered.map { $0.url.path })
        let appeared = newPaths.subtracting(knownPaths)
        knownPaths = newPaths

        // 新出现的项打上 NEW 标记；已消失的项清理标记
        if hasScanned {
            for item in discovered where appeared.contains(item.url.path) {
                newIDs.insert(item.id)
            }
        }
        newIDs.formIntersection(Set(discovered.map(\.id)))

        if let current = selectedID, !discovered.contains(where: { $0.id == current }) {
            selectedID = nil
        }
    }
}
