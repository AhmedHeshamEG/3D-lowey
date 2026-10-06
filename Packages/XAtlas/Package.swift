// swift-tools-version: 6.0
// xatlas (MIT, https://github.com/jpcy/xatlas, commit f700c77) vendored as C++ with a small C face, so models unwrap
// for painting the same on iPadOS and in the Linux test container. See LICENSE-xatlas.txt and VENDORED.md.

import PackageDescription

let package = Package(
    name: "XAtlas",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "XAtlasCpp", targets: ["XAtlasCpp"])
    ],
    targets: [
        .target(
            name: "XAtlasCpp",
            path: "Sources/XAtlasCpp",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("xatlas-src"),
                // Single-threaded and without its debug checks: the same mesh unwraps the same way everywhere.
                .define("XA_MULTITHREADED", to: "0"),
                .define("XA_DEBUG", to: "0"),
                .define("XA_DEBUG_ASSERT(exp)", to: "((void)0)")
            ]
        ),
        .testTarget(
            name: "XAtlasTests",
            dependencies: ["XAtlasCpp"],
            path: "Tests/XAtlasTests"
        )
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
