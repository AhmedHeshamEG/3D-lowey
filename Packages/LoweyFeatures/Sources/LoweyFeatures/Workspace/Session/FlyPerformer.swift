import Foundation
import GameController
import LoweyCore

/// Flies the shot camera from the on-screen sticks or a game controller (MFi, Xbox, PlayStation): left stick moves,
/// right stick looks, the triggers (or the pad's slider) lift; A records a take (or stops one), B stops flying.
/// Ticks once per screen frame while flying.
@MainActor
final class FlyPerformer {
    var flight = Flight()
    /// What the on-screen pad asks for.
    var pad = Flight.Input.none
    /// Moving now (a flight in progress is one undo step, or one stretch of a take).
    var isMoving = false
    private let clock = PlaybackClock()
    private var buttonA = false
    private var buttonB = false

    /// The connected controller, if any.
    static var controller: GCExtendedGamepad? { GCController.controllers().first { $0.extendedGamepad != nil }?.extendedGamepad }

    func start(_ step: @escaping @MainActor (Flight.Input, Double) -> Void, buttons: @escaping @MainActor (_ record: Bool, _ stop: Bool) -> Void) {
        clock.preferred = 120
        clock.onTick = { [weak self] dt in
            guard let self else { return }
            let (input, record, stop) = read()
            buttons(record, stop)
            step(input, dt > 0 ? dt : 1.0 / 60)
        }
        clock.start()
    }

    func stop() {
        clock.stop()
        pad = .none
        isMoving = false
    }

    /// The controller wins whenever it's touched; otherwise the on-screen pad.
    private func read() -> (Flight.Input, record: Bool, stop: Bool) {
        guard let gamepad = Self.controller else { return (pad, false, false) }
        let input = Flight.Input(strafe: Self.deadZone(Double(gamepad.leftThumbstick.xAxis.value)),
                                 forward: Self.deadZone(Double(gamepad.leftThumbstick.yAxis.value)),
                                 lift: Self.deadZone(Double(gamepad.rightTrigger.value - gamepad.leftTrigger.value)),
                                 pan: Self.deadZone(Double(gamepad.rightThumbstick.xAxis.value)),
                                 tilt: Self.deadZone(Double(gamepad.rightThumbstick.yAxis.value)))
        let a = gamepad.buttonA.isPressed
        let b = gamepad.buttonB.isPressed
        defer {
            buttonA = a
            buttonB = b
        }
        return (input.isIdle ? pad : input, a && !buttonA, b && !buttonB)
    }

    /// Sticks rest a little off centre: ignore the first 8 %, then a curve gentle near the middle.
    static func deadZone(_ value: Double) -> Double {
        let magnitude = abs(value)
        guard magnitude > 0.08 else { return 0 }
        let t = min((magnitude - 0.08) / 0.92, 1)
        return (value < 0 ? -1 : 1) * (0.3 * t + 0.7 * t * t)
    }
}
