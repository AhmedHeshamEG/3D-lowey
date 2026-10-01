// swift-tools-version: 6.0
// hmm-kit — the shared foundation of the hmm. studio apps (3D-lowey, Retake, Editoro).
//
// Every module builds on Linux: Apple-only code (SwiftUI, UIKit, AVFoundation, Network, Speech, StoreKit…) sits
// behind `#if canImport(...)`, so the pure parts (commands, documents, transcripts, bridge protocol, statistics)
// are unit-tested on Linux in seconds and the rest in the iOS simulator.

import PackageDescription

let package = Package(
    name: "HmmKit",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "HmmDesign", targets: ["HmmDesign"]),
        .library(name: "HmmCommands", targets: ["HmmCommands"]),
        .library(name: "HmmDocuments", targets: ["HmmDocuments"]),
        .library(name: "HmmTranscript", targets: ["HmmTranscript"]),
        .library(name: "HmmMedia", targets: ["HmmMedia"]),
        .library(name: "HmmBridge", targets: ["HmmBridge"]),
        .library(name: "HmmPerception", targets: ["HmmPerception"]),
        .library(name: "HmmDiagnostics", targets: ["HmmDiagnostics"]),
        .library(name: "HmmStore", targets: ["HmmStore"])
    ],
    targets: [
        .target(name: "HmmDesign"),
        .target(name: "HmmCommands"),
        .target(name: "HmmDocuments", dependencies: ["HmmDesign"]),
        .target(name: "HmmTranscript"),
        // Async API runs on the caller's actor (an export loop on the main actor can await the encoder it owns).
        .target(name: "HmmMedia", swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .target(name: "HmmBridge", dependencies: ["HmmDesign"]),
        .target(name: "HmmPerception", dependencies: ["HmmMedia"]),
        .target(name: "HmmDiagnostics", dependencies: ["HmmDesign"]),
        .target(name: "HmmStore"),
        .testTarget(name: "HmmCommandsTests", dependencies: ["HmmCommands"]),
        .testTarget(name: "HmmDocumentsTests", dependencies: ["HmmDocuments"]),
        .testTarget(name: "HmmTranscriptTests", dependencies: ["HmmTranscript"]),
        .testTarget(name: "HmmBridgeTests", dependencies: ["HmmBridge"]),
        .testTarget(name: "HmmDiagnosticsTests", dependencies: ["HmmDiagnostics"]),
        .testTarget(name: "HmmPerceptionTests", dependencies: ["HmmPerception"]),
        .testTarget(name: "HmmMediaTests", dependencies: ["HmmMedia"]),
        .testTarget(name: "HmmDesignTests", dependencies: ["HmmDesign"])
    ],
    swiftLanguageModes: [.v6]
)
