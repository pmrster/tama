// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tama",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "TamaCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Tama",
            dependencies: ["TamaCore"]
        ),
        .testTarget(
            name: "TamaCoreTests",
            dependencies: ["TamaCore"]
        ),
    ]
)
