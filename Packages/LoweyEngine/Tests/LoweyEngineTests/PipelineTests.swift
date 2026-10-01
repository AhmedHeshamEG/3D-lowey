import HmmDiagnostics
import HmmMedia
import LoweyCore
@testable import LoweyEngine
import XCTest

/// The benchmark and the export pipeline end to end (the timing numbers that count come from the device; here they
/// only have to be produced and written).
@MainActor
final class PipelineTests: XCTestCase {
    func testNightMarketBenchmarkRunsAndWritesItsReport() async throws {
        let models = ModelLibrary()
        let benchmark = MarketBenchmark(models: models, duration: 1)
        try await benchmark.runOffscreen(frames: 24, width: 1280, height: 720, device: RenderDevice.sharedDevice())
        let report = benchmark.report(appVersion: "test", device: "Simulator", system: "iOS")
        XCTAssertEqual(report.frames, 24)
        XCTAssertGreaterThan(report.p95, 0)
        XCTAssertGreaterThanOrEqual(report.sceneFacts["objects"] ?? 0, 380)
        XCTAssertGreaterThan(report.sceneFacts["triangles"] ?? 0, 10000, "the market is drawn, walkers included")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("benchmarks")
        let url = try MarketBenchmark.write(report, to: folder)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let read = try decoder.decode(BenchmarkReport.self, from: Data(contentsOf: url))
        XCTAssertEqual(read.scene, NightMarket.projectName)
        XCTAssertEqual(url.lastPathComponent, "benchmark-Simulator-test.json")
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testBenchmarkStageFramesHideTheEditorLayer() {
        let benchmark = MarketBenchmark(models: ModelLibrary(), duration: 1)
        let frame = benchmark.frame(size: CGSize(width: 1180, height: 820), renderScale: 0.8)
        XCTAssertEqual(frame.request.renderScale, 0.8)
        XCTAssertEqual(frame.request.editor?.showsGrid, false)
        XCTAssertNotNil(frame.shotCamera, "the benchmark looks through the dolly")
        XCTAssertFalse(benchmark.record(frameTime: 1.0 / 120, renderScale: 1, report: nil))
    }

    /// The 4K spike: one second at 3840 × 2160, rendered straight into IOSurface pixel buffers and verified like every
    /// export. HEVC on a device; the simulator's software encoder has no 4K HEVC, so there it checks the same 4K
    /// pipeline with H.264 (HEVC 4K is on the device checklist).
    func testFourKExportIsVerified() async throws {
        let document = TestScenes.lookCheck(look: LookPreset.sketch.id, mood: .goldenHour)
        let session = try ExportSession(document: document, catalog: .empty, device: RenderDevice.sharedDevice(), models: ModelLibrary())
        var settings = ExportPreset.youtube4K.settings(range: TimeRange(start: 0, end: 1), fps: 30)
        #if targetEnvironment(simulator)
            settings.codec = .h264
        #endif
        XCTAssertEqual(settings.size.width, 3840)
        XCTAssertEqual(settings.size.height, 2160)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("spike-4k.mp4")
        try? FileManager.default.removeItem(at: url)
        var progress = 0.0
        _ = try await session.video(settings, audio: nil, to: url) { progress = $0 }
        XCTAssertEqual(progress, 1)
        let problems = try await MediaInspector.verify(url, expected: ExportExpectation(duration: 1, frameCount: 30, width: 3840, height: 2160,
                                                                                         audio: false, alpha: false))
        XCTAssertEqual(problems, [])
    }

    func testStillsSequencesAndGIFs() async throws {
        let document = TestScenes.lookCheck(look: LookPreset.lowPoly.id, mood: .dusk)
        let session = try ExportSession(document: document, catalog: .empty, device: RenderDevice.sharedDevice(), models: ModelLibrary())
        var settings = ExportPreset.gifLoop.settings(range: TimeRange(start: 0, end: 0.4), fps: 10)
        settings.longSide = 320
        let gif = FileManager.default.temporaryDirectory.appendingPathComponent("loop.gif")
        _ = try await session.gif(settings, to: gif) { _ in }
        XCTAssertGreaterThan(try Data(contentsOf: gif).count, 1000)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sequence")
        _ = try await session.pngSequence(settings, audio: [Float](repeating: 0, count: 9600), to: folder) { _ in }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(files.filter { $0.hasSuffix(".png") }.count, settings.frameCount)
        XCTAssertTrue(files.contains("soundtrack.wav"))
        let still = try await session.image(at: 0, framing: .square, longSide: 512, transparent: true)
        XCTAssertEqual(still.width, 512)
        XCTAssertEqual(still.height, 512)
    }

    func testDynamicScaleDropsUnderLoadAndRecovers() {
        var scale = DynamicScale(budget: 1.0 / 120)
        for _ in 0 ..< 20 {
            _ = scale.update(gpuTime: 0.012, thermal: .nominal)
        }
        XCTAssertEqual(scale.scale, DynamicScale.minimum, accuracy: 0.001)
        for _ in 0 ..< 400 {
            _ = scale.update(gpuTime: 0.002, thermal: .nominal)
        }
        XCTAssertEqual(scale.scale, 1, accuracy: 0.001)
        XCTAssertEqual(scale.update(gpuTime: 0.002, thermal: .serious), 0.75, accuracy: 0.001, "a hot device caps the scale")
        scale.enabled = false
        XCTAssertEqual(scale.update(gpuTime: 0.05, thermal: .critical), 1)
    }
}
