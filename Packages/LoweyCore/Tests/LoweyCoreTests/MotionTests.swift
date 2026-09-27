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
        XCTAssertNil(Stepping(name: "fours"))
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

    // MARK: Key editing

    private func keyedDocument() -> Document {
        var document = makeDocument()
        document.scene.timeline.tracks = [Track(id: "t", target: "a", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(.zero), easing: .easeOut),
            Keyframe(time: 1, value: .vec3(Vec3(1, 0, 0)), easing: .linear),
            Keyframe(time: 2, value: .vec3(Vec3(3, 0, 0)), easing: .easeIn)
        ])]
        return document
    }

    func testKeyOperationsRevertAndBehave() throws {
        let document = keyedDocument()
        let timeline = document.scene.timeline
        var keys = KeyOperations(ids: .sequential("k"))
        let all = [KeyRef(track: "t", time: 0), KeyRef(track: "t", time: 1), KeyRef(track: "t", time: 2)]

        let moved = try assertReverts(XCTUnwrap(keys.move([KeyRef(track: "t", time: 1)], by: 0.5, in: timeline)), on: document)
        XCTAssertEqual(moved.scene.timeline.track("t")?.keyframes.map(\.time), [0, 1.5, 2])
        let collided = try assertReverts(XCTUnwrap(keys.move([KeyRef(track: "t", time: 1)], by: 1, in: timeline)), on: document)
        XCTAssertEqual(collided.scene.timeline.track("t")?.keyframes.count, 2, "landing on a key replaces it")

        let retimed = try assertReverts(XCTUnwrap(keys.retime(all, factor: 0.5, in: timeline)), on: document)
        XCTAssertEqual(retimed.scene.timeline.track("t")?.keyframes.map(\.time), [0, 0.5, 1])
        XCTAssertNil(keys.retime(all, factor: 0, in: timeline))

        let reversed = try assertReverts(XCTUnwrap(keys.reverse(all, in: timeline)), on: document)
        let reversedTrack = try XCTUnwrap(reversed.scene.timeline.track("t"))
        XCTAssertEqual(reversedTrack.keyframes.map(\.value), [.vec3(Vec3(3, 0, 0)), .vec3(Vec3(1, 0, 0)), .vec3(.zero)])
        XCTAssertEqual(reversedTrack.keyframes[1].easing, .easeIn, "ease-out played backwards is an ease-in")
        XCTAssertTrue(try XCTUnwrap(reversedTrack.value(at: 0.5)?.vec3Value).isApproximately(try XCTUnwrap(timeline.track("t")?.value(at: 1.5)?.vec3Value)))
        XCTAssertNil(keys.reverse([KeyRef(track: "t", time: 1)], in: timeline))

        let mirrored = try assertReverts(XCTUnwrap(keys.mirror(all, in: timeline)), on: document)
        XCTAssertEqual(mirrored.scene.timeline.track("t")?.keyframes.map(\.time), [0, 1, 2, 3, 4])
        XCTAssertEqual(mirrored.scene.timeline.track("t")?.value(at: 4), .vec3(.zero), "returns to the start")

        let eased = try assertReverts(XCTUnwrap(keys.setEasing(.bounce, for: [KeyRef(track: "t", time: 0)], in: timeline)), on: document)
        XCTAssertEqual(eased.scene.timeline.track("t")?.keyframes[0].easing, .bounce)

        let deleted = try assertReverts(XCTUnwrap(keys.delete([KeyRef(track: "t", time: 1)], in: timeline)), on: document)
        XCTAssertEqual(deleted.scene.timeline.track("t")?.keyframes.count, 2)
        let emptied = try assertReverts(XCTUnwrap(keys.delete(all, in: timeline)), on: document)
        XCTAssertTrue(emptied.scene.timeline.tracks.isEmpty, "a track without keys goes away")
        XCTAssertNil(keys.delete([KeyRef(track: "zzz", time: 0)], in: timeline))

        let clipboard = keys.copy([KeyRef(track: "t", time: 1), KeyRef(track: "t", time: 2)], in: timeline)
        XCTAssertEqual(clipboard.span, 1)
        let pasted = try assertReverts(XCTUnwrap(keys.paste(clipboard, at: 5, in: timeline)), on: document)
        XCTAssertEqual(pasted.scene.timeline.track("t")?.keyframes.map(\.time), [0, 1, 2, 5, 6])
        let onto = try assertReverts(XCTUnwrap(keys.paste(clipboard, at: 0, onto: "c", in: timeline)), on: document)
        XCTAssertEqual(onto.scene.timeline.track(for: "c", .position)?.keyframes.count, 2)
        XCTAssertTrue(keys.copy([], in: timeline).isEmpty)

        let shifted = try assertReverts(XCTUnwrap(keys.shift(["a"], by: -5, in: timeline)), on: document)
        XCTAssertEqual(shifted.scene.timeline.track("t")?.keyframes.first?.time, 0, "can't slide before zero")
        let cleared = try assertReverts(XCTUnwrap(keys.clear(["a"], in: timeline)), on: document)
        XCTAssertTrue(cleared.scene.timeline.tracks.isEmpty)
        XCTAssertNil(keys.clear(["c"], in: timeline))

        let transformKeys = try assertReverts(XCTUnwrap(keys.keyTransforms(["c"], at: 2, current: document.scene, timeline: timeline)), on: document)
        XCTAssertEqual(transformKeys.scene.timeline.tracks.filter { $0.target == "c" }.count, 3)
        XCTAssertEqual(KeyOperations.mirrored(.cubicBezier(0.1, 0.2, 0.3, 0.4)), .cubicBezier(0.7, 0.6, 0.9, 0.8))
        XCTAssertEqual(PropertyDefaults.value(for: .opacity), .float(1))
        XCTAssertNil(PropertyDefaults.value(for: .color))
    }

    func testSetKeyOnExistingTrackKeepsCurveStyle() {
        let timeline = keyedDocument().scene.timeline
        var keys = KeyOperations(ids: .sequential("k"))
        let edit = keys.setKey("a", .position, value: .vec3(Vec3(9, 9, 9)), at: 1.5, previous: nil, in: timeline)
        XCTAssertEqual(edit.id, "t")
        XCTAssertEqual(edit.track?.key(at: 1.5)?.easing, .linear, "inherits the easing of the key before")
        let replaced = keys.setKey("a", .position, value: .vec3(.one), at: 1, previous: nil, in: timeline)
        XCTAssertEqual(replaced.track?.keyframes.count, 3)
        let fresh = keys.setKey("c", .opacity, value: .float(0), at: 0, previous: .float(1), in: timeline)
        XCTAssertEqual(fresh.track?.keyframes.count, 1, "keying at time 0 doesn't add a 'before' key")
    }

    // MARK: Presets & stagger

    func testEveryPresetMakesEditableKeysAndReverts() throws {
        let document = makeDocument()
        var builder = PresetBuilder(ids: .sequential("p"))
        for preset in AnimationPreset.allCases {
            let command = try XCTUnwrap(builder.apply(preset, to: ["a"], at: 1, options: PresetOptions(preset),
                                                      current: document.scene, timeline: document.scene.timeline), "\(preset)")
            let applied = try assertReverts(command, on: document)
            XCTAssertFalse(applied.scene.timeline.tracks.isEmpty, "\(preset)")
            XCTAssertTrue(applied.scene.timeline.tracks.allSatisfy { !$0.keyframes.isEmpty })
            XCTAssertFalse(preset.title.isEmpty)
            XCTAssertFalse(preset.properties.isEmpty)
            let end = 1 + preset.defaultDuration
            let final = Animator.evaluate(applied, at: end + 0.01).scene.objects["a"]!
            let original = document.scene.objects["a"]!
            switch preset {
            case .popIn, .bounce, .dropIn, .slideIn, .wiggle, .shake, .pulse, .float:
                XCTAssertTrue(final.transform.isApproximately(original.transform, tolerance: 1e-6), "\(preset) ends where it started")
            case .popOut:
                XCTAssertLessThan(final.transform.scale.x, 0.01)
            case .grow:
                XCTAssertEqual(final.transform.scale.x, 2, accuracy: 1e-9)
            case .shrink:
                XCTAssertEqual(final.transform.scale.x, 0.5, accuracy: 1e-9)
            case .spin:
                XCTAssertTrue(final.transform.rotation.isApproximately(original.transform.rotation, tolerance: 1e-9), "a full turn")
                let half = Animator.evaluate(applied, at: 1 + preset.defaultDuration / 2).scene.objects["a"]!.transform.rotation
                XCTAssertFalse(half.isApproximately(original.transform.rotation, tolerance: 1e-3))
            case .fadeIn:
                XCTAssertEqual(final.opacity, 1, accuracy: 1e-9)
                XCTAssertEqual(Animator.evaluate(applied, at: 0.5).scene.objects["a"]!.opacity, 0, accuracy: 1e-9)
            case .fadeOut:
                XCTAssertEqual(final.opacity, 0, accuracy: 1e-9)
            case .typewriter:
                // "a" has one child ("b"): it appears at the start.
                XCTAssertEqual(Animator.evaluate(applied, at: 0.5).scene.objects["b"]!.isVisible, false)
                XCTAssertEqual(Animator.evaluate(applied, at: 1.01).scene.objects["b"]!.isVisible, true)
            }
        }
        // Popping in hides the object before the pop.
        let pop = try XCTUnwrap(builder.apply(.popIn, to: ["c"], at: 2, options: PresetOptions(.popIn), current: document.scene,
                                              timeline: document.scene.timeline))
        var popped = document
        _ = try pop.apply(to: &popped)
        XCTAssertLessThan(Animator.evaluate(popped, at: 1).scene.objects["c"]!.transform.scale.x, 0.01)
        XCTAssertGreaterThan(Animator.evaluate(popped, at: 2.2).scene.objects["c"]!.transform.scale.x, 0.5)
        XCTAssertGreaterThan(PresetBuilder.keys(.bounce, for: document.scene.objects["a"]!, at: 0, options: PresetOptions(.bounce)).count, 0)
    }

    func testPresetOnTopOfExistingKeysReplacesOnlyItsSpan() throws {
        var document = makeDocument()
        document.scene.timeline.tracks = [Track(id: "s", target: "a", property: .scale, keyframes: [
            Keyframe(time: 0, value: .vec3(.one)), Keyframe(time: 0.5, value: .vec3(Vec3(3, 3, 3))), Keyframe(time: 5, value: .vec3(.one))
        ])]
        var builder = PresetBuilder(ids: .sequential("p"))
        let command = try XCTUnwrap(builder.apply(.pulse, to: ["a"], at: 1, options: PresetOptions(.pulse), current: document.scene,
                                                  timeline: document.scene.timeline))
        let applied = try assertReverts(command, on: document)
        let times = try XCTUnwrap(applied.scene.timeline.track("s")).keyframes.map(\.time)
        XCTAssertEqual(times.first, 0)
        XCTAssertTrue(times.contains(0.5))
        XCTAssertTrue(times.contains(5))
        XCTAssertEqual(applied.scene.timeline.tracks.count, 1, "reuses the existing track")
    }

    func testMassStaggerOrdersAndRandomises() throws {
        var document = makeDocument()
        // A row of trees along X.
        var ids: [ObjectID] = []
        for index in 0 ..< 6 {
            let id = ObjectID(raw: "tree-\(index)")
            document.scene.objects[id] = SceneObject(id: id, name: "Tree", kind: .primitive(.cone),
                                                     transform: Transform(position: Vec3(Double(5 - index), 0, 0)))
            document.scene.roots.append(id)
            ids.append(id)
        }
        var builder = PresetBuilder(ids: .sequential("p"))
        let settings = StaggerSettings(delay: 0.1, order: .axis(.x, reversed: false))
        let command = try XCTUnwrap(builder.apply(.popIn, to: ids, at: 1, options: PresetOptions(.popIn), stagger: settings,
                                                  current: document.scene, timeline: document.scene.timeline))
        XCTAssertEqual(command.label, "Pop in × 6")
        let applied = try assertReverts(command, on: document)
        func start(_ id: ObjectID) -> Double { applied.scene.timeline.track(for: id, .scale)?.keyframes.first?.time ?? -1 }
        XCTAssertEqual(start("tree-5"), 1, accuracy: 1e-9, "left-most (x = 0) first")
        XCTAssertEqual(start("tree-0"), 1.5, accuracy: 1e-9, "right-most last")
        XCTAssertEqual(PresetBuilder.order(ids, by: .axis(.x, reversed: true), in: document.scene).first, "tree-0")
        XCTAssertEqual(PresetBuilder.order(ids, by: .distance(from: Vec3(3, 0, 0)), in: document.scene).first, "tree-2", "a wave from x = 3")
        XCTAssertEqual(PresetBuilder.order(ids + ["missing"], by: .selection, in: document.scene), ids)

        let random = StaggerSettings(delay: 0.1, order: .selection, randomTiming: 1, randomAmplitude: 0.5, seed: 42)
        let a = try XCTUnwrap(builder.apply(.bounce, to: ids, at: 0, options: PresetOptions(.bounce), stagger: random,
                                            current: document.scene, timeline: document.scene.timeline))
        let b = try XCTUnwrap(builder.apply(.bounce, to: ids, at: 0, options: PresetOptions(.bounce), stagger: random,
                                            current: document.scene, timeline: document.scene.timeline))
        func values(_ command: EditCommand) -> [PropertyValue] {
            guard case let .batch(_, commands) = command, case let .setTracks(edits) = commands.first else { return [] }
            return edits.compactMap { $0.track?.keyframes.map(\.value) }.flatMap { $0 }
        }
        XCTAssertEqual(values(a), values(b), "same seed, same crowd")
        XCTAssertEqual(PresetBuilder.scaledAmplitude(.grow, 2, by: 0.5), 1.5)
        XCTAssertEqual(PresetBuilder.scaledAmplitude(.bounce, 2, by: 0.5), 1)
    }

    func testAnimatedGeneratorsGrowFromTheStart() throws {
        let (info, scenes) = try EnigmaSample.build()
        let room = scenes[1]
        let array = try XCTUnwrap(room.objects.values.first { $0.name.contains("array") })
        var builder = PresetBuilder(ids: .sequential("g"))
        let command = try XCTUnwrap(builder.animateGenerator(array.id, at: 0, current: room, timeline: room.timeline))
        let applied = try assertReverts(command, on: Document(project: info, scene: room))
        XCTAssertEqual(applied.scene.timeline.tracks.count, array.children.count)
        let firstStart = applied.scene.timeline.track(for: array.children[0], .scale)?.keyframes.first?.time
        XCTAssertEqual(firstStart, 0, "grows from the first desk")
        XCTAssertNil(builder.animateGenerator("nope", at: 0, current: room, timeline: room.timeline))
    }

    // MARK: Perform

    func testPerformTakeBecomesKeysAndReplacesItsRange() throws {
        var take = PerformTake(object: "a", property: .position)
        take.begin()
        for frame in 0 ... 60 {
            let t = 1 + Double(frame) / 60
            take.add(.init(time: t, value: .vec3(Vec3(sin(t * 3), 0, 0))))
        }
        // Lift the finger, then perform again later.
        take.begin()
        take.add(.init(time: 4, value: .vec3(Vec3(0, 1, 0))))
        take.add(.init(time: 4.5, value: .vec3(Vec3(0, 2, 0))))
        XCTAssertEqual(take.segments.count, 2)
        XCTAssertFalse(take.isEmpty)

        let raw = PerformBaker.keys(from: take.segments[0], fps: 30, smoothing: 0)
        XCTAssertEqual(raw.count, 31, "0 % smoothing keeps every frame")
        XCTAssertEqual(raw.first?.time, 1)
        XCTAssertEqual(raw.last?.time, 2)
        let smooth = PerformBaker.keys(from: take.segments[0], fps: 30, smoothing: 0.8)
        XCTAssertLessThan(smooth.count, raw.count, "smoothing simplifies the curve")
        XCTAssertEqual(smooth.first?.value, raw.first?.value, "end points are exact")
        XCTAssertEqual(smooth.last?.value, raw.last?.value)

        var document = makeDocument()
        document.scene.timeline.tracks = [Track(id: "t", target: "a", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(.zero)), Keyframe(time: 1.5, value: .vec3(Vec3(9, 9, 9))), Keyframe(time: 3, value: .vec3(.one))
        ])]
        var ids = IDFactory.sequential("perf")
        let command = try XCTUnwrap(PerformBaker.command(for: [take], fps: 30, smoothing: 0.3, timeline: document.scene.timeline, ids: &ids))
        let applied = try assertReverts(command, on: document)
        let track = try XCTUnwrap(applied.scene.timeline.track("t"))
        XCTAssertFalse(track.keyframes.contains { $0.time == 1.5 }, "the performed range replaced the old key")
        XCTAssertTrue(track.keyframes.contains { $0.time == 0 } && track.keyframes.contains { $0.time == 3 }, "keys outside stay")
        XCTAssertEqual(track.value(at: 4.5), .vec3(Vec3(0, 2, 0)))
        XCTAssertNil(PerformBaker.command(for: [PerformTake(object: "a", property: .position)], fps: 30, smoothing: 0,
                                          timeline: document.scene.timeline, ids: &ids))
        XCTAssertEqual(PerformBaker.keys(from: [], fps: 30, smoothing: 0).count, 0)
        XCTAssertEqual(PerformBaker.keys(from: [.init(time: 2, value: .float(1))], fps: 30, smoothing: 0.5).count, 1)
        // Rotation and colour takes smooth too.
        let spins = (0 ... 20).map { PerformTake.Sample(time: Double($0) / 20, value: .quat(Quat(angle: Double($0) * 0.1, axis: .unitY))) }
        XCTAssertGreaterThan(PerformBaker.keys(from: spins, fps: 30, smoothing: 1).count, 1)
        XCTAssertEqual(PerformBaker.distance(.color(.rgba(RGBA(1, 0, 0))), .color(.rgba(RGBA(0, 0, 0)))), 1, accuracy: 1e-9)
        XCTAssertEqual(PerformBaker.distance(.bool(true), .bool(false)), 1)
    }

    // MARK: Camera

    private func cameraDocument() -> (Document, ObjectID) {
        var document = makeDocument()
        var camera = SceneObject(id: "cam", name: "Camera", kind: .camera,
                                 transform: Transform(position: Vec3(0, 1, 10), rotation: .identity))
        camera[.fieldOfView] = .float(50)
        document.scene.objects["cam"] = camera
        document.scene.roots.append("cam")
        return (document, "cam")
    }

    func testEveryCameraMoveKeysTheCameraAndReverts() throws {
        let (document, cam) = cameraDocument()
        var ids = IDFactory.sequential("cm")
        for move in CameraMove.allCases {
            let command = try XCTUnwrap(CameraMoves.apply(move, camera: cam, subject: Vec3(0, 1, 0), at: 0.5,
                                                          options: CameraMoveOptions(duration: move.defaultDuration),
                                                          current: document.scene, timeline: document.scene.timeline, ids: &ids))
            let applied = try assertReverts(command, on: document)
            XCTAssertFalse(applied.scene.timeline.tracks.isEmpty, "\(move)")
            XCTAssertFalse(move.title.isEmpty)
            let start = Animator.evaluate(applied, at: 0.5).scene.objects[cam]!
            let original = document.scene.objects[cam]!
            if move != .reveal {
                XCTAssertTrue(start.transform.position.isApproximately(original.transform.position, tolerance: 1e-6), "\(move) starts in place")
            }
            let end = Animator.evaluate(applied, at: 0.5 + move.defaultDuration).scene.objects[cam]!
            switch move {
            case .pushIn:
                XCTAssertLessThan(end.transform.position.distance(to: Vec3(0, 1, 0)), 9.99)
            case .pullOut:
                XCTAssertGreaterThan(end.transform.position.distance(to: Vec3(0, 1, 0)), 10.01)
            case .punchIn:
                XCTAssertLessThan(end[.fieldOfView]?.floatValue ?? 50, 50)
            case .truck:
                XCTAssertEqual(end.transform.position.x, 2, accuracy: 1e-9)
            case .crane:
                XCTAssertEqual(end.transform.position.y, 3, accuracy: 1e-9)
            case .orbit:
                XCTAssertEqual(end.transform.position.distance(to: Vec3(0, 1, 0)), 10, accuracy: 1e-6, "orbits keep their distance")
                let view = end.transform.rotation.act(Vec3(0, 0, -1))
                XCTAssertTrue(view.isApproximately((Vec3(0, 1, 0) - end.transform.position).normalized, tolerance: 1e-6), "and keep looking")
            case .whipPan:
                XCTAssertFalse(end.transform.rotation.isApproximately(original.transform.rotation, tolerance: 1e-3))
            case .shake:
                XCTAssertTrue(end.transform.rotation.isApproximately(original.transform.rotation, tolerance: 1e-9), "settles")
            case .dolly:
                XCTAssertEqual(end.transform.position.z, 8, accuracy: 1e-9)
            case .reveal:
                XCTAssertLessThan(start.transform.position.y, original.transform.position.y)
                XCTAssertTrue(end.transform.position.isApproximately(original.transform.position, tolerance: 1e-9))
            }
        }
        XCTAssertNil(CameraMoves.apply(.pushIn, camera: "none", subject: .zero, at: 0, options: CameraMoveOptions(duration: 1),
                                       current: document.scene, timeline: document.scene.timeline, ids: &ids))
        let pull = try XCTUnwrap(CameraMoves.focusPull(camera: cam, to: 2, at: 1, duration: 1, current: document.scene,
                                                       timeline: document.scene.timeline, ids: &ids))
        let pulled = try assertReverts(pull, on: document)
        XCTAssertEqual(Animator.evaluate(pulled, at: 2).scene.objects[cam]?[.focusDistance], .float(2))
    }

    func testLensMath() {
        var lens = CameraLens(fieldOfView: 50)
        XCTAssertEqual(CameraLens.fieldOfView(focalLength: lens.focalLength), 50, accuracy: 1e-9)
        XCTAssertEqual(lens.framing(aspect: 16.0 / 9.0).fieldOfView, 50)
        XCTAssertEqual(lens.framing(aspect: 16.0 / 9.0).yaw, 0)
        lens.portraitZoom = 1.2
        lens.portraitShift = 0.5
        let portrait = lens.framing(aspect: 9.0 / 16.0)
        XCTAssertEqual(portrait.fieldOfView, 60, accuracy: 1e-9)
        XCTAssertLessThan(portrait.yaw, 0, "pan right = turn right (negative yaw)")
        let (document, cam) = cameraDocument()
        XCTAssertEqual(CameraLens(document.scene.objects[cam]!).fieldOfView, 50)
    }

    // MARK: Simulations

    func testPhysicsFallsAndSettlesOnTheGround() throws {
        var document = makeDocument()
        document.scene.objects["c"]?.transform.position = Vec3(-2, 3, 1)
        var ids = IDFactory.sequential("sim")
        let bounds = SceneBounds()
        let command = try XCTUnwrap(Simulation.physics(["c"], settings: PhysicsSettings(kind: .fall, duration: 3), at: 0, fps: 30,
                                                       bounds: bounds, current: document.scene, timeline: document.scene.timeline, ids: &ids))
        let applied = try assertReverts(command, on: document)
        let late = Animator.evaluate(applied, at: 3).scene
        XCTAssertEqual(late.objects["c"]!.transform.position.y, 0, accuracy: 0.02, "rests on the ground (pivot at the base)")
        let early = Animator.evaluate(applied, at: 0.3).scene
        XCTAssertLessThan(early.objects["c"]!.transform.position.y, 3)
        // Deterministic.
        var ids2 = IDFactory.sequential("sim")
        let again = try XCTUnwrap(Simulation.physics(["c"], settings: PhysicsSettings(kind: .fall, duration: 3), at: 0, fps: 30,
                                                     bounds: bounds, current: document.scene, timeline: document.scene.timeline, ids: &ids2))
        XCTAssertEqual(command, again)
    }

    func testExplosionScattersObjects() throws {
        var document = makeDocument()
        document.scene.objects["b"]?.parent = nil
        document.scene.objects["a"]?.children = []
        document.scene.roots.append("b")
        var ids = IDFactory.sequential("sim")
        let command = try XCTUnwrap(Simulation.physics(["a", "b", "c"], settings: PhysicsSettings(kind: .explode, duration: 2, center: Vec3(0, 0, 0)),
                                                       at: 1, fps: 30, bounds: SceneBounds(), current: document.scene,
                                                       timeline: document.scene.timeline, ids: &ids))
        let applied = try assertReverts(command, on: document)
        let before = Animator.evaluate(applied, at: 1).scene
        let after = Animator.evaluate(applied, at: 1.5).scene
        for id in ["a", "c"] as [ObjectID] {
            let start = before.objects[id]!.transform.position
            let end = after.objects[id]!.transform.position
            XCTAssertGreaterThan(Vec3(end.x, 0, end.z).length, Vec3(start.x, 0, start.z).length, "\(id) flies outward")
        }
        XCTAssertNil(Simulation.physics(["zzz"], settings: PhysicsSettings(), at: 0, fps: 30, bounds: SceneBounds(), current: document.scene,
                                        timeline: document.scene.timeline, ids: &ids))
        var bodies = [Simulation.Body(id: "x", position: Vec3(0, 0.5, 0), velocity: .zero, rotation: .identity, spin: .zero, radius: 0.5,
                                      bottom: 0, parentWorld: .identity, scale: .one),
                      Simulation.Body(id: "y", position: Vec3(0.5, 0.5, 0), velocity: .zero, rotation: .identity, spin: .zero, radius: 0.5,
                                      bottom: 0, parentWorld: .identity, scale: .one)]
        Simulation.step(&bodies, dt: 0.01, settings: PhysicsSettings(gravity: 0))
        XCTAssertGreaterThanOrEqual(bodies[0].position.distance(to: bodies[1].position), 0.999, "overlapping bodies are pushed apart")
    }

    func testFlockAndCrowdBake() throws {
        var document = makeDocument()
        var birds: [ObjectID] = []
        for index in 0 ..< 8 {
            let id = ObjectID(raw: "bird-\(index)")
            document.scene.objects[id] = SceneObject(id: id, name: "Bird", kind: .primitive(.cone),
                                                     transform: Transform(position: Vec3(Double(index) * 0.5, 6, 0)))
            document.scene.roots.append(id)
            birds.append(id)
        }
        var ids = IDFactory.sequential("flock")
        let settings = Simulation.FlockSettings(duration: 3)
        let flock = try XCTUnwrap(Simulation.flock(birds, settings: settings, at: 0, fps: 30, current: document.scene,
                                                   timeline: document.scene.timeline, ids: &ids))
        let flying = try assertReverts(flock, on: document)
        let end = Animator.evaluate(flying, at: 3).scene
        for bird in birds {
            let p = end.objects[bird]!.transform.position
            XCTAssertLessThan(abs(p.x - settings.center.x), settings.extent.x + 6, "stays around the area")
            XCTAssertNotEqual(p, document.scene.objects[bird]!.transform.position, "moved")
        }
        XCTAssertNil(Simulation.flock(["none"], settings: settings, at: 0, fps: 30, current: document.scene, timeline: document.scene.timeline,
                                      ids: &ids))

        let seats = birds.indices.map { Vec3(Double($0) * 1.5, 0, -5) }
        let crowd = try XCTUnwrap(Simulation.crowdWalk(birds, to: seats, at: 0, fps: 30, current: document.scene,
                                                       timeline: document.scene.timeline, ids: &ids))
        let walked = try assertReverts(crowd, on: document)
        let arrived = Animator.evaluate(walked, at: 60).scene
        for (index, bird) in birds.enumerated() {
            let p = arrived.objects[bird]!.transform.position
            XCTAssertLessThan(Vec3(p.x - seats[index].x, 0, p.z - seats[index].z).length, 0.35, "everyone reaches their seat")
        }
    }
}
