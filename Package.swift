// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mac-agent",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MacAgentCore", path: "Sources/MacAgentCore"),
        .executableTarget(
            name: "mac-agent",
            dependencies: ["MacAgentCore"],
            path: "Sources/mac-agent"
        ),
        .testTarget(
            name: "MacAgentCoreTests",
            dependencies: ["MacAgentCore"],
            path: "Tests/MacAgentCoreTests"
        ),
    ]
)
