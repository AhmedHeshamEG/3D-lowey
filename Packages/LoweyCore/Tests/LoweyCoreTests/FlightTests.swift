import Foundation
@testable import LoweyCore
import XCTest

final class FlightTests: XCTestCase {
    func testFlyingForwardEasesUpToSpeed() {
        var flight = Flight(speed: 2, response: 0.2)
        var camera = Transform.identity
        camera = flight.step(camera, input: Flight.Input(forward: 1), dt: 1.0 / 60)
        let first = -camera.position.z
        XCTAssertGreaterThan(first, 0)
        XCTAssertLessThan(first, 2.0 / 60 * 0.5, "it eases in")
        for _ in 0 ..< 120 {
            camera = flight.step(camera, input: Flight.Input(forward: 1), dt: 1.0 / 60)
        }
        let before = camera.position.z
        camera = flight.step(camera, input: Flight.Input(forward: 1), dt: 1.0 / 60)
        XCTAssertEqual(before - camera.position.z, 2.0 / 60, accuracy: 0.002, "full speed after a moment")
        XCTAssertEqual(camera.position.y, 0, accuracy: 1e-9, "level with the ground")
        // Let go: it glides to a stop.
        for _ in 0 ..< 120 {
            camera = flight.step(camera, input: .none, dt: 1.0 / 60)
        }
        XCTAssertTrue(flight.isResting)
    }

    func testLookingAroundAndTiltLimits() {
        var flight = Flight(turnRate: 90, response: 0.01)
        var camera = Transform.identity
        for _ in 0 ..< 60 {
            camera = flight.step(camera, input: Flight.Input(pan: 1), dt: 1.0 / 60)
        }
        let forward = camera.rotation.act(Vec3(0, 0, -1))
        XCTAssertEqual(atan2(forward.x, -forward.z) * 180 / .pi, 90, accuracy: 3, "a full stick turns 90° a second (to the right)")
        for _ in 0 ..< 300 {
            camera = flight.step(camera, input: Flight.Input(tilt: 1), dt: 1.0 / 60)
        }
        let up = camera.rotation.act(Vec3(0, 0, -1)).y
        XCTAssertLessThan(asin(up) * 180 / .pi, 85.5, "never past straight up")
        // Moving forward while looking up still flies level.
        let start = camera.position
        for _ in 0 ..< 60 {
            camera = flight.step(camera, input: Flight.Input(forward: 1), dt: 1.0 / 60)
        }
        XCTAssertEqual(camera.position.y, start.y, accuracy: 1e-9)
    }
}
