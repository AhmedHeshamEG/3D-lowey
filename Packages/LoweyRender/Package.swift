// swift-tools-version: 6.0
// LoweyRender — the RealityKit bridge: turns LoweyCore scenes into entities and keeps them in sync.

import PackageDescription

let package = Package(
    name: "LoweyRender",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .library(name: "LoweyRender", targets: ["LoweyRender"])
    ],
    dependencies: [
        .package(path: "../LoweyCore"),
        // glTF / GLB → RealityKit. MIT license (see THIRD_PARTY.md).
        .package(url: "https://github.com/warrenm/GLTFKit2", from: "0.5.15")
    ],
    targets: [
        .target(
            name: "LoweyRender",
            dependencies: [
                "LoweyCore",
                .product(name: "GLTFKit2", package: "GLTFKit2")
            ],
            path: "Sources/LoweyRender",
            // The Metal surface shader (Shaders/) is compiled by Xcode into this module's bundle.
            resources: [.process("Resources")]
        )
    ],
    swiftLanguageModes: [.v6]
)
