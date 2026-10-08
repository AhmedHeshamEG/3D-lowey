import Foundation
@testable import LoweyCore
import XCTest

/// The Motion row's six looping motions: each is one behaviour at one speed, they loop, and they become keys.
final class LoopMotionTests: XCTestCase {
    /// The shared test scene with the motions on "c" (a root cylinder) and four seconds of time.
    private func document(with kinds: [BehaviorKind]) -> (Document, ObjectID) {
        var document = makeDocument()
        document.scene.timeline.duration = 4
        for (index, kind) in kinds.enumerated() {
            document.scene.timeline.behaviors.append(Behavior(id: "b\(index)", target: "c", kind: kind))
        }
        return (document, "c")
    }

    private func position(_ document: Document, _ id: ObjectID, at time: Double) -> Vec3 {
        Animator.evaluate(document, at: time).scene.objects[id]?.transform.position ?? .zero
    }

    func testEveryMotionReadsBackAsItselfAtItsSpeed() throws {
        let path = ObjectID(raw: "path")
        for motion in LoopMotion.allCases {
            for speed in [0.25, 1, 2.5, 4] {
                let kind = try XCTUnwrap(motion.behavior(speed: speed, path: path))
                let reading = try XCTUnwrap(LoopMotion.reading(kind), "\(motion) isn't recognised")
                XCTAssertEqual(reading.motion, motion)
                XCTAssertEqual(reading.speed, speed, accuracy: 1e-9)
                let faster = LoopMotion.retimed(kind, speed: 3)
                XCTAssertEqual(try XCTUnwrap(LoopMotion.reading(faster)).speed, 3, accuracy: 1e-9)
            }
        }
        XCTAssertNil(LoopMotion.followPath.behavior(), "following needs a path")
        XCTAssertNil(LoopMotion.reading(.followPath(.object(path), duration: 3, loop: false, orient: true)), "a path followed once isn't a loop")
        XCTAssertNil(LoopMotion.reading(.lookAt(path)))
        XCTAssertEqual(try XCTUnwrap(LoopMotion.reading(XCTUnwrap(LoopMotion.spin.behavior(speed: 99)))).speed, 4, "clamped to the slider")
    }

    func testRetimingKeepsWhatIsNotSpeed() {
        XCTAssertEqual(LoopMotion.retimed(.bounce(height: 1.5, period: 1), speed: 2), .bounce(height: 1.5, period: 0.5))
        XCTAssertEqual(LoopMotion.retimed(.spin(degreesPerSecond: -90, axis: .x), speed: 2), .spin(degreesPerSecond: -180, axis: .x))
        XCTAssertEqual(LoopMotion.retimed(.lookAt(ObjectID(raw: "x")), speed: 2), .lookAt(ObjectID(raw: "x")))
    }

    func testBounceHopsAndLandsEveryPeriod() {
        let (document, cube) = document(with: [.bounce(height: 0.4, period: 1)])
        let rest = position(document, cube, at: 0).y
        XCTAssertEqual(position(document, cube, at: 0.5).y - rest, 0.4, accuracy: 1e-9, "the top of the hop")
        XCTAssertEqual(position(document, cube, at: 0.25).y - rest, 0.3, accuracy: 1e-9, "a parabola")
        for time in [1.0, 2.0, 3.0] {
            XCTAssertEqual(position(document, cube, at: time).y, rest, accuracy: 1e-9, "back on the ground at \(time) s")
        }
        XCTAssertEqual(position(document, cube, at: 2.5).y - rest, 0.4, accuracy: 1e-9, "it loops")
    }

    func testSwingGoesThereAndBack() throws {
        let (document, cube) = document(with: [.swing(angle: 25, period: 2)])
        func roll(_ time: Double) throws -> Double {
            let rotation = try XCTUnwrap(Animator.evaluate(document, at: time).scene.objects[cube]?.transform.rotation)
            return rotation.act(.unitX).y
        }
        XCTAssertEqual(try roll(0), 0, accuracy: 1e-9)
        XCTAssertEqual(try roll(0.5), sin(25 * .pi / 180), accuracy: 1e-9, "all the way one side")
        XCTAssertEqual(try roll(1), 0, accuracy: 1e-9)
        XCTAssertEqual(try roll(1.5), -sin(25 * .pi / 180), accuracy: 1e-9, "all the way the other")
        XCTAssertEqual(try roll(2), 0, accuracy: 1e-9)
    }

    func testTheNewMotionsRoundTripInTheProjectFile() throws {
        for kind in [BehaviorKind.bounce(height: 0.4, period: 0.5), .swing(angle: 25, period: 2)] {
            let data = try JSONEncoder().encode(kind)
            XCTAssertEqual(try JSONDecoder().decode(BehaviorKind.self, from: data), kind)
        }
    }

    func testMakingKeyframesOfSeveralMotionsAtOnce() throws {
        let (document, cube) = document(with: [.bounce(height: 0.4, period: 1), .spin(degreesPerSecond: 90, axis: .y)])
        var ids = IDFactory.random
        let command = try XCTUnwrap(Simulation.bake(["b0", "b1"], label: "Make keyframes", in: document, ids: &ids))
        var session = EditSession(document: document)
        _ = try session.perform(command)
        let baked = session.document
        XCTAssertTrue(baked.scene.timeline.behaviors.isEmpty, "the motions became keys")
        XCTAssertNotNil(baked.scene.timeline.track(for: cube, .position))
        XCTAssertNotNil(baked.scene.timeline.track(for: cube, .rotation))
        for time in [0.25, 0.5, 1.3, 2.75, 3.5] {
            let before = Animator.evaluate(document, at: time).scene.objects[cube]?.transform
            let after = Animator.evaluate(baked, at: time).scene.objects[cube]?.transform
            XCTAssertEqual(after?.position.y ?? 0, before?.position.y ?? 1, accuracy: 0.02, "the hop at \(time) s")
            let turned = (before?.rotation.act(.unitX) ?? .zero).distance(to: after?.rotation.act(.unitX) ?? .unitY)
            XCTAssertLessThan(turned, 0.05, "the spin at \(time) s")
        }
        XCTAssertNil(Simulation.bake(["nothing"], label: "x", in: document, ids: &ids))
    }
}
