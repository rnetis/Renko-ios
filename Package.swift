// swift-tools-version:5.9
import PackageDescription

// Test harness only. The app itself is generated from project.yml (XcodeGen);
// this package compiles the pure-Foundation core (engine, analysis, models)
// so it can be unit-tested with a plain `swift test`, no simulator needed.
let package = Package(
    name: "RenkoCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "RenkoCore", targets: ["RenkoCore"]),
    ],
    targets: [
        .target(
            name: "RenkoCore",
            path: "Sources/ToobitRenko",
            exclude: [
                "App", "Views", "Services", "Networking", "Support",
                "Assets.xcassets",
            ],
            sources: ["Engine", "Models"]
        ),
        .testTarget(
            name: "RenkoCoreTests",
            dependencies: ["RenkoCore"],
            path: "Tests/RenkoCoreTests"
        ),
    ]
)
