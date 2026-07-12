// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tama",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "tama-cli", targets: ["TamaCLI"]),
    ],
    targets: [
        .target(
            name: "TamaCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Tama",
            dependencies: ["TamaCore"]
        ),
        .executableTarget(
            name: "TamaCLI",
            dependencies: ["TamaCore"]
        ),
        .testTarget(
            name: "TamaCoreTests",
            dependencies: ["TamaCore"]
        ),
    ]
)
