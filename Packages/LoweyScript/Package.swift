// swift-tools-version: 6.0
// LoweyScript — the programmatic layer: JavaScript (JavaScriptCore) driving the same command API
// as the UI. iPadOS/macOS only (JavaScriptCore); its tests run in the app's test bundle.

import PackageDescription

let package = Package(
    name: "LoweyScript",
    platforms: [
        .iOS("26.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "LoweyScript", targets: ["LoweyScript"])
    ],
    dependencies: [
        .package(path: "../LoweyCore")
    ],
    targets: [
        .target(
            name: "LoweyScript",
            dependencies: ["LoweyCore"],
            path: "Sources/LoweyScript"
        )
    ],
    swiftLanguageModes: [.v6]
)
