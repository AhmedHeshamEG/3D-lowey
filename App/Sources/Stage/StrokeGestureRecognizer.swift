import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Captures one drawing stroke with pressure and coalesced (high-frequency) Pencil samples.
final class StrokeGestureRecognizer: UIGestureRecognizer {
    struct Sample {
        var location: CGPoint
        /// 0...1 (fingers report ~0.6).
        var pressure: Double
    }

    private(set) var samples: [Sample] = []
    private var trackedTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first else {
            for touch in touches where touch !== trackedTouch {
                ignore(touch, for: event)
            }
            return
        }
        trackedTouch = touch
        samples = [sample(touch)]
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        let coalesced = event.coalescedTouches(for: touch) ?? [touch]
        for item in coalesced {
            samples.append(sample(item))
        }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        samples.append(sample(touch))
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
        samples = []
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
