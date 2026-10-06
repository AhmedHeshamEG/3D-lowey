import CoreGraphics
import Foundation
import HmmDiagnostics
import LoweyCore
import QuartzCore

/// What the benchmark stage runs: a frame for each moment, every presented frame recorded, then the report.
@MainActor
public protocol StageBenchmark: AnyObject {
    /// The work before the run (laying a model flat for painting); the stage starts after it.
    func prepare() async throws
    func frame(size: CGSize, renderScale: Float) -> StageFrame
    /// Feeds one presented frame; true once the run is over.
    func record(frameTime: Double, renderScale: Float, report: FrameReport?) -> Bool
    func report(appVersion: String, device: String, system: String) -> BenchmarkReport
}

extension MarketBenchmark: StageBenchmark {
    public func prepare() async throws {}
}

/// Diagnostics ▸ Run the painting benchmark (M6's gate): a scripted Pencil paints a ~50k-triangle model for twenty
/// seconds; every frame draws the stroke into the model's layer, composites it and shades the scene, as painting
/// does. Each presented frame is recorded against the same targets as the Night Market.
@MainActor
public final class PaintBenchmark: StageBenchmark {
    public let tier: DeviceTier
    public let builder: ShotBuilder
    public private(set) var recorder: BenchmarkRecorder
    private var started: CFTimeInterval?
    private var lastReport: FrameReport?
    private let brush = BuiltInBrushes.inkPen

    public init(models: ModelLibrary = .shared, duration: Double = PaintBenchmarkScene.duration, tier: DeviceTier = .a, budget: Double = 1.0 / 120.0) {
        self.tier = tier
        models.seed(PaintBenchmarkScene.assetID, model: PaintBenchmarkScene.model(), rig: nil)
        builder = ShotBuilder(document: PaintBenchmarkScene.document(), catalog: Self.catalog, models: models)
        recorder = BenchmarkRecorder(duration: duration, budget: budget, target: MarketBenchmark.target(tier: tier, budget: budget))
    }

    public static let catalog = AssetCatalog(manifest: LibraryManifest(assets: [PaintBenchmarkScene.asset])) { _ in
        URL(fileURLWithPath: "/dev/null")
    }

    /// Lays the model flat (off the main thread) and gives it one empty layer to paint, its files kept in memory.
    public func prepare() async throws {
        let model = PaintBenchmarkScene.model()
        guard let merged = AssetPaint.mergedMesh(model) else { return }
        let prepared = try await Task.detached(priority: .userInitiated) {
            try PaintOperations.prepare(mesh: merged, keepOwnUVs: false)
        }.value
        let files = prepared.files
        builder.document.scene.objects[PaintBenchmarkScene.objectID]?.paint = prepared.paint
        builder.paintFile = { files[$0] }
    }

    /// The scripted Pencil's stroke so far, in the frame's pixels.
    func livePaint(at time: Double, size: CGSize) -> LivePaint? {
        let (stroke, samples) = PaintBenchmarkScene.pencil(at: time)
        let inputs = samples.enumerated().map { index, sample in
            BrushInput(point: Vec2(sample.point.x * Double(size.width), sample.point.y * Double(size.height)), pressure: sample.pressure,
                       time: Double(index) / PaintBenchmarkScene.sampleRate)
        }
        let path = BrushStroker.path(inputs, brush: brush, size: Double(size.height) * 0.02, opacity: 0.9, minimumSpacing: 1.5)
        let dabs = BrushStroker.dabs(path, brush: brush, seed: UInt64(stroke + 1))
        let color = stroke % 2 == 0 ? RGBA(0.85, 0.25, 0.2) : RGBA(0.2, 0.35, 0.85)
        return LivePaint(object: PaintBenchmarkScene.objectID, layer: "l1", stroke: stroke + 1, source: .stamps(dabs, brush: brush), color: color,
                         erases: false, pixelsPerPoint: 1)
    }

    public var elapsed: Double {
        guard let started else { return 0 }
        return CACurrentMediaTime() - started
    }

    public func frame(size: CGSize, renderScale: Float) -> StageFrame {
        if started == nil { started = CACurrentMediaTime() }
        var request = builder.request(at: 0, framing: .landscape, size: size, frameIndex: 0, renderScale: renderScale)
        request.livePaint = livePaint(at: elapsed, size: size)
        var editor = EditorScene()
        editor.showsGrid = false
        editor.showsSelection = false
        request.editor = editor
        return StageFrame(request: request, shotCamera: request.camera)
    }

    @discardableResult
    public func record(frameTime: Double, renderScale: Float, report: FrameReport?) -> Bool {
        if let report { lastReport = report }
        guard frameTime > 0 else { return false }
        return recorder.frame(duration: frameTime, at: CACurrentMediaTime(), renderScale: Double(renderScale), thermal: .current,
                              memoryMB: MarketBenchmark.memoryFootprintMB())
    }

    /// Paints `frames` frames back to back away from the screen (tests, CI's smoke run), timing each.
    public func runOffscreen(frames count: Int, width: Int, height: Int, device: RenderDevice) async throws {
        let renderer = try FrameRenderer(device: device, models: builder.models)
        let size = CGSize(width: width, height: height)
        var clock = CACurrentMediaTime()
        for index in 0 ..< count {
            let time = Double(index) / 120
            var request = builder.request(at: 0, framing: .landscape, size: size, frameIndex: index)
            request.editor = nil
            request.livePaint = livePaint(at: time, size: size)
            lastReport = try await renderer.render(request, width: width, height: height)
            let now = CACurrentMediaTime()
            _ = recorder.frame(duration: now - clock, at: time, renderScale: 1, thermal: .current, memoryMB: MarketBenchmark.memoryFootprintMB())
            clock = now
        }
    }

    /// Writes the report as `benchmark-paint-<device>-<version>.json` (beside the Night Market's) into `folder`.
    public static func write(_ report: BenchmarkReport, to folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(report.fileName.replacingOccurrences(of: "benchmark-", with: "benchmark-paint-"))
        try report.json().write(to: url, options: .atomic)
        return url
    }

    public func report(appVersion: String, device: String, system: String) -> BenchmarkReport {
        var facts: [String: Double] = ["paintTextureSize": Double(PaintSurface.defaultSize)]
        if let lastReport {
            facts["triangles"] = Double(lastReport.triangles)
            facts["drawCalls"] = Double(lastReport.drawCalls)
        }
        facts["tier"] = Double(DeviceTier.allCases.firstIndex(of: tier) ?? 0) + 1
        let scene = tier == .a ? PaintBenchmarkScene.projectName : "\(PaintBenchmarkScene.projectName) (Tier \(tier.rawValue) preview)"
        return recorder.report(app: "Maquette", appVersion: appVersion, scene: scene, device: device, system: system, sceneFacts: facts)
    }
}
