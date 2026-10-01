import AVFoundation
import CoreGraphics
import HmmMedia
import LoweyCore
@testable import LoweyEngine
import XCTest

/// LoweyRender 2 on the simulator's GPU: every Look in a day and a night mood against golden images, a 1.x project
/// opened in this version, picking from the ID buffer, GPU skinning, and the preview being the export.
@MainActor
final class RenderTests: XCTestCase {
    static let size = (width: 640, height: 360)
    private var device: RenderDevice!
    private var models: ModelLibrary!

    override func setUp() async throws {
        device = try RenderDevice.sharedDevice()
        models = ModelLibrary()
        MarketBenchmark.seed(models)
    }

    private func render(_ document: Document, at time: Double = 0, catalog: AssetCatalog = .empty,
                        width: Int = size.width, height: Int = size.height) async throws -> (CGImage, FrameRenderer, FrameRequest) {
        let frames = try FrameRenderer(device: device, models: models)
        let builder = ShotBuilder(document: document, catalog: catalog, models: models)
        let request = builder.request(at: time, framing: .landscape, size: CGSize(width: width, height: height),
                                      frameIndex: builder.timeline.frame(for: time))
        return try await (frames.image(request, width: width, height: height), frames, request)
    }

    // MARK: Golden images

    func testEveryLookInDayAndNight() async throws {
        let golden = GoldenImage()
        for preset in LookPreset.builtIns {
            for mood in [LightingPreset.day, .night] {
                let (image, _, _) = try await render(TestScenes.lookCheck(look: preset.id, mood: mood))
                let coverage = GoldenImage.coverage(image)
                XCTAssertGreaterThan(coverage.content, 0.08, "\(preset.id) \(mood): the objects are drawn")
                try golden.assertMatches(image, named: "look-\(preset.id)-\(mood.rawValue)")
            }
        }
    }

    func testAVersion1ProjectOpensInClayAndRendersAsBefore() async throws {
        let document = try TestScenes.migratedV1()
        XCTAssertEqual(document.project.look.presetID, LookPreset.clay.id)
        let (image, _, _) = try await render(document)
        try GoldenImage().assertMatches(image, named: "migrated-v1")
    }

    func testLooksLookDifferent() async throws {
        let (ink, _, _) = try await render(TestScenes.lookCheck(look: LookPreset.ink.id, mood: .day))
        let (clay, _, _) = try await render(TestScenes.lookCheck(look: LookPreset.clay.id, mood: .day))
        let result = GoldenImage().compare(ink, clay)
        XCTAssertGreaterThan(result.differentFraction, 0.02, "Ink draws lines, Clay doesn't")
    }

    // MARK: Picking

    func testPickingFindsTheObjectUnderAPixel() async throws {
        let document = TestScenes.lookCheck(look: LookPreset.ink.id, mood: .day)
        let (_, frames, request) = try await render(document)
        let size = CGSize(width: Self.size.width, height: Self.size.height)
        for name in ["Cube", "Sphere", "Cylinder"] {
            let object = try XCTUnwrap(document.scene.objects.values.first { $0.name == name })
            let center = object.transform.position + Vec3(0, object.transform.scale.y / 2, 0)
            let point = try XCTUnwrap(request.camera.project(center, in: size))
            let hit = try XCTUnwrap(frames.renderer.pick(at: SIMD2(Int(point.x), Int(point.y)), radius: 2), name)
            XCTAssertEqual(hit.object, object.id, name)
            XCTAssertLessThan((hit.point - center).length, max(object.transform.scale.x, object.transform.scale.z), "\(name): on its surface")
        }
        XCTAssertNil(frames.renderer.pick(at: SIMD2(4, 4), radius: 2), "the sky picks nothing")
        let cube = try XCTUnwrap(document.scene.objects.values.first { $0.name == "Cube" })
        let bounds = try XCTUnwrap(frames.renderer.visualBounds(of: [cube.id]))
        XCTAssertEqual(bounds.size.y, 1, accuracy: 0.05)
    }

    // MARK: Skinning

    func testWalkersAreSkinnedOnTheGPU() async throws {
        let catalog = MarketBenchmark.catalog
        let document = TestScenes.walker()
        let (still, _, _) = try await render(document, at: 0, catalog: catalog)
        let (stride, _, _) = try await render(document, at: 0.25, catalog: catalog)
        XCTAssertGreaterThan(GoldenImage.coverage(still).content, 0.05, "the walker is drawn, not a placeholder")
        XCTAssertGreaterThan(GoldenImage().compare(still, stride).differentFraction, 0.01, "the pose moves the mesh")
        try GoldenImage().assertMatches(stride, named: "walker-stride")
    }

    // MARK: Preview = export

    /// The stage's frame (the same renderer at full scale, no editor layer) and the frame an exported video holds.
    func testThePreviewIsTheExport() async throws {
        let document = TestScenes.lookCheck(look: LookPreset.comic.id, mood: .day)
        let (preview, _, _) = try await render(document, at: 0.5)
        let session = try ExportSession(document: document, catalog: .empty, device: device, models: models)
        var settings = ExportPreset.hd1080.settings(range: TimeRange(start: 0.5, end: 0.6), fps: 30)
        settings.longSide = Self.size.width
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-export.mp4")
        try? FileManager.default.removeItem(at: url)
        _ = try await session.video(settings, audio: nil, to: url) { _ in }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: .zero).image
        let still = try await session.image(at: 0.5, framing: .landscape, longSide: Self.size.width)
        XCTAssertEqual(GoldenImage().compare(preview, still).differentFraction, 0, "a still is the preview, pixel for pixel")
        var video = GoldenImage()
        video.channelTolerance = 40
        video.maxDifferentFraction = 0.03
        let result = video.compare(preview, frame)
        XCTAssertLessThan(result.differentFraction, 0.03, "the video frame matches the preview within compression")
    }
}
