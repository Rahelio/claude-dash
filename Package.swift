// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeDash",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeDash", path: "Sources/ClaudeDash")
    ]
)
