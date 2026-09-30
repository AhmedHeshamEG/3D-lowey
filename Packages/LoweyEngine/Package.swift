// swift-tools-version: 6.0
// LoweyEngine — LoweyRender 2 (the Metal renderer), model import, export, the stage view, audio, face capture and
// scripting. Apple frameworks allowed; everything above it (features, app) talks to it through Core types.

import PackageDescription

let package = Package(
    name: "LoweyEngine",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .library(name: "LoweyEngine", targets: ["LoweyEngine"])
    ],
    dependencies: [
        .package(path: "../LoweyCore"),
        .package(path: "../HmmKit")
    ],
    targets: [
        .target(
            name: "LoweyEngine",
            dependencies: [
                "LoweyCore",
                .product(name: "HmmMedia", package: "HmmKit"),
                .product(name: "HmmDiagnostics", package: "HmmKit"),
                .product(name: "HmmPerception", package: "HmmKit"),
                .product(name: "HmmTranscript", package: "HmmKit")
            ],
            path: "Sources/LoweyEngine",
            // The Metal shaders are compiled by Xcode into this module's default library.
            resources: [.process("Shaders")]
        ),
        .testTarget(
            name: "LoweyEngineTests",
            dependencies: ["LoweyEngine"],
            path: "Tests/LoweyEngineTests",
            resources: [.copy("Golden")]
        )
    ],
    swiftLanguageModes: [.v6]
)
