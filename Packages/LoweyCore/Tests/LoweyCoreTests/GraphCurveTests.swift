import Foundation
@testable import LoweyCore
import XCTest

final class GraphCurveTests: XCTestCase {
    private let track = Track(id: "t", target: "a", property: .position, keyframes: [
        Keyframe(time: 0, value: .vec3(Vec3(0, 0, 0)), easing: .cubicBezier(0.25, 0, 0.75, 1)),
        Keyframe(time: 1, value: .vec3(Vec3(2, 4, 0)), easing: .easeInOut),
        Keyframe(time: 2, value: .vec3(Vec3(2, 4, 0)))
    ])

    func testComponents() {
        XCTAssertEqual(GraphCurves.components(.vec3(Vec3(1, 2, 3))), [1, 2, 3])
        XCTAssertEqual(GraphCurves.components(.float(0.5)), [0.5])
        XCTAssertNil(GraphCurves.components(.color(.palette(1))))
        let turned = GraphCurves.components(.quat(Quat(eulerDegrees: Vec3(0, 30, 0)))) ?? []
        XCTAssertEqual(turned[1], 30, accuracy: 1e-6)
        XCTAssertEqual(GraphCurves.replacing(component: 1, with: 9, in: .vec3(Vec3(1, 2, 3))), .vec3(Vec3(1, 9, 3)))
        let rotation = GraphCurves.replacing(component: 1, with: 45, in: .quat(.identity))
        XCTAssertEqual(GraphCurves.components(rotation)?[1] ?? 0, 45, accuracy: 1e-6)
        XCTAssertEqual(GraphCurves.componentNames(.quat(.identity)), ["Tilt", "Turn", "Roll"])
    }

    func testCurveAndHandles() throws {
        let curve = GraphCurves.curve(track, component: 1, from: 0, to: 2, count: 21)
        XCTAssertEqual(curve.count, 21)
        XCTAssertEqual(curve[10].value, 4, accuracy: 1e-9)
        XCTAssertEqual(curve[5].value, 2, accuracy: 1e-6, "symmetric ease: half way at half time")
        let handles = try XCTUnwrap(GraphCurves.handles(track, key: 0, component: 1))
        XCTAssertEqual(handles.first.time, 0.25, accuracy: 1e-9)
        XCTAssertEqual(handles.first.value, 0, accuracy: 1e-9)
        XCTAssertEqual(handles.second.value, 4, accuracy: 1e-9)
        XCTAssertNil(GraphCurves.handles(track, key: 2, component: 1), "the last key leads nowhere")
    }

    func testDraggingAHandleShapesTheEasing() throws {
        let easing = try XCTUnwrap(GraphCurves.easing(track, key: 0, component: 1, first: true, to: 0.1, value: 2))
        XCTAssertEqual(easing, .cubicBezier(0.1, 0.5, 0.75, 1))
        // A flat segment keeps the handle's height.
        let flat = try XCTUnwrap(GraphCurves.easing(track, key: 1, component: 1, first: false, to: 1.5, value: 99))
        guard case let .cubicBezier(_, _, x2, _) = flat else { return XCTFail("a curve") }
        XCTAssertEqual(x2, 0.5, accuracy: 1e-9)
    }

    func testMovingAKeyStaysBetweenItsNeighbours() {
        let moved = GraphCurves.moving(key: 1, in: track, to: 5, component: 0, value: 3, fps: 30)
        XCTAssertEqual(moved.keyframes.map(\.time), [0, 59.0 / 30, 2])
        XCTAssertEqual(moved.keyframes[1].value, .vec3(Vec3(3, 4, 0)))
        XCTAssertEqual(moved.keyframes[1].easing, .easeInOut)
    }
}
