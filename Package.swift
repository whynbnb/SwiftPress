// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SwiftPress",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SwiftPress",
            dependencies: [],
            path: "Sources/SwiftPress",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
