// swift-tools-version: 6.0
// LoweyCore — the pure-Swift heart of 3D-lowey.
// No RealityKit, no UIKit: it builds and tests on Linux, macOS and iPadOS alike.

import PackageDescription

let package = Package(
    name: "LoweyCore",
    platforms: [
        .iOS("26.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "LoweyCore", targets: ["LoweyCore"])
    ],
    targets: [
        .target(
            name: "LoweyCore",
            path: "Sources/LoweyCore",
            // Word → mouth shapes (from the CMU Pronouncing Dictionary, BSD; see THIRD_PARTY.md).
            resources: [.copy("Resources/visemes.txt")]
        ),
        .testTarget(
            name: "LoweyCoreTests",
            dependencies: ["LoweyCore"],
            path: "Tests/LoweyCoreTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
