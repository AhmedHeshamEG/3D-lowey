import Foundation
@testable import LoweyCore
import XCTest

final class FlipbookTests: XCTestCase {
    private let dot = FlipStroke(points: [Vec2(0, 0), Vec2(0.1, 0)], widths: [0.01, 0.01], color: .palette(0))

    private func track(holds: [Int], loops: Bool = false) -> FlipbookTrack {
        FlipbookTrack(id: "fx", name: "FX", start: 1, frames: holds.enumerated().map { FlipbookFrame(id: "f\($0.offset)", hold: $0.element,
                                                                                                     strokes: [dot]) },
                      loops: loops, end: loops ? 3 : nil)
    }

    func testHoldsAndLoops() {
        let flip = track(holds: [2, 1, 3])
        XCTAssertEqual(flip.lengthInFrames, 6)
        XCTAssertNil(flip.frameIndex(at: 0.9, fps: 24))
        XCTAssertEqual(flip.frameIndex(at: 1, fps: 24), 0)
        XCTAssertEqual(flip.frameIndex(at: 1 + 1.0 / 24, fps: 24), 0, "held on twos")
        XCTAssertEqual(flip.frameIndex(at: 1 + 2.0 / 24, fps: 24), 1)
        XCTAssertEqual(flip.frameIndex(at: 1 + 5.0 / 24, fps: 24), 2)
        XCTAssertNil(flip.frameIndex(at: 1 + 6.0 / 24, fps: 24), "done after its last hold")
        XCTAssertEqual(flip.startTime(ofFrame: 2, fps: 24), 1 + 3.0 / 24, accuracy: 1e-12)
        let looping = track(holds: [2, 1, 3], loops: true)
        XCTAssertEqual(looping.frameIndex(at: 1 + 7.0 / 24, fps: 24), 0, "loops back to the first drawing")
        XCTAssertNil(looping.frameIndex(at: 3.01, fps: 24), "stops at its end")
    }

    func testDrawingAtThePlayheadContinuesTheFlipbook() {
        var flip = FlipbookTrack(id: "fx", name: "FX")
        var result = FlipbookEditing.adding(dot, at: 2, fps: 24, hold: 2, to: flip, newID: "a")
        flip = result.track
        XCTAssertEqual(flip.start, 2)
        XCTAssertEqual(result.frame, 0)
        result = FlipbookEditing.adding(dot, at: 2 + 1.0 / 24, fps: 24, hold: 2, to: flip, newID: "b")
        XCTAssertEqual(result.track.frames.count, 1, "inside the held drawing: same drawing")
        XCTAssertEqual(result.track.frames[0].strokes.count, 2)
        flip = result.track
        result = FlipbookEditing.adding(dot, at: 2 + 5.0 / 24, fps: 24, hold: 2, to: flip, newID: "c")
        XCTAssertEqual(result.track.frames.count, 2)
        XCTAssertEqual(result.track.frames[0].hold, 5, "the last drawing holds until the new one")
        XCTAssertEqual(result.track.frameIndex(at: 2 + 5.0 / 24, fps: 24), 1)
        flip = result.track
        result = FlipbookEditing.adding(dot, at: 1, fps: 24, hold: 2, to: flip, newID: "d")
        XCTAssertEqual(result.track.start, 1)
        XCTAssertEqual(result.track.frameIndex(at: 2, fps: 24), 1, "the old drawings keep their times")
    }

    func testFrameEditing() {
        var flip = track(holds: [2, 2])
        flip = FlipbookEditing.insertingFrame(after: 0, hold: 3, in: flip, newID: "new")
        XCTAssertEqual(flip.frames.map(\.id), ["f0", "new", "f1"])
        flip = FlipbookEditing.duplicatingFrame(2, in: flip, newID: "copy")
        XCTAssertEqual(flip.frames.last?.strokes, flip.frames[2].strokes)
        flip = FlipbookEditing.settingHold(0, ofFrame: 0, in: flip)
        XCTAssertEqual(flip.frames[0].hold, 1)
        flip = FlipbookEditing.removingFrame(1, from: flip)
        XCTAssertEqual(flip.frames.map(\.id), ["f0", "f1", "copy"])
        XCTAssertTrue(FlipbookEditing.erasing(frame: 0, in: flip) { $0.x > 0.05 }.frames[0].strokes.isEmpty, "a lone point goes")
        let long = FlipStroke(points: (0 ... 4).map { Vec2(Double($0) * 0.1, 0) }, widths: [0.01], color: .palette(0))
        flip.frames[0].strokes = [long]
        let split = FlipbookEditing.erasing(frame: 0, in: flip) { abs($0.x - 0.2) < 0.01 }
        XCTAssertEqual(split.frames[0].strokes.map(\.points.count), [2, 2])
    }

    func testCommandRevertsAndRoundTrips() throws {
        let document = makeDocument()
        let added = try assertReverts(.setFlipbooks([FlipbookEdit(track(holds: [2]))]), on: document)
        XCTAssertEqual(added.scene.timeline.flipbooks.count, 1)
        var changed = track(holds: [2, 4])
        changed.blend = .multiply
        changed.anchor = .object("a")
        let replaced = try assertReverts(.setFlipbooks([FlipbookEdit(changed)]), on: added)
        XCTAssertEqual(replaced.scene.timeline.flipbook("fx")?.anchor, .object("a"))
        _ = try assertReverts(.setFlipbooks([FlipbookEdit(id: "fx", track: nil)]), on: replaced)
        let data = try LoweyJSON.encode(replaced.scene.timeline)
        XCTAssertEqual(try LoweyJSON.decode(Timeline.self, from: data), replaced.scene.timeline)
    }

    func testLayoutOnCameraAndObject() throws {
        var document = makeDocument()
        var onCamera = track(holds: [4])
        onCamera.start = 0
        var onObject = onCamera
        onObject.id = "obj"
        onObject.anchor = .object("c")
        document.scene.timeline.flipbooks = [onCamera, onObject]
        // A camera at the origin looking down −Z: the object at depth 5.
        document.scene["c"]?.transform.position = Vec3(0, 0, -5)
        let layout = FlipbookLayout(width: 1920, height: 1080, fieldOfView: 90) { point in
            guard point.z < 0 else { return nil }
            return (point.x / -point.z / (16.0 / 9), point.y / -point.z, -point.z)
        }
        let draws = layout.draws(document.scene.timeline, scene: document.scene, palette: document.palette, at: 0.05)
        XCTAssertEqual(draws.count, 2)
        let camera = try XCTUnwrap(draws.first)
        XCTAssertEqual(camera.strokes[0].points[0], Vec2(960, 540))
        XCTAssertEqual(camera.strokes[0].points[1].x, 960 + 108, accuracy: 1e-9, "a tenth of the frame height")
        let object = try XCTUnwrap(draws.last)
        // 90° vertical field of view at 5 m: 1080 px span 10 m → 108 px per metre.
        XCTAssertEqual(object.strokes[0].points[1].x - object.strokes[0].points[0].x, 10.8, accuracy: 1e-6)
        let frame = try XCTUnwrap(layout.anchorFrame(onObject, in: document.scene))
        XCTAssertEqual(frame.point(frame.pixel(Vec2(0.3, -0.2))).x, 0.3, accuracy: 1e-9)
        document.scene["c"]?.transform.position = Vec3(0, 0, 5)
        XCTAssertNil(layout.anchorFrame(onObject, in: document.scene), "behind the camera")
        XCTAssertEqual(FlipbookLayout.outline(camera.strokes[0]).count, 4)
    }

    func testEffectsAreDeterministicAndDrawable() {
        for fx in FlipbookFX.allCases {
            var ids = IDFactory.sequential("fx")
            let frames = fx.frames(size: 0.5, color: .palette(1), seed: 3, ids: &ids)
            XCTAssertEqual(frames.count, fx.defaultFrames, fx.title)
            XCTAssertTrue(frames.allSatisfy { !$0.strokes.isEmpty }, fx.title)
            var again = IDFactory.sequential("fx")
            XCTAssertEqual(fx.frames(size: 0.5, color: .palette(1), seed: 3, ids: &again), frames, "\(fx.title) is deterministic")
            let extent = frames.flatMap { $0.strokes.flatMap(\.points) }.map { max(abs($0.x), abs($0.y)) }.max() ?? 0
            XCTAssertLessThanOrEqual(extent, 0.5, fx.title)
        }
    }
}
