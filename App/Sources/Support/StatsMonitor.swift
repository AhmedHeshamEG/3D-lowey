import Foundation
import Observation
import QuartzCore

/// Frame-rate readout for the stats pill: frames per second, the slowest frame (a hitch shows here even when the
/// average looks fine) and the device's heat. Runs only while the pill is shown.
@Observable
@MainActor
final class StatsMonitor {
    private(set) var fps: Double = 0
    private(set) var worstMilliseconds: Double = 0
    private(set) var thermal: ProcessInfo.ThermalState = .nominal

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var proxy: FrameProxy?
    @ObservationIgnored private var last: CFTimeInterval?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var elapsed: Double = 0
    @ObservationIgnored private var worst: Double = 0

    var isRunning: Bool { link != nil }

    func setRunning(_ running: Bool) {
        if running {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard link == nil else { return }
        let proxy = FrameProxy { [weak self] link in self?.tick(link) }
        let link = CADisplayLink(target: proxy, selector: #selector(FrameProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.proxy = proxy
        self.link = link
    }

    private func stop() {
        link?.invalidate()
        link = nil
        proxy = nil
        last = nil
        frames = 0
        elapsed = 0
        worst = 0
    }

    private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if let last {
            let delta = now - last
            frames += 1
            elapsed += delta
            worst = max(worst, delta)
        }
        last = now
        guard elapsed >= 0.5 else { return }
        fps = Double(frames) / elapsed
        worstMilliseconds = worst * 1000
        thermal = ProcessInfo.processInfo.thermalState
        frames = 0
        elapsed = 0
        worst = 0
    }
}

/// Lets a CADisplayLink call a closure (Swift 6 friendly target).
final class FrameProxy: NSObject {
    private let body: @MainActor (CADisplayLink) -> Void

    init(_ body: @escaping @MainActor (CADisplayLink) -> Void) {
        self.body = body
    }

    @MainActor @objc func tick(_ link: CADisplayLink) {
        body(link)
    }
}
