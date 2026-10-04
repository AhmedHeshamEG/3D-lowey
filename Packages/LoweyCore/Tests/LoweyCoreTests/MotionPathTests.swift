import Foundation
@testable import LoweyCore
import XCTest

final class MotionPathTests: XCTestCase {
    /// "c" moves from x −2 to 2 over a second, through y 1 at the middle key.
    private func document() -> Document {
        var document = makeDocument()
        document.scene.timeline.tracks = [Track(id: "move", target: "c", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(Vec3(-2, 0, 0)), easing: .linear),
            Keyframe(time: 0.5, value: .vec3(Vec3(0, 1, 0)), easing: .linear),
            Keyframe(time: 1, value: .vec3(Vec3(2, 0, 0)))
        ])]
        return document
    }

    func testPathFollowsTheKeys() throws {
        let path = try XCTUnwrap(MotionPath.compute(document(), object: "c"))
        XCTAssertEqual(path.points.first, Vec3(-2, 0, 0))
        XCTAssertEqual(path.points.last, Vec3(2, 0, 0))
        XCTAssertEqual(path.keys.map(\.time), [0, 0.5, 1])
        XCTAssertEqual(path.keys[1].world, Vec3(0, 1, 0))
        XCTAssertNil(MotionPath.compute(document(), object: "a"), "nothing moves a")
    }

    func testParentsMoveTheArc() throws {
        var doc = makeDocument()
        doc.scene.timeline.tracks = [Track(id: "parent", target: "a", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(Vec3(0, 0, 0)), easing: .linear), Keyframe(time: 1, value: .vec3(Vec3(4, 0, 0)))
        ])]
        let path = try XCTUnwrap(MotionPath.compute(doc, object: "b"))
        // b sits at (0, 1, 0) under a.
        XCTAssertEqual(path.points.last, Vec3(4, 1, 0))
        XCTAssertTrue(path.keys.isEmpty, "b has no keys of its own to drag")
    }

    func testDraggingADotMovesItsKey() throws {
        let doc = document()
        let edit = try XCTUnwrap(MotionPath.movingKey(at: 0.5, of: "c", to: Vec3(0, 2, 1), in: doc))
        XCTAssertEqual(edit.track?.key(at: 0.5)?.value, .vec3(Vec3(0, 2, 1)))
        XCTAssertEqual(edit.track?.key(at: 0.5)?.easing, .linear, "the key keeps its easing")
        XCTAssertNil(MotionPath.movingKey(at: 0.3, of: "c", to: .zero, in: doc), "no key there")
        // Under a moving parent the key is stored in the parent's space.
        var nested = makeDocument()
        nested.scene.timeline.tracks = [
            Track(id: "p", target: "a", property: .position, keyframes: [Keyframe(time: 0, value: .vec3(Vec3(1, 0, 0)))]),
            Track(id: "b", target: "b", property: .position, keyframes: [Keyframe(time: 0, value: .vec3(Vec3(0, 1, 0)))])
        ]
        let local = try XCTUnwrap(MotionPath.movingKey(at: 0, of: "b", to: Vec3(3, 1, 0), in: nested))
        XCTAssertEqual(local.track?.key(at: 0)?.value, .vec3(Vec3(2, 1, 0)))
    }

    func testNeighbourKeyTimes() {
        let scene = document().scene
        let around = MotionPath.neighbourKeyTimes(of: "c", in: scene, around: 0.6, before: 2, after: 1)
        XCTAssertEqual(around.before, [0.5, 0])
        XCTAssertEqual(around.after, [1])
        XCTAssertEqual(MotionPath.neighbourKeyTimes(of: "c", in: scene, around: 0.5, before: 1, after: 0).before, [0])
    }
}
