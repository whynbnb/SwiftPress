import XCTest
@testable import SwiftPress

final class CoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftPressTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testAppBundleValidation() throws {
        let app = temporaryDirectory.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"),
            withIntermediateDirectories: true
        )
        XCTAssertFalse(AppBundle.isValid(at: app))

        try Data().write(to: app.appendingPathComponent("Contents/Info.plist"))
        XCTAssertTrue(AppBundle.isValid(at: app))

        let file = temporaryDirectory.appendingPathComponent("Fake.app")
        try Data().write(to: file)
        XCTAssertFalse(AppBundle.isValid(at: file))
    }

    func testDefaultFilenameUsesVersionAndDate() throws {
        let app = temporaryDirectory.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"),
            withIntermediateDirectories: true
        )
        let plist = ["CFBundleShortVersionString": "2.3"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))

        let name = AppInfo.defaultDMGFilename(for: app)
        XCTAssertTrue(name.hasPrefix("Test v2.3 "))
        XCTAssertTrue(name.hasSuffix(".dmg"))
    }

    func testLayoutPatchesWindowAndIcon() throws {
        try DMGLayout.writeDSStore(to: temporaryDirectory, windowSize: (640, 400), iconSize: 128)
        let data = try Data(contentsOf: temporaryDirectory.appendingPathComponent(".DS_Store"))

        XCTAssertEqual(Array(data.prefix(4)), [0, 0, 0, 1])
        XCTAssertNotNil(data.range(of: Data("{ 640,  400}}".utf8)))
        XCTAssertEqual(count(of: 128.0, in: data), 1)
        XCTAssertEqual(count(of: 76.0, in: data), 0)
    }

    func testLayoutUnsetWindowKeepsIcon() throws {
        try DMGLayout.writeDSStore(to: temporaryDirectory, windowSize: nil, iconSize: 128)
        let data = try Data(contentsOf: temporaryDirectory.appendingPathComponent(".DS_Store"))

        XCTAssertNotNil(data.range(of: Data("WindowBoundX".utf8)))
        XCTAssertNil(data.range(of: Data("WindowBounds".utf8)))
        XCTAssertEqual(count(of: 128.0, in: data), 1)
    }

    func testLayoutUnsetIconUsesFinderDefault() throws {
        try DMGLayout.writeDSStore(to: temporaryDirectory, windowSize: (640, 400), iconSize: nil)
        let data = try Data(contentsOf: temporaryDirectory.appendingPathComponent(".DS_Store"))

        XCTAssertEqual(count(of: 48.0, in: data), 1)
    }

    func testWatchPathDecodingFallsBackToDefaults() throws {
        let watchPath = try JSONDecoder().decode(WatchPath.self, from: Data("{}".utf8))
        XCTAssertEqual(watchPath.path, "")
        XCTAssertTrue(watchPath.enabled)
        XCTAssertEqual(watchPath.fileExtension, "app")
        XCTAssertEqual(watchPath.depth, .recursive)
    }

    private func count(of value: Double, in data: Data) -> Int {
        var bits = value.bitPattern.bigEndian
        let needle = withUnsafeBytes(of: &bits) { Data($0) }
        var result = 0
        var search = data.startIndex
        while let range = data.range(of: needle, options: [], in: search..<data.endIndex) {
            result += 1
            search = range.upperBound
        }
        return result
    }
}
