import Foundation
import QuartzCore

/// A display-link clock: calls back once per screen frame with the time since the last frame (playback, face
/// performance, momentum). Never used by export, which steps time exactly.
@MainActor
final class PlaybackClock {
    private var link: CADisplayLink?
    private var proxy: DisplayLinkTarget?
    private var last: CFTimeInterval?
    var onTick: ((Double) -> Void)?
    var preferred: Float = 120

    var isRunning: Bool { link != nil }

    func start() {
        stop()
        let proxy = DisplayLinkTarget { [weak self] link in self?.tick(link) }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: preferred)
        link.add(to: .main, forMode: .common)
        self.proxy = proxy
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        proxy = nil
        last = nil
    }

    private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let delta = last.map { now - $0 } ?? 0
        last = now
        onTick?(min(delta, 0.1))
    }
}

/// A CADisplayLink target that forwards to a closure (the link retains its target, not the owner).
final class DisplayLinkTarget: NSObject {
    private let body: @MainActor (CADisplayLink) -> Void

    init(_ body: @escaping @MainActor (CADisplayLink) -> Void) {
        self.body = body
    }

    @MainActor @objc func tick(_ link: CADisplayLink) {
        body(link)
    }
}
