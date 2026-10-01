import AVFoundation
import HmmMedia
import LoweyCore
@testable import LoweyEngine
import UIKit
import XCTest

/// Exports of the Enigma sample end to end: stills through its cameras, determinism, both framings, PNG sequences
/// with transparency, the soundtrack, the whole narrated story, waiting while the app is away, and 3D files.
@MainActor
final class ExportTests: XCTestCase {
    private func attach(_ image: CGImage, name: String) {
        GoldenImage().attach(image, name: name)
    }

    func testEnigmaOpeningRendersThroughItsCameras() async throws {
        let session = try TestDocuments.session(TestDocuments.opening())
        let beats = [(1.0, "desk-push-in"), (5.0, "room-paper-grows"), (7.6, "big-x"), (9.8, "hero-robot"), (11.6, "question-mark")]
        for (time, beat) in beats {
            for (framing, label) in [(Framing.landscape, "16x9"), (.portrait, "9x16")] {
                let image = try await session.image(at: time, framing: framing, longSide: 640)
                XCTAssertEqual(max(image.width, image.height), 640)
                XCTAssertGreaterThan(GoldenImage.coverage(image).content, 0.03, "\(beat) \(label) looks blank")
                attach(image, name: "opening-\(beat)-\(label)")
            }
        }
    }

    func testExportIsDeterministic() async throws {
        let document = try TestDocuments.opening()
        let first = try await TestDocuments.session(document).image(at: 7.4, framing: .landscape, longSide: 320)
        let second = try await TestDocuments.session(document).image(at: 7.4, framing: .landscape, longSide: 320)
        GoldenImage(channelTolerance: 2).compare(first, second).differentFraction.assertBelow(0.001, "the same scene renders the same frame twice")
    }

    func testVideoExportWritesBothFramings() async throws {
        let session = try TestDocuments.session(TestDocuments.opening())
        let folder = try ImageChecks.temporaryFolder("video")
        for (framing, size) in [(Framing.landscape, CGSize(width: 480, height: 270)), (.portrait, CGSize(width: 270, height: 480))] {
            let settings = ExportSettings(framing: framing, longSide: 480, fps: 24, codec: .h264, range: TimeRange(start: 6.8, end: 7.8))
            var progress: [Double] = []
            let name = "opening-\(Int(size.width))x\(Int(size.height)).mp4"
            let url = try await session.video(settings, audio: nil, to: folder.appendingPathComponent(name)) {
                progress.append($0)
            }
            XCTAssertEqual(progress.last ?? 0, 1, accuracy: 1e-9)
            XCTAssertEqual(progress.count, settings.frameCount, "every frame reported")
            let asset = AVURLAsset(url: url)
            let track = try await XCTUnwrap(asset.loadTracks(withMediaType: .video).first)
            let natural = try await track.load(.naturalSize)
            XCTAssertEqual(natural.width, size.width)
            XCTAssertEqual(natural.height, size.height)
            // The video decodes (plays in Photos): grab a frame from the middle.
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let (frame, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
            attach(frame, name: "video-frame-\(Int(size.width))x\(Int(size.height))")
        }
    }

    func testPNGSequenceAndTransparentBackground() async throws {
        let session = try TestDocuments.session(TestDocuments.opening())
        let settings = ExportSettings(framing: .square, longSide: 256, fps: 12, codec: .h264, range: TimeRange(start: 10.5, end: 10.75),
                                      transparent: true)
        let folder = try await session.pngSequence(settings, audio: nil, to: ImageChecks.temporaryFolder("png")) { _ in }
        let frames = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".png") }
        XCTAssertEqual(frames.count, 3)
        let image = try XCTUnwrap(UIImage(contentsOfFile: folder.appendingPathComponent("frame_00003.png").path)?.cgImage)
        XCTAssertNotEqual(image.alphaInfo, .none)
        // One cube in an empty world: the background is see-through, the cube solid.
        var cube = SceneObject(id: "cube", name: "Cube", kind: .primitive(.cube), transform: Transform(scale: Vec3(1, 1, 1)))
        cube[.color] = .color(.rgba(RGBA(1, 0.5, 0.2)))
        var look = Look.default
        look.ground.visible = false
        let single = TestDocuments.document("Cube", objects: [cube], camera: Vec3(0, 0.5, 3), look: look)
        let matte = try await TestDocuments.session(single).image(at: 0, framing: .square, longSide: 128, transparent: true)
        let pixels = GoldenImage.rgba(matte)
        XCTAssertLessThan(pixels[3], 10, "the background is see-through")
        let center = (64 * 128 + 64) * 4
        XCTAssertGreaterThan(pixels[center + 3], 245, "the cube is solid")
        attach(matte, name: "transparent-cube")
    }

    func testVideoExportCarriesTheSoundtrack() async throws {
        let session = try TestDocuments.session(TestDocuments.opening())
        let rate = 48000.0
        let tone = (0 ..< Int(rate)).flatMap { index -> [Float] in
            let sample = Float(sin(Double(index) / rate * 2 * .pi * 440) * 0.3)
            return [sample, sample]
        }
        let settings = ExportSettings(framing: .landscape, longSide: 320, fps: 24, codec: .h264, range: TimeRange(start: 0, end: 1))
        let url = try await session.video(settings, audio: tone, to: ImageChecks.temporaryFolder("sound").appendingPathComponent("sound.mp4")) { _ in }
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1, "the soundtrack is in the video")
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 1, accuracy: 0.15)
    }

    /// The whole narrated story (the scene a 1.x device export once got stuck on), both framings, start to end.
    func testFullNarratedStoryExportsToTheEnd() async throws {
        executionTimeAllowance = 600
        let document = try TestDocuments.story()
        let duration = document.scene.timeline.duration
        let session = try TestDocuments.session(document)
        let folder = try ImageChecks.temporaryFolder("story")
        for (framing, name) in [(Framing.landscape, "story-16x9.mp4"), (.portrait, "story-9x16.mp4")] {
            let settings = ExportSettings(framing: framing, longSide: 320, fps: 10, codec: .h264, range: TimeRange(start: 0, end: duration))
            var reported = 0
            let url = try await session.video(settings, audio: nil, to: folder.appendingPathComponent(name)) { _ in
                reported += 1
            }
            XCTAssertEqual(reported, settings.frameCount, "every frame reported")
            let seconds = try await AVURLAsset(url: url).load(.duration).seconds
            XCTAssertEqual(seconds, Double(settings.frameCount) / 10, accuracy: 0.25)
        }
    }

    /// iOS suspends GPU work in the background: the export holds, says so, and carries on when the app is back.
    func testExportWaitsWhileTheAppIsAwayThenFinishes() async throws {
        let session = try TestDocuments.session(TestDocuments.opening())
        let app = AppPresence()
        session.canRender = { app.inFront }
        session.onWaiting = { app.waits.append($0) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            app.inFront = true
        }
        let started = Date()
        let settings = ExportSettings(framing: .landscape, longSide: 160, fps: 10, codec: .h264, range: TimeRange(start: 0, end: 0.5))
        let url = try await session.video(settings, audio: nil, to: ImageChecks.temporaryFolder("away").appendingPathComponent("away.mp4")) { _ in }
        XCTAssertEqual(app.waits, [true, false], "it said it was waiting, then that it resumed")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.9, "nothing rendered while away")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSceneExportsAsGLBAndUSDZ() throws {
        let (info, scenes) = try EnigmaSample.build()
        let cave = scenes[2]
        let meshes = ModelExport.meshes(nil, scene: cave, look: cave.look ?? info.look, catalog: .empty, models: ModelLibrary())
        XCTAssertGreaterThan(meshes.count, 20)
        let glb = ModelExport.data(.glb, meshes: meshes)
        XCTAssertEqual(glb.prefix(4), Data("glTF".utf8))
        let folder = try ImageChecks.temporaryFolder("model")
        try glb.write(to: folder.appendingPathComponent("cave.glb"))
        let usdz = ModelExport.data(.usdz, meshes: meshes)
        XCTAssertEqual(usdz.prefix(2), Data("PK".utf8), "a zip package")
        XCTAssertGreaterThan(usdz.count, 1000)
        // The .glb reads back through the importer as the same number of parts.
        let model = try GLTFMeshReader.model(data: glb)
        XCTAssertEqual(model.parts.count, meshes.count)
    }
}

/// Stands in for the app's foreground state in the export tests.
@MainActor
private final class AppPresence {
    var inFront = false
    var waits: [Bool] = []
}

extension Double {
    func assertBelow(_ limit: Double, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(self, limit, message, file: file, line: line)
    }
}
