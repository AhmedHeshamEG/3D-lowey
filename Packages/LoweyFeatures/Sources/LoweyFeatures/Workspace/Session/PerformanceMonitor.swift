import Foundation
import HmmDiagnostics
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

    func record(gpu: Double, total: Double, scale: Float) {
        let now = CACurrentMediaTime()
        let frameTime = total > 0 ? total : gpu
        stats.record(duration: frameTime, at: now)
        renderScale = scale
        onFrame?(total, gpu, scale)
        guard now - lastPublish > 0.25 else { return }
        lastPublish = now
        let note = String(format: "GPU %.1f ms · scale %.2f", gpu * 1000, scale)
        snapshot = PerformanceSnapshot(stats: stats, thermal: .current, memoryMB: MemoryFootprint.megabytes(), note: note)
    }

    func reset() {
        stats.reset()
    }
}
