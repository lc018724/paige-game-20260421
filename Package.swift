// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThreadGame",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "ThreadGame",
            path: "Sources/ThreadGame"
        ),
        .testTarget(
            name: "ThreadGameTests",
            dependencies: ["ThreadGame"],
            path: "Tests/ThreadGameTests"
        )
    ]
)
