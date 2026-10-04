import CoreGraphics
import Foundation
import HmmDiagnostics
import LoweyCore
import QuartzCore

/// Diagnostics ▸ Run benchmark: plays the Night Market for 20 seconds on the stage at full speed, records every
/// presented frame and writes the JSON report. The walkers are seeded into the model library, so nothing is read
/// from disk and every run draws the same frames.
@MainActor
public final class MarketBenchmark {
    /// On ProMotion at Tier A: p95 ≤ 10 ms between presented frames at render scale ≥ 0.85, no hitch over 33 ms.
    public static let target = target(tier: .a, budget: 1.0 / 120.0)

    /// The pass rule for a tier on a screen. Frames are timed present to present, so a perfect run sits at the
    /// screen's own interval (8.3 ms at 120 Hz, 16.7 ms at 60 Hz) with vsync jitter around it, and a dropped frame
    /// doubles it: p95 within 1.2 intervals means no frame was dropped. The render scale must stay near the top of
    /// the tier's preview range (0.85 at Tier A), and no hitch over 33 ms.
    public static func target(tier: DeviceTier, budget: Double) -> BenchmarkTarget {
        let range = PreviewQuality(tier: tier).renderScale
        let minimumScale = range.lowerBound + (range.upperBound - range.lowerBound) * 0.55
        return BenchmarkTarget(p95Milliseconds: (budget * 1.2 * 1000 * 10).rounded() / 10, minimumRenderScale: Double((minimumScale * 100).rounded() / 100))
    }

    /// The tier whose preview this run uses (Tier B on an M iPad shows how a recent A-chip iPad will feel).
    public let tier: DeviceTier
    public let document: Document
    public let catalog: AssetCatalog
    public let builder: ShotBuilder
    public private(set) var recorder: BenchmarkRecorder
    private var started: CFTimeInterval?
    private var lastReport: FrameReport?

    public init(models: ModelLibrary = .shared, duration: Double = NightMarket.duration, tier: DeviceTier = .a, budget: Double = 1.0 / 120.0) {
        self.tier = tier
        let (info, scene) = NightMarket.build()
        document = Document(project: info, scene: scene)
        catalog = Self.catalog
        Self.seed(models)
        builder = ShotBuilder(document: document, catalog: catalog, models: models)
        recorder = BenchmarkRecorder(duration: duration, budget: budget, target: Self.target(tier: tier, budget: budget))
    }

    /// The benchmark's catalog: just the generated walker.
    public static let catalog = AssetCatalog(manifest: LibraryManifest(assets: [BenchmarkFigure.asset])) { _ in
        URL(fileURLWithPath: "/dev/null")
    }

    /// Puts the generated walker into a model library (idempotent).
    public static func seed(_ models: ModelLibrary) {
        models.seed(BenchmarkFigure.asset.id, model: BenchmarkFigure.model(), rig: BenchmarkFigure.rig())
    }

    /// Seconds since the first frame (the scene's playback time).
    public var elapsed: Double {
        guard let started else { return 0 }
        return CACurrentMediaTime() - started
    }

    public var isFinished: Bool { recorder.elapsed >= recorder.duration }

    /// What the stage draws now: the dolly shot at the current playback time, no grid or gizmo.
    public func frame(size: CGSize, renderScale: Float) -> StageFrame {
        if started == nil { started = CACurrentMediaTime() }
        let time = min(elapsed, NightMarket.duration)
        var request = builder.request(at: time, framing: .landscape, size: size, frameIndex: builder.timeline.frame(for: time),
                                      renderScale: renderScale)
        var editor = EditorScene()
        editor.showsGrid = false
        editor.showsSelection = false
        request.editor = editor
        return StageFrame(request: request, shotCamera: request.camera)
    }

    /// Feeds one presented frame (frame-to-frame time, as the viewer feels it); true once the run is over.
    @discardableResult
    public func record(frameTime: Double, renderScale: Float, report: FrameReport?) -> Bool {
        if let report { lastReport = report }
        guard frameTime > 0 else { return false }
        return recorder.frame(duration: frameTime, at: CACurrentMediaTime(), renderScale: Double(renderScale), thermal: .current,
                              memoryMB: Self.memoryFootprintMB())
    }

    /// Runs the benchmark away from the screen (tests, and CI's smoke run): renders `frames` frames back to back at
    /// `width` × `height` and records the wall time of each.
    public func runOffscreen(frames count: Int, width: Int, height: Int, device: RenderDevice) async throws {
        let renderer = try FrameRenderer(device: device, models: builder.models)
        let fps = Double(builder.timeline.fps)
        let size = CGSize(width: width, height: height)
        var clock = CACurrentMediaTime()
        for index in 0 ..< count {
            let time = Double(index) / fps
            var request = builder.request(at: time, framing: .landscape, size: size, frameIndex: index)
            request.editor = nil
            lastReport = try await renderer.render(request, width: width, height: height)
            let now = CACurrentMediaTime()
            _ = recorder.frame(duration: now - clock, at: time, renderScale: 1, thermal: .current, memoryMB: Self.memoryFootprintMB())
            clock = now
        }
    }

    /// The finished report; the scene facts include what the last frame drew.
    public func report(appVersion: String, device: String, system: String) -> BenchmarkReport {
        var facts = NightMarket.facts(document.scene)
        if let lastReport {
            facts["triangles"] = Double(lastReport.triangles)
            facts["drawCalls"] = Double(lastReport.drawCalls)
        }
        facts["tier"] = Double(DeviceTier.allCases.firstIndex(of: tier) ?? 0) + 1
        let scene = tier == .a ? NightMarket.projectName : "\(NightMarket.projectName) (Tier \(tier.rawValue) preview)"
        return recorder.report(app: "Maquette", appVersion: appVersion, scene: scene, device: device, system: system, sceneFacts: facts)
    }

    /// Writes the report as `benchmark-<device>-<version>.json` into `folder`.
    public static func write(_ report: BenchmarkReport, to folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(report.fileName)
        try report.json().write(to: url, options: .atomic)
        return url
    }

    /// The app's physical memory footprint in megabytes.
    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
