import Foundation
@testable import LoweyCore
import XCTest

final class MotionTests: XCTestCase {
    private func position(_ scene: Scene, _ id: ObjectID) -> Vec3 { scene.objects[id]?.transform.position ?? .zero }

    // MARK: Commands

    func testSetTracksRevertsExactly() throws {
        let document = makeDocument()
        let track = Track(id: "t1", target: "a", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(.zero)), Keyframe(time: 1, value: .vec3(Vec3(2, 0, 0)))
        ])
        let added = try assertReverts(.setTracks([TrackEdit(track)]), on: document)
        XCTAssertEqual(added.scene.timeline.tracks.count, 1)
        var changed = track
        changed.setKey(Keyframe(time: 2, value: .vec3(Vec3(3, 0, 0))))
        let second = Track(id: "t2", target: "c", property: .scale, keyframes: [Keyframe(time: 0, value: .vec3(.one))])
        let replaced = try assertReverts(.setTracks([TrackEdit(changed), TrackEdit(second)]), on: added)
        XCTAssertEqual(replaced.scene.timeline.tracks.map(\.id), ["t1", "t2"])
        // Removing the first track and undoing restores the original order.
        try assertReverts(.setTracks([TrackEdit(id: "t1", track: nil)]), on: replaced)
        // Removing a missing track is a harmless no-op.
        var doc = replaced
        _ = try EditCommand.setTracks([TrackEdit(id: "nope", track: nil)]).apply(to: &doc)
        XCTAssertEqual(doc, replaced)
        // A track whose id doesn't match the edit is rejected atomically.
        XCTAssertThrowsError(try EditCommand.setTracks([TrackEdit(id: "x", track: track)]).apply(to: &doc))
        XCTAssertEqual(EditCommand.setTracks([TrackEdit(id: "t1", track: nil)]).label, "Delete keys")
        XCTAssertEqual(EditCommand.setTracks([TrackEdit(track)]).label, "Animate")
    }

    func testCoalescedKeyingIsOneUndoStep() throws {
        var session = EditSession(document: makeDocument())
        var keys = KeyOperations(ids: .sequential("k"))
        for step in 1 ... 5 {
            let current = Animator.evaluate(session.document, at: 1).scene
            let edits = keys.keying([PropertyChange(object: "a", key: .position, value: .vec3(Vec3(Double(step) + 1, 0, 0)))],
                                    at: 1, current: current, timeline: session.document.scene.timeline)
            try session.perform(.setTracks(edits), coalesceKey: "drag")
        }
        session.endCoalescing()
        XCTAssertEqual(session.undoStack.count, 1)
        let track = try XCTUnwrap(session.document.scene.timeline.track(for: "a", .position))
        XCTAssertEqual(track.keyframes.count, 2, "a key at 0 holding the old value, and the key at 1")
        XCTAssertEqual(track.value(at: 1), .vec3(Vec3(6, 0, 0)))
        XCTAssertEqual(track.value(at: 0), .vec3(Vec3(1, 0, 0)), "the old value is the pre-gesture position")
        try session.undo()
        XCTAssertTrue(session.document.scene.timeline.tracks.isEmpty)
        try session.redo()
        XCTAssertEqual(session.document.scene.timeline.track(for: "a", .position)?.value(at: 1), .vec3(Vec3(6, 0, 0)))
    }

    func testDeleteTakesAnimationAlongAndDuplicateCopiesIt() throws {
        var document = makeDocument()
        document.scene.timeline.tracks = [Track(id: "t", target: "b", property: .scale, keyframes: [
            Keyframe(time: 0, value: .vec3(.one)), Keyframe(time: 1, value: .vec3(Vec3(2, 2, 2)))
        ]), Track(id: "p", target: "a", property: .position, keyframes: [Keyframe(time: 0, value: .vec3(Vec3(1, 0, 0)))])]
        document.scene.timeline.behaviors = [Behavior(id: "bh", target: "a", kind: .spin(degreesPerSecond: 90, axis: .y))]
        var ops = Operations(ids: .sequential("o"))
        let delete = try XCTUnwrap(ops.delete(["a"], in: document.scene))
        let after = try assertReverts(delete, on: document)
        XCTAssertTrue(after.scene.timeline.tracks.isEmpty, "the child's track goes with it")
        XCTAssertTrue(after.scene.timeline.behaviors.isEmpty)
        let (duplicate, roots) = try XCTUnwrap(ops.duplicate(["a"], in: document.scene, offset: Vec3(3, 0, 0)))
        let copied = try assertReverts(duplicate, on: document)
        XCTAssertEqual(copied.scene.timeline.tracks.count, 4)
        XCTAssertEqual(copied.scene.timeline.behaviors.count, 2)
        let newRoot = try XCTUnwrap(roots.first)
        XCTAssertEqual(copied.scene.timeline.track(for: newRoot, .position)?.keyframes.first?.value, .vec3(Vec3(4, 0, 0)),
                       "position keys of the copy move with it")
    }

    // MARK: Evaluation

    func testAnimatorAppliesTracksAndReportsAnimatedObjects() {
        var document = makeDocument()
        document.scene.timeline.tracks = [Track(id: "t", target: "c", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(.zero), easing: .linear), Keyframe(time: 2, value: .vec3(Vec3(4, 0, 0)))
        ])]
        let halfway = Animator.evaluate(document, at: 1)
        XCTAssertEqual(position(halfway.scene, "c"), Vec3(2, 0, 0))
        XCTAssertEqual(halfway.animated, ["c"])
        XCTAssertEqual(position(halfway.scene, "a"), Vec3(1, 0, 0), "untouched")
        XCTAssertEqual(Animator.keyedScene(document, at: 2).objects["c"]?.transform.position, Vec3(4, 0, 0))
        // A track with a mistyped value is ignored instead of corrupting the object.
        document.scene.timeline.tracks.append(Track(id: "bad", target: "a", property: .position, keyframes: [Keyframe(time: 0, value: .float(3))]))
        XCTAssertEqual(position(Animator.evaluate(document, at: 0).scene, "a"), Vec3(1, 0, 0))
    }

    func testPerObjectSteppingCameraStaysSmooth() {
        var document = makeDocument()
        var camera = SceneObject(id: "cam", name: "Camera", kind: .camera)
        camera[.fieldOfView] = .float(50)
        document.scene.objects["cam"] = camera
        document.scene.roots.append("cam")
        let ramp = [Keyframe(time: 0, value: .vec3(.zero), easing: .linear), Keyframe(time: 1, value: .vec3(Vec3(30, 0, 0)))]
        document.scene.timeline = Timeline(fps: 30, stepping: .onTwos, tracks: [
            Track(id: "t1", target: "c", property: .position, keyframes: ramp),
            Track(id: "t2", target: "cam", property: .position, keyframes: ramp),
            Track(id: "t3", target: "b", property: .position, keyframes: ramp)
        ])
        let frame15 = 15.0 / 30.0
        let scene = Animator.evaluate(document, at: frame15).scene
        XCTAssertEqual(position(scene, "c").x, 14, accuracy: 1e-6, "project on twos")
        XCTAssertEqual(position(scene, "cam").x, 15, accuracy: 1e-6, "camera smooth")
        // Object override: ones; children inherit a parent's stepping.
        document.scene.objects["c"]?[.stepping] = .enumeration("ones")
        document.scene.objects["a"]?[.stepping] = .enumeration("threes")
        let overridden = Animator.evaluate(document, at: frame15).scene
        XCTAssertEqual(position(overridden, "c").x, 15, accuracy: 1e-6)
        XCTAssertEqual(position(overridden, "b").x, 15, accuracy: 1e-6, "b inherits threes from a: frame 15 is on the grid")
        XCTAssertEqual(position(Animator.evaluate(document, at: 16.0 / 30.0).scene, "b").x, 15, accuracy: 1e-6)
        XCTAssertEqual(Stepping(name: "twos"), .onTwos)
        XCTAssertNil(Stepping(name: "fives"))
        XCTAssertEqual(Stepping.onThrees.name, "threes")
    }

    func testCameraCutsPickTheCamera() {
        var document = makeDocument()
        for id in ["c1", "c2"] as [ObjectID] {
            document.scene.objects[id] = SceneObject(id: id, name: id.raw, kind: .camera)
            document.scene.roots.append(id)
        }
        document.scene.activeCamera = "c1"
        XCTAssertEqual(Animator.evaluate(document, at: 3).camera, "c1")
        document.scene.timeline.cuts = [CameraCut(time: 2, camera: "c2"), CameraCut(time: 0, camera: "c1"), CameraCut(time: 5, camera: "gone")]
        XCTAssertEqual(Animator.evaluate(document, at: 1).camera, "c1")
        XCTAssertEqual(Animator.evaluate(document, at: 2).camera, "c2")
        XCTAssertEqual(Animator.evaluate(document, at: 6).camera, "c1", "a cut to a deleted camera falls back to the active camera")
        XCTAssertEqual(document.scene.timeline.contentEnd, 5)
    }

    func testTimelineCodableAndBackwardCompatible() throws {
        var timeline = Timeline(fps: 24, duration: 12, stepping: .onTwos)
        timeline.markers = [Marker(id: "m", time: 1.5, name: "Enigma")]
        timeline.loop = TimeRange(start: 3, end: 1)
        timeline.cuts = [CameraCut(time: 0, camera: "cam")]
        timeline.behaviors = [
            Behavior(id: "b1", target: "a", kind: .followPath(.points([.zero, .unitX]), duration: 2, loop: true, orient: true)),
            Behavior(id: "b2", target: "a", kind: .followPath(.object("path"), duration: 2, loop: false, orient: false), start: 1, end: 4),
            Behavior(id: "b3", target: "a", kind: .lookAt("b")),
            Behavior(id: "b4", target: "a", kind: .follow("b", offset: Vec3(0, 2, 5), lag: 0.2)),
            Behavior(id: "b5", target: "a", kind: .orbit(center: .zero, around: "b", period: 4, faceCenter: true)),
            Behavior(id: "b6", target: "a", kind: .noise(position: .one, rotation: Vec3(5, 5, 5), frequency: 2)),
            Behavior(id: "b7", target: "a", kind: .windSway(angle: 6, frequency: 0.5, direction: 30)),
            Behavior(id: "b8", target: "a", kind: .bob(height: 0.1, period: 3, tilt: 4), enabled: false),
            Behavior(id: "b9", target: "a", kind: .spin(degreesPerSecond: 45, axis: .x))
        ]
        timeline.clipTracks = [ClipTrack(id: "ct", target: "a", segments: [
            ClipSegment(id: "s", clip: ClipRef(asset: "tiger", name: "Walk"), start: 0, duration: 4)
        ], ik: IKSettings(feetOnGround: true, lookAt: "b"))]
        XCTAssertEqual(timeline.loop, TimeRange(start: 1, end: 3))
        let data = try LoweyJSON.encode(timeline)
        XCTAssertEqual(try LoweyJSON.decode(Timeline.self, from: data), timeline)
        // Phase 1 files have none of the new fields.
        let old = try LoweyJSON.decode(Timeline.self, from: Data(#"{"fps":30,"duration":10,"stepping":1,"tracks":[]}"#.utf8))
        XCTAssertEqual(old, Timeline())
        XCTAssertThrowsError(try LoweyJSON.decode(BehaviorKind.self, from: Data(#"{"type":"teleport"}"#.utf8)))
        XCTAssertEqual(timeline.animatedObjects, ["a"])
        XCTAssertEqual(timeline.snapped(0.51), 12.0 / 24.0)
        XCTAssertTrue(TimeRange(start: 0, end: 1).contains(1))
        XCTAssertEqual(TimeRange(start: 0, end: 1).clamp(3), 1)
        XCTAssertEqual(Set(BehaviorKind.noise(position: .zero, rotation: .zero, frequency: 1).drives), [.position, .rotation])
        for behavior in timeline.behaviors {
            XCTAssertFalse(behavior.kind.title.isEmpty)
            XCTAssertFalse(behavior.kind.drives.isEmpty)
        }
    }

    // MARK: Behaviours

    private func behaviorDocument() -> Document {
        var document = makeDocument()
        let path = DrawingRecipe(style: .tube, strokes: [.init(points: [.zero, Vec3(10, 0, 0)], widths: [0.05, 0.05])])
        document.scene.objects["path"] = SceneObject(id: "path", name: "Path", kind: .drawing(path), transform: Transform(position: Vec3(0, 0, 5)))
        document.scene.roots.append("path")
        return document
    }

    func testFollowPathAtConstantSpeedFacingForward() {
        var document = behaviorDocument()
        document.scene.timeline.behaviors = [Behavior(id: "f", target: "c", kind: .followPath(.object("path"), duration: 4, loop: false, orient: true))]
        let halfway = Animator.evaluate(document, at: 2).scene
        XCTAssertTrue(position(halfway, "c").isApproximately(Vec3(5, 0, 5)))
        let forward = halfway.objects["c"]!.transform.rotation.act(.unitZ)
        XCTAssertTrue(forward.isApproximately(.unitX, tolerance: 1e-6), "models face +Z: now along the path")
        XCTAssertTrue(position(Animator.evaluate(document, at: 10).scene, "c").isApproximately(Vec3(10, 0, 5)), "holds at the end")
        XCTAssertTrue(position(Animator.evaluate(document, at: -1).scene, "c").isApproximately(Vec3(-2, 0, 1)), "not started yet")
        // Child objects follow in world space.
        document.scene.timeline.behaviors = [Behavior(
            id: "f",
            target: "b",
            kind: .followPath(.points([.zero, Vec3(0, 0, 8)]), duration: 2, loop: true, orient: false)
        )]
        let child = Animator.evaluate(document, at: 2.5).scene
        XCTAssertTrue(child.worldTransform(of: "b").position.isApproximately(Vec3(0, 0, 2), tolerance: 1e-9))
        XCTAssertNil(PathCurve(points: []).sample(0.5))
        XCTAssertEqual(PathCurve(points: [Vec3(1, 1, 1)]).sample(0.5)?.position, Vec3(1, 1, 1))
    }

    func testLookAtFollowOrbitAndCameraFacing() {
        var document = behaviorDocument()
        var camera = SceneObject(id: "cam", name: "Cam", kind: .camera, transform: Transform(position: Vec3(0, 0, 10)))
        camera[.fieldOfView] = .float(40)
        document.scene.objects["cam"] = camera
        document.scene.roots.append("cam")
        document.scene.timeline.tracks = [Track(id: "move", target: "c", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(.zero), easing: .linear), Keyframe(time: 4, value: .vec3(Vec3(8, 0, 0)))
        ])]
        document.scene.timeline.behaviors = [Behavior(id: "look", target: "cam", kind: .lookAt("c"))]
        let scene = Animator.evaluate(document, at: 0).scene
        let view = scene.objects["cam"]!.transform.rotation.act(Vec3(0, 0, -1))
        XCTAssertTrue(view.isApproximately(Vec3(0, 0, -1), tolerance: 1e-9), "cameras look down -Z at the target")

        document.scene.timeline.behaviors = [Behavior(id: "follow", target: "cam", kind: .follow("c", offset: Vec3(0, 2, 6), lag: 1))]
        let following = Animator.evaluate(document, at: 3).scene
        XCTAssertTrue(position(following, "cam").isApproximately(Vec3(4, 2, 6), tolerance: 1e-9), "one second behind")
        document.scene.timeline.behaviors = [Behavior(id: "follow", target: "cam", kind: .follow("c", offset: Vec3(0, 2, 6), lag: 0))]
        XCTAssertTrue(position(Animator.evaluate(document, at: 3).scene, "cam").isApproximately(Vec3(6, 2, 6), tolerance: 1e-9))

        document.scene.timeline.tracks = []
        document.scene.timeline.behaviors = [Behavior(id: "orbit", target: "c", kind: .orbit(center: .zero, around: nil, period: 4, faceCenter: true))]
        let quarter = Animator.evaluate(document, at: 1).scene
        XCTAssertTrue(position(quarter, "c").isApproximately(Vec3(1, 0, 2), tolerance: 1e-9), "c starts at (-2,0,1): a quarter turn around Y")
        document.scene.timeline.behaviors = [Behavior(id: "orbit", target: "c", kind: .orbit(center: .zero, around: "path", period: 2, faceCenter: false))]
        XCTAssertEqual(position(Animator.evaluate(document, at: 2).scene, "c").x, -2, accuracy: 1e-9, "full turn")
    }

    func testOscillatingBehavioursAreDeterministicAndBounded() {
        var document = behaviorDocument()
        document.scene.timeline.behaviors = [
            Behavior(id: "n", target: "c", kind: .noise(position: Vec3(0.5, 0.5, 0.5), rotation: Vec3(10, 10, 10), frequency: 2)),
            Behavior(id: "w", target: "a", kind: .windSway(angle: 8, frequency: 0.5, direction: 0)),
            Behavior(id: "b", target: "path", kind: .bob(height: 0.2, period: 2, tilt: 5)),
            Behavior(id: "s", target: "b", kind: .spin(degreesPerSecond: 90, axis: .y), start: 1, end: 3)
        ]
        let first = Animator.evaluate(document, at: 1.37)
        let again = Animator.evaluate(document, at: 1.37)
        XCTAssertEqual(first.scene, again.scene, "same time, same result")
        XCTAssertEqual(first.animated, ["c", "a", "path", "b"])
        for time in stride(from: 0.0, through: 6, by: 0.25) {
            let scene = Animator.evaluate(document, at: time).scene
            XCTAssertLessThanOrEqual(position(scene, "c").distance(to: Vec3(-2, 0, 1)), 0.5 * 3.0.squareRoot() + 1e-9)
            XCTAssertLessThanOrEqual(abs(position(scene, "path").y), 0.2 + 1e-9)
            let up = scene.objects["a"]!.transform.rotation.act(.unitY)
            XCTAssertGreaterThan(up.y, cos(8.5 * .pi / 180), "sway stays within the angle")
        }
        let spun = Animator.evaluate(document, at: 2).scene.objects["b"]!.transform.rotation
        XCTAssertTrue(spun.isApproximately(Quat(angle: .pi / 2, axis: .unitY), tolerance: 1e-9))
        let held = Animator.evaluate(document, at: 10).scene.objects["b"]!.transform.rotation
        XCTAssertTrue(held.isApproximately(Quat(angle: .pi, axis: .unitY), tolerance: 1e-9), "holds at the end")
        XCTAssertEqual(Animator.evaluate(document, at: 0.5).scene.objects["b"]!.transform.rotation, .identity)
        // Noise helpers.
        XCTAssertEqual(Noise.value(3, seed: 1), Noise.lattice(3, seed: 1), accuracy: 1e-12)
        for x in stride(from: -5.0, through: 5, by: 0.13) {
            XCTAssertLessThanOrEqual(abs(Noise.fractal(x, seed: 9)), 1)
        }
        XCTAssertNotEqual(Noise.seed("a"), Noise.seed("b"))
    }

    func testBakingABehaviourKeepsTheMotion() throws {
        var document = behaviorDocument()
        document.scene.timeline.duration = 2
        document.scene.timeline.behaviors = [Behavior(id: "f", target: "c", kind: .followPath(.object("path"), duration: 2, loop: false, orient: false))]
        var ids = IDFactory.sequential("bake")
        let command = try XCTUnwrap(Simulation.bake("f", in: document, ids: &ids))
        let baked = try assertReverts(command, on: document)
        XCTAssertTrue(baked.scene.timeline.behaviors.isEmpty)
        for time in [0.0, 0.5, 1.3, 2.0] {
            let expected = position(Animator.evaluate(document, at: time).scene, "c")
            XCTAssertTrue(position(Animator.evaluate(baked, at: time).scene, "c").isApproximately(expected, tolerance: 0.01), "t=\(time)")
        }
        XCTAssertNil(Simulation.bake("missing", in: document, ids: &ids))
    }
}
