@testable import LoweyCore
import XCTest

final class KeySelectionTests: XCTestCase {
    private func timeline() -> Timeline {
        let position = Track(id: "p", target: "a", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(.zero)), Keyframe(time: 1, value: .vec3(Vec3(1, 0, 0))),
            Keyframe(time: 2, value: .vec3(Vec3(2, 0, 0))), Keyframe(time: 3, value: .vec3(Vec3(3, 0, 0)))
        ])
        let scale = Track(id: "s", target: "a", property: .scale, keyframes: [
            Keyframe(time: 1, value: .vec3(.one)), Keyframe(time: 2.5, value: .vec3(Vec3(2, 2, 2)))
        ])
        let other = Track(id: "o", target: "c", property: .opacity, keyframes: [
            Keyframe(time: 0.5, value: .float(0)), Keyframe(time: 2, value: .float(1))
        ])
        return Timeline(fps: 30, duration: 5, tracks: [position, scale, other])
    }

    func testQueriesPickTheRightKeys() {
        let timeline = timeline()
        XCTAssertEqual(KeySelection.all(in: timeline).count, 8)
        let ofA = KeySelection.tracks(of: ["a"], in: timeline)
        XCTAssertEqual(ofA, ["p", "s"])
        // A box over object A's row from 0.9 s to 2.6 s.
        let box = KeySelection.keys(in: TimeRange(start: 0.9, end: 2.6), tracks: ofA, timeline: timeline)
        XCTAssertEqual(box, [KeyRef(track: "p", time: 1), KeyRef(track: "p", time: 2), KeyRef(track: "s", time: 1), KeyRef(track: "s", time: 2.5)])
        XCTAssertEqual(KeySelection.after(2, in: timeline).count, 4)
        XCTAssertEqual(KeySelection.before(0.5, in: timeline).count, 2)
        XCTAssertEqual(KeySelection.column(at: 2.01, in: timeline), [KeyRef(track: "p", time: 2), KeyRef(track: "o", time: 2)])
        let inverted = KeySelection.inverted(box, in: timeline, tracks: ofA)
        XCTAssertEqual(inverted, [KeyRef(track: "p", time: 0), KeyRef(track: "p", time: 3)])
        XCTAssertEqual(KeySelection.span(of: box), TimeRange(start: 1, end: 2.5))
        XCTAssertNil(KeySelection.span(of: []))
        // Stale refs are dropped, nearly-equal times snap to the stored key.
        let normalized = KeySelection.normalized([KeyRef(track: "p", time: 1.0002), KeyRef(track: "p", time: 7)], in: timeline)
        XCTAssertEqual(normalized, [KeyRef(track: "p", time: 1)])
    }

    func testStretchKeepsProportionsAndReverts() throws {
        var document = makeDocument()
        document.scene.timeline = timeline()
        let keys = KeyOperations()
        let selection: [KeyRef] = [KeyRef(track: "p", time: 1), KeyRef(track: "p", time: 2), KeyRef(track: "s", time: 1), KeyRef(track: "s", time: 2.5)]
        // Stretch 1…2.5 onto 1…4 (slower): 2 → 3, 2.5 → 4. The unselected key at 3 is replaced.
        let command = try XCTUnwrap(keys.stretch(selection, to: TimeRange(start: 1, end: 4), in: document.scene.timeline))
        let stretched = try assertReverts(command, on: document)
        XCTAssertEqual(stretched.scene.timeline.track("p")?.keyframes.map(\.time), [0, 1, 3])
        XCTAssertEqual(stretched.scene.timeline.track("s")?.keyframes.map(\.time), [1, 4])
        // The value that was at 2 is now at 3.
        XCTAssertEqual(stretched.scene.timeline.track("p")?.key(at: 3)?.value, .vec3(Vec3(2, 0, 0)))
        // Same span → nothing to do.
        XCTAssertNil(keys.stretch(selection, to: TimeRange(start: 1, end: 2.5), in: document.scene.timeline))
        // Squash onto a single instant moves everything together without losing keys of other tracks.
        let squashed = try XCTUnwrap(keys.stretch([KeyRef(track: "o", time: 0.5), KeyRef(track: "o", time: 2)], to: TimeRange(start: 3, end: 3.5),
                                                  in: document.scene.timeline))
        let result = try assertReverts(squashed, on: document)
        XCTAssertEqual(result.scene.timeline.track("o")?.keyframes.map(\.time), [3, 3.5])
        XCTAssertEqual(KeySelection.stretchedTime(5, from: TimeRange(start: 5, end: 5), to: TimeRange(start: 6, end: 9)), 6)
    }

    func testMoveClampedStopsTheWholeSelectionAtZero() throws {
        var document = makeDocument()
        document.scene.timeline = timeline()
        let keys = KeyOperations()
        let selection = [KeyRef(track: "p", time: 1), KeyRef(track: "p", time: 2)]
        let command = try XCTUnwrap(keys.moveClamped(selection, by: -5, in: document.scene.timeline))
        let moved = try assertReverts(command, on: document)
        // 1 → 0 (replacing the old key at 0), 2 → 1: spacing kept.
        XCTAssertEqual(moved.scene.timeline.track("p")?.keyframes.map(\.time), [0, 1, 3])
        XCTAssertNil(keys.moveClamped([KeyRef(track: "p", time: 0)], by: -1, in: document.scene.timeline))
    }
}
