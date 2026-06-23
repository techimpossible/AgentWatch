// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentWatch",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "AgentWatch",
            path: "Sources/AgentWatch"
        )
    ]
)
