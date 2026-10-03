import Foundation
@testable import LoweyCore
import XCTest

final class SmearTests: XCTestCase {
    func testSlowMovesStayClean() {
        XCTAssertNil(Smear.make(previous: .zero, current: Vec3(0.05, 0, 0), extent: 1, amount: 1))
        XCTAssertNil(Smear.make(previous: .zero, current: Vec3(2, 0, 0), extent: 1, amount: 0), "off unless asked for")
    }

    func testFastMovesStretchBehind() throws {
        let smear = try XCTUnwrap(Smear.make(previous: .zero, current: Vec3(1, 0, 0), extent: 1, amount: 1))
        XCTAssertEqual(smear.direction, Vec3(1, 0, 0))
        XCTAssertGreaterThan(smear.stretch, 1.5)
        // The leading point stays put, the trailing one goes further back; sideways nothing changes.
        let lead = smear.apply(to: Vec3(1.5, 0, 0))
        let trail = smear.apply(to: Vec3(0.5, 0, 0))
        XCTAssertLessThan(trail.x, 0.5)
        XCTAssertEqual(lead.x, 1.5, accuracy: 0.6)
        XCTAssertEqual(smear.apply(to: Vec3(1, 0.3, 0)).y, 0.3, accuracy: 1e-12)
    }

    func testSmearsFromTheTimeline() {
        var document = makeDocument()
        document.scene["c"]?[.smear] = .float(1)
        document.scene.timeline.fps = 24
        document.scene.timeline.tracks = [Track(id: "dash", target: "c", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(.zero), easing: .linear), Keyframe(time: 0.5, value: .vec3(Vec3(12, 0, 0)))
        ])]
        XCTAssertNotNil(Smear.smears(in: document, at: 0.25)["c"], "half a metre a frame")
        XCTAssertNil(Smear.smears(in: document, at: 0.25)["a"], "a doesn't smear")
        XCTAssertNil(Smear.smears(in: document, at: 1)["c"], "stopped")
    }
}
