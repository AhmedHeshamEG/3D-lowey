import QuartzCore

/// Flick the timeline and it keeps gliding, slowing like a scroll view (UIScrollView's normal deceleration).
@MainActor
final class TimelineMomentum {
    private var link: CADisplayLink?
    private var proxy: FrameProxy?
    private var last: CFTimeInterval?
    /// Timeline seconds per real second.
    private var velocity: Double = 0
    private var step: ((Double) -> Bool)?
    /// Below this speed (in points per second on screen) the glide stops.
    private var stopBelow: Double = 0

    var isRunning: Bool { link != nil }

    /// `step` applies a time offset and returns false when it hit an end (the glide stops there).
    func start(velocity: Double, pointsPerSecond: Double, step: @escaping (Double) -> Bool) {
        stop()
        guard abs(velocity * pointsPerSecond) > 60 else { return }
        self.velocity = velocity
        self.step = step
        stopBelow = 12 / max(pointsPerSecond, 1e-6)
        let proxy = FrameProxy { [weak self] link in self?.tick(link) }
        let link = CADisplayLink(target: proxy, selector: #selector(FrameProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.proxy = proxy
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        proxy = nil
        last = nil
        step = nil
    }

    private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { last = now }
        guard let last, let step else { return }
        let dt = min(now - last, 0.05)
        guard step(velocity * dt) else {
            stop()
            return
        }
        velocity *= pow(0.998, dt * 1000)
        if abs(velocity) < stopBelow { stop() }
    }
}
