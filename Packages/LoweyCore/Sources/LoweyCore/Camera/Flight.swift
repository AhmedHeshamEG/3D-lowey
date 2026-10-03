import Foundation

/// Flying a camera like a drone in a game: one stick moves (forward/back, strafe), the other looks (pan, tilt), a
/// slider or the triggers lift. Moves ease in and out (velocity follows the sticks with a short lag), so a flown take
/// reads as a camera operator's move, not a joystick's.
public struct Flight: Sendable {
    /// What the controls ask for, each −1…1.
    public struct Input: Equatable, Sendable {
        public var strafe: Double
        public var forward: Double
        public var lift: Double
        public var pan: Double
        public var tilt: Double

        public init(strafe: Double = 0, forward: Double = 0, lift: Double = 0, pan: Double = 0, tilt: Double = 0) {
            self.strafe = strafe
            self.forward = forward
            self.lift = lift
            self.pan = pan
            self.tilt = tilt
        }

        public static let none = Input()

        public var isIdle: Bool { [strafe, forward, lift, pan, tilt].allSatisfy { abs($0) < 1e-3 } }
    }

    /// Top speed (metres per second) and turn rate (degrees per second) at full stick.
    public var speed: Double
    public var turnRate: Double
    /// Seconds to reach the asked speed (the ease).
    public var response: Double
    private var velocity = Vec3.zero
    private var turn = (pan: 0.0, tilt: 0.0)

    public init(speed: Double = 3, turnRate: Double = 70, response: Double = 0.25) {
        self.speed = speed
        self.turnRate = turnRate
        self.response = response
    }

    /// The camera after `dt` seconds of `input`. Moves follow the camera's heading, level with the ground; lift is
    /// world up; tilt never goes past straight up or down.
    public mutating func step(_ camera: Transform, input: Input, dt: Double) -> Transform {
        guard dt > 0 else { return camera }
        let blend = 1 - exp(-dt / max(response, 1e-3))
        let forward = camera.rotation.act(Vec3(0, 0, -1))
        let heading = Vec3(forward.x, 0, forward.z).length > 1e-6 ? Vec3(forward.x, 0, forward.z).normalized : Vec3(0, 0, -1)
        let right = Vec3(-heading.z, 0, heading.x)
        let wanted = (heading * clamp(input.forward) + right * clamp(input.strafe) + Vec3(0, clamp(input.lift), 0)) * speed
        velocity += (wanted - velocity) * blend
        turn.pan += (clamp(input.pan) * turnRate - turn.pan) * blend
        turn.tilt += (clamp(input.tilt) * turnRate - turn.tilt) * blend
        var result = camera
        result.position += velocity * dt
        let pitch = asin(min(max(forward.y, -1), 1)) * 180 / .pi
        let tilt = min(max(pitch + turn.tilt * dt, -85), 85) - pitch
        let side = camera.rotation.act(Vec3(1, 0, 0))
        let yaw = Quat(angle: -turn.pan * dt * .pi / 180, axis: .unitY)
        result.rotation = (yaw * Quat(angle: tilt * .pi / 180, axis: side) * camera.rotation).normalized
        return result
    }

    /// Still: nothing moving or turning.
    public var isResting: Bool { velocity.length < 1e-3 && abs(turn.pan) < 0.05 && abs(turn.tilt) < 0.05 }

    private func clamp(_ value: Double) -> Double { min(max(value, -1), 1) }
}
