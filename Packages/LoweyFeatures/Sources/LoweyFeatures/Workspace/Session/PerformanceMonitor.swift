import Foundation
import HmmDiagnostics
import LoweyEngine
import Observation
import QuartzCore

/// Frame times from the stage for the Performance HUD and the benchmark. Every frame is recorded; the published
/// snapshot refreshes four times a second so the HUD itself costs nothing.
@Observable
@MainActor
final class PerformanceMonitor {
    private(set) var snapshot = PerformanceSnapshot(stats: FrameStats(), thermal: .nominal, memoryMB: 0)
    /// The stage's render scale right now (dynamic scale lowers it to hold the frame rate).
    private(set) var renderScale: Float = 1
    @ObservationIgnored private var stats = FrameStats(window: 5, budget: 1.0 / 120.0)
    @ObservationIgnored private var lastPublish: CFTimeInterval = 0
    /// Extra listeners (the benchmark runner) get every frame.
    @ObservationIgnored var onFrame: ((_ total: Double, _ gpu: Double, _ scale: Float) -> Void)?
    /// The hidden load meter (CONTEXT §6): silent until the scene nears what this iPad keeps smooth.
    private(set) var load: LoadMeter.Level = .comfortable
    @ObservationIgnored private var meter = LoadMeter()
    @ObservationIgnored private var lastSceneCost: CFTimeInterval = 0

    /// One frame: its interval (for the HUD), its GPU and CPU work (for the meter: the stage redraws on demand, so
    /// only the work says how close the device is), the render scale and the screen's budget.
    func record(gpu: Double, total: Double, scale: Float, work: Double? = nil, budget: Double? = nil) {
        let now = CACurrentMediaTime()
        let frameTime = total > 0 ? total : gpu
        if let budget, budget != stats.budget {
            stats.budget = budget
            meter.budget = budget
        }
        meter.record(frame: work ?? gpu, at: now)
        if meter.level != load { load = meter.level }
        stats.record(duration: frameTime, at: now)
        renderScale = scale
        onFrame?(total, gpu, scale)
        guard now - lastPublish > 0.25 else { return }
        lastPublish = now
        let note = String(format: "GPU %.1f ms · scale %.2f", gpu * 1000, scale)
        snapshot = PerformanceSnapshot(stats: stats, thermal: .current, memoryMB: MemoryFootprint.megabytes(), note: note)
    }

    /// What the scene draws, against what this tier draws comfortably (checked twice a second).
    func recordScene(_ report: FrameReport?, tier: DeviceTier) {
        let now = CACurrentMediaTime()
        guard let report, now - lastSceneCost > 0.5 else { return }
        lastSceneCost = now
        meter.setSceneCost(SceneCost.estimate(report, tier: tier), at: now)
        if meter.level != load { load = meter.level }
    }

    func reset() {
        stats.reset()
        meter.reset()
        load = .comfortable
    }
}
