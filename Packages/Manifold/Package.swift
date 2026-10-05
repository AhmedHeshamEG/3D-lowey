// swift-tools-version: 6.0
// Manifold (Apache-2.0, https://github.com/elalish/manifold, v3.5.4) vendored as C++ with a small C face,
// so booleans run the same on iPadOS and in the Linux test container. See LICENSE-manifold.txt and VENDORED.md.

import PackageDescription

let package = Package(
    name: "Manifold",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "ManifoldCpp", targets: ["ManifoldCpp"])
    ],
    targets: [
        .target(
            name: "ManifoldCpp",
            path: "Sources/ManifoldCpp",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("manifold-include"),
                .headerSearchPath("manifold-src"),
                .define("MANIFOLD_PAR", to: "-1"),
                .define("MANIFOLD_NO_IOSTREAM"),
                .define("MANIFOLD_NO_FILESYSTEM")
            ]
        ),
        .testTarget(
            name: "ManifoldTests",
            dependencies: ["ManifoldCpp"],
            path: "Tests/ManifoldTests"
        )
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
