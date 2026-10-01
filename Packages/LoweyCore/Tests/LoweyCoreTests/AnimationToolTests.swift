import Foundation
@testable import LoweyCore
import XCTest

/// Key editing, presets, Perform takes, camera moves and simulations.
final class AnimationToolTests: XCTestCase {
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
}
