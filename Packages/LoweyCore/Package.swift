// swift-tools-version: 6.0
// LoweyCore — the pure-Swift heart of 3D-lowey: model, commands, documents, geometry, motion, solvers.
// No UIKit, no Metal: it builds and tests on Linux, macOS and iPadOS alike.

import PackageDescription

let package = Package(
    name: "LoweyCore",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "LoweyCore", targets: ["LoweyCore"])
    ],
    dependencies: [
        .package(path: "../HmmKit")
    ],
    targets: [
        .target(
            name: "LoweyCore",
            dependencies: [
                .product(name: "HmmCommands", package: "HmmKit"),
                .product(name: "HmmDocuments", package: "HmmKit"),
                .product(name: "HmmTranscript", package: "HmmKit")
            ],
            path: "Sources/LoweyCore",
            // Word → mouth shapes (from the CMU Pronouncing Dictionary, BSD; see LICENSES.md).
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
