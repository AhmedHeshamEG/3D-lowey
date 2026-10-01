import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Captures one drawing stroke with pressure and coalesced (high-frequency) Pencil samples.
public final class StrokeGestureRecognizer: UIGestureRecognizer {
    public struct Sample {
        public var location: CGPoint
        /// 0...1 (fingers report ~0.6).
        public var pressure: Double

        public init(location: CGPoint, pressure: Double) {
            self.location = location
            self.pressure = pressure
        }
    }

    public private(set) var samples: [Sample] = []
    private var trackedTouch: UITouch?
    /// Draw, then hold still: called once per stroke (QuickShape). Moving on after it keeps reporting samples.
    public var onHold: (() -> Void)?
    /// How long the tip must rest, and how far it may drift while resting (points).
    public var holdDuration: TimeInterval = 0.45
    public var holdTolerance: CGFloat = 5
    public private(set) var held = false
    private var holdAnchor: CGPoint?
    private var holdTimer: Timer?

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first else {
            for touch in touches where touch !== trackedTouch {
                ignore(touch, for: event)
            }
            return
        }
        trackedTouch = touch
        samples = [sample(touch)]
        state = .began
        armHold(at: samples[0].location)
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        let coalesced = event.coalescedTouches(for: touch) ?? [touch]
        for item in coalesced {
            samples.append(sample(item))
        }
        if let last = samples.last?.location, !held,
           let anchor = holdAnchor, hypot(last.x - anchor.x, last.y - anchor.y) > holdTolerance {
            armHold(at: last)
        }
        state = .changed
    }

    /// (Re)starts the rest timer: it fires only if the tip stays within `holdTolerance` for `holdDuration`.
    private func armHold(at point: CGPoint) {
        holdAnchor = point
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.held, self.trackedTouch != nil, self.samples.count > 3 else { return }
                self.held = true
                self.onHold?()
            }
        }
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        samples.append(sample(touch))
        state = .ended
    }

    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override public func reset() {
        super.reset()
        trackedTouch = nil
        samples = []
        held = false
        holdAnchor = nil
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func sample(_ touch: UITouch) -> Sample {
        let pressure: Double = if touch.type == .pencil, touch.maximumPossibleForce > 0 {
            Double(touch.force / touch.maximumPossibleForce)
        } else {
            0.6
        }
        return Sample(location: touch.preciseLocation(in: view), pressure: pressure)
    }
}
