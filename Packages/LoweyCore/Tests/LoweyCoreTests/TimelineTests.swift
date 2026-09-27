import Foundation
@testable import LoweyCore
import XCTest

final class TimelineTests: XCTestCase {
    func testEasingEndpointsAndShapes() {
        let all: [Easing] = [.linear, .easeIn, .easeOut, .easeInOut, .backOut, .bounce, .elastic, .cubicBezier(0.25, 0.1, 0.25, 1)]
        for easing in all {
            XCTAssertEqual(easing.apply(0), 0, accuracy: 1e-6, "\(easing)")
            XCTAssertEqual(easing.apply(1), 1, accuracy: 1e-6, "\(easing)")
            XCTAssertEqual(easing.apply(-5), easing.apply(0), accuracy: 1e-9, "clamped")
            XCTAssertEqual(try LoweyJSON.decode(Easing.self, from: LoweyJSON.encode(easing)), easing)
        }
        XCTAssertEqual(Easing.linear.apply(0.3), 0.3, accuracy: 1e-12)
        XCTAssertLessThan(Easing.easeIn.apply(0.5), 0.5)
        XCTAssertGreaterThan(Easing.easeOut.apply(0.5), 0.5)
        XCTAssertEqual(Easing.easeInOut.apply(0.5), 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan((0 ... 100).map { Easing.backOut.apply(Double($0) / 100) }.max() ?? 0, 1, "back overshoots")
        XCTAssertEqual(Easing.step.apply(0.99), 0)
        XCTAssertEqual(Easing.cubicBezier(0, 0, 1, 1).apply(0.4), 0.4, accuracy: 1e-4)
        XCTAssertEqual(Easing.cubicBezier(0.9, -2, 0.1, 3).apply(0.5), Easing.cubicBezier(0.9, -2, 0.1, 3).apply(0.5))
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertTrue((0 ... 1.0001).contains(Easing.bounce.apply(t)))
        }
        XCTAssertThrowsError(try LoweyJSON.decode(Easing.self, from: Data("\"wobble\"".utf8)))
        XCTAssertThrowsError(try LoweyJSON.decode(Easing.self, from: Data("[1,2]".utf8)))
    }

    func testTrackEvaluation() {
        var track = Track(id: "t", target: "a", property: .position)
        XCTAssertNil(track.value(at: 0))
        track.setKey(Keyframe(time: 2, value: .vec3(Vec3(10, 0, 0)), easing: .linear))
        track.setKey(Keyframe(time: 0, value: .vec3(.zero), easing: .linear))
        XCTAssertEqual(track.keyframes.map(\.time), [0, 2])
        XCTAssertEqual(track.value(at: -1), .vec3(.zero))
        XCTAssertEqual(track.value(at: 1), .vec3(Vec3(5, 0, 0)))
        XCTAssertEqual(track.value(at: 3), .vec3(Vec3(10, 0, 0)))
        track.setKey(Keyframe(time: 1, value: .vec3(Vec3(0, 4, 0)), easing: .step))
        track.setKey(Keyframe(time: 1.0001, value: .vec3(Vec3(0, 5, 0)), easing: .step)) // replaces (within 0.5 ms)
        XCTAssertEqual(track.keyframes.count, 3)
        XCTAssertEqual(track.value(at: 1.5), .vec3(Vec3(0, 5, 0)), "step holds")
        track.removeKey(at: 1)
        XCTAssertEqual(track.keyframes.count, 2)
        var many = Track(id: "m", target: "a", property: .emissiveIntensity)
        for index in 0 ... 50 {
            many.setKey(Keyframe(time: Double(index), value: .float(Double(index)), easing: .linear))
        }
        XCTAssertEqual(many.value(at: 37.5), .float(37.5))
        var zero = Track(id: "z", target: "a", property: .visible, keyframes: [
            Keyframe(time: 1, value: .bool(false)), Keyframe(time: 1, value: .bool(true))
        ])
        zero.setKey(Keyframe(time: 3, value: .bool(false)))
        _ = zero.value(at: 1)
    }

    func testTimelineEvaluateAndStepping() {
        var track = Track(id: "t", target: "a", property: .emissiveIntensity, keyframes: [
            Keyframe(time: 0, value: .float(0), easing: .linear),
            Keyframe(time: 1, value: .float(30), easing: .linear)
        ])
        track.setKey(Keyframe(time: 1, value: .float(30), easing: .linear))
        var timeline = Timeline(fps: 30, duration: 1, tracks: [track])
        XCTAssertEqual(timeline.frameCount, 30)
        XCTAssertEqual(timeline.frame(for: 0.5), 15)
        XCTAssertEqual(timeline.time(for: 15), 0.5)
        XCTAssertEqual(timeline.evaluate(at: 0.5)["a"]?[.emissiveIntensity], .float(15))
        timeline.stepping = .onTwos
        // Frame 15 on twos → frame 14.
        XCTAssertEqual(timeline.evaluate(at: 0.5)["a"]?[.emissiveIntensity]?.floatValue ?? 0, 14, accuracy: 1e-9)
        XCTAssertEqual(Stepping.onThrees.quantize(10.0 / 30.0, fps: 30), 9.0 / 30.0, accuracy: 1e-12)
        XCTAssertEqual(Stepping.onOnes.quantize(0.123, fps: 30), 0.123)
        XCTAssertEqual(try LoweyJSON.decode(Timeline.self, from: LoweyJSON.encode(timeline)), timeline)
    }
}
