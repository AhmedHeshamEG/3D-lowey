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
        .library(name: "HmmStore", targets: ["HmmStore"]),
        .library(name: "HmmBrush", targets: ["HmmBrush"]),
        .library(name: "HmmBoard", targets: ["HmmBoard"]),
        .library(name: "HmmBrushRender", targets: ["HmmBrushRender"]),
        .library(name: "HmmBoardUI", targets: ["HmmBoardUI"])
    ],
    targets: [
        .target(name: "HmmDesign"),
        .target(name: "HmmCommands"),
        .target(name: "HmmDocuments", dependencies: ["HmmDesign", "HmmCommands"]),
        .target(name: "HmmTranscript"),
        // Async API runs on the caller's actor (an export loop on the main actor can await the encoder it owns).
        .target(name: "HmmMedia", swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .target(name: "HmmBridge", dependencies: ["HmmDesign"]),
        .target(name: "HmmPerception", dependencies: ["HmmMedia"]),
        .target(name: "HmmDiagnostics", dependencies: ["HmmDesign"]),
        .target(name: "HmmStore"),
        // The brush engine's arithmetic: brushes, strokes into stamps, the built-in tips and grains.
        .target(name: "HmmBrush", dependencies: ["HmmDocuments"]),
        // The Schizzo board's model: items, commands, the view, the board on disk.
        .target(name: "HmmBoard", dependencies: ["HmmBrush", "HmmCommands", "HmmDocuments"]),
        // The brush engine on the GPU (Metal): the stamp shader, the stamper, tip and grain textures.
        .target(name: "HmmBrushRender", dependencies: ["HmmBrush"], resources: [.process("Shaders")]),
        // The board on screen: its Metal renderer, the canvas view, the SwiftUI screen.
        .target(name: "HmmBoardUI", dependencies: ["HmmBoard", "HmmBrush", "HmmBrushRender", "HmmCommands", "HmmDesign", "HmmDocuments"]),
        .testTarget(name: "HmmCommandsTests", dependencies: ["HmmCommands"]),
        .testTarget(name: "HmmDocumentsTests", dependencies: ["HmmDocuments", "HmmCommands"]),
        .testTarget(name: "HmmTranscriptTests", dependencies: ["HmmTranscript"]),
        .testTarget(name: "HmmBridgeTests", dependencies: ["HmmBridge"]),
        .testTarget(name: "HmmDiagnosticsTests", dependencies: ["HmmDiagnostics"]),
        .testTarget(name: "HmmPerceptionTests", dependencies: ["HmmPerception"]),
        .testTarget(name: "HmmMediaTests", dependencies: ["HmmMedia"]),
        .testTarget(name: "HmmDesignTests", dependencies: ["HmmDesign"]),
        .testTarget(name: "HmmBrushTests", dependencies: ["HmmBrush"]),
        .testTarget(name: "HmmBoardTests", dependencies: ["HmmBoard", "HmmBrush", "HmmCommands", "HmmDocuments"]),
        .testTarget(name: "HmmBoardUITests", dependencies: ["HmmBoardUI", "HmmBoard", "HmmBrush", "HmmBrushRender"])
    ],
    swiftLanguageModes: [.v6]
)
