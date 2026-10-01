// swift-tools-version: 6.0
// LoweyFeatures — every screen of the app, one folder per feature (Theater, Stage, Timeline, Build, Draw, Look,
// Inspector, Animate, Camera, Cast, Audio, Library, Export, Bridge, Diagnostics, Settings, Onboarding, Scripts, Face).
// Features never reference each other's types: they share the Workspace (the open project, the editor session, the
// library) and talk through Core types. Tools/check-feature-boundaries.py enforces it in CI.

import PackageDescription

let package = Package(
    name: "LoweyFeatures",
    defaultLocalization: "en",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .library(name: "LoweyFeatures", targets: ["LoweyFeatures"])
    ],
    dependencies: [
        .package(path: "../LoweyEngine"),
        .package(path: "../LoweyCore"),
        .package(path: "../HmmKit")
    ],
    targets: [
        .target(
            name: "LoweyFeatures",
            dependencies: [
                "LoweyEngine",
                "LoweyCore",
                .product(name: "HmmDesign", package: "HmmKit"),
                .product(name: "HmmCommands", package: "HmmKit"),
                .product(name: "HmmDocuments", package: "HmmKit"),
                .product(name: "HmmBridge", package: "HmmKit"),
                .product(name: "HmmDiagnostics", package: "HmmKit"),
                .product(name: "HmmTranscript", package: "HmmKit"),
                .product(name: "HmmMedia", package: "HmmKit"),
                .product(name: "HmmPerception", package: "HmmKit")
            ],
            path: "Sources/LoweyFeatures"
        ),
        .testTarget(
            name: "LoweyFeaturesTests",
            dependencies: ["LoweyFeatures"],
            path: "Tests/LoweyFeaturesTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
