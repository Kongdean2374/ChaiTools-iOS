// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ChaiToolsCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ChaiToolsCore", targets: ["ChaiToolsCore"])],
    targets: [
        .target(name: "ChaiToolsCore", path: "Shared", exclude: ["Keychain.swift", "WorkspaceModel.swift"]),
        .testTarget(name: "ChaiToolsCoreTests", dependencies: ["ChaiToolsCore"], path: "Tests")
    ]
)
