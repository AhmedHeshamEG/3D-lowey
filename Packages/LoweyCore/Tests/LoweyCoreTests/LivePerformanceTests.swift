@testable import LoweyCore
import XCTest

/// Maquette 0.10: takes and comping, dangling bones, the face and hands on skeletons, breathing, triggers, the voice.
final class LivePerformanceTests: XCTestCase {
    // MARK: Fixtures

    /// A cube with a three-joint tail drawn out of its side: root in the middle, the tail running along +x.
    private func tailed() throws -> Document {
        var document = makeDocument()
        document.scene = Scene(id: "scene-1", name: "Test")
        var cube = SceneObject(id: "body", name: "Body", kind: .primitive(.cube))
        cube.rig = ObjectRig(names: ["root", "t1", "t2", "t3"], parents: [nil, 0, 1, 2],
                             positions: [Vec3(0, 0, 0), Vec3(0.5, 0, 0), Vec3(1, 0, 0), Vec3(1.5, 0, 0)], tips: ["t3": Vec3(2, 0, 0)])
        _ = try EditCommand.insert(SceneFragment(object: cube), parent: nil, index: nil).apply(to: &document)
        return document
    }

    /// The body slides along z from 1 s to 1.5 s and stops.
    private func sliding(_ document: Document) throws -> Document {
        var result = document
        let track = Track(id: "slide", target: "body", property: .position, keyframes: [
            Keyframe(time: 1, value: .vec3(.zero), easing: .linear), Keyframe(time: 1.5, value: .vec3(Vec3(0, 0, 2)), easing: .linear)
        ])
        _ = try EditCommand.setTracks([TrackEdit(track)]).apply(to: &result)
        return result
    }

    private func tip(_ animated: AnimatedScene, joint: Int = 3) throws -> Vec3 {
        let object = try XCTUnwrap(animated.scene.objects["body"])
        let rig = try XCTUnwrap(object.rig)
        let model = try rig.skeleton.modelSpace(XCTUnwrap(animated.poses["body"]))
        return RigSpace.frame(of: "body", in: animated.scene).apply(to: model[joint].position)
    }

    /// A stick figure standing at the origin, facing +z, arms hanging: the humanoid standard's names.
    private func person() throws -> Document {
        var document = makeDocument()
        document.scene = Scene(id: "scene-1", name: "Test")
        var body = SceneObject(id: "person", name: "Person", kind: .primitive(.cube))
        let names = ["hips", "spine", "chest", "neck", "head", "leftUpperArm", "leftLowerArm", "leftHand", "rightUpperArm", "rightLowerArm",
                     "rightHand"]
        let parents: [Int?] = [nil, 0, 1, 2, 3, 2, 5, 6, 2, 8, 9]
        let positions = [Vec3(0, 1, 0), Vec3(0, 1.2, 0), Vec3(0, 1.4, 0), Vec3(0, 1.55, 0), Vec3(0, 1.65, 0), Vec3(0.2, 1.45, 0),
                         Vec3(0.25, 1.15, 0), Vec3(0.28, 0.85, 0), Vec3(-0.2, 1.45, 0), Vec3(-0.25, 1.15, 0), Vec3(-0.28, 0.85, 0)]
        body.rig = ObjectRig(names: names, parents: parents, positions: positions, standard: .humanoid, tips: ["head": Vec3(0, 1.85, 0)])
        _ = try EditCommand.insert(SceneFragment(object: body), parent: nil, index: nil).apply(to: &document)
        return document
    }

    private func joint(_ name: String, of animated: AnimatedScene, in id: ObjectID = "person") throws -> Transform {
        let rig = try XCTUnwrap(animated.scene.objects[id]?.rig)
        let pose = try XCTUnwrap(animated.poses[id])
        return try rig.skeleton.modelSpace(pose)[XCTUnwrap(rig.skeleton.index(of: name))]
    }

    private func set(_ changes: [PropertyChange], on document: Document) throws -> Document {
        var result = document
        _ = try EditCommand.setProperties(changes).apply(to: &result)
        return result
    }

    // MARK: Dangle

    func testADanglingTailTrailsThenSwingsPastThenSettles() throws {
        let loose = try set([PropertyChange(object: "body", key: .dangle("t1"), value: .float(0.8)),
                             PropertyChange(object: "body", key: .dangle("t2"), value: .float(0.8))], on: sliding(tailed()))
        // At rest before anything moves: exactly as drawn.
        XCTAssertTrue(try tip(Animator.evaluate(loose, at: 0.5)).isApproximately(Vec3(1.5, 0, 0), tolerance: 1e-9))
        // Mid-slide the body is at z = 1; the tail's end hasn't caught up.
        let trailing = try tip(Animator.evaluate(loose, at: 1.25))
        XCTAssertLessThan(trailing.z, 0.85)
        // Just after the stop it has swung past where it rests.
        let after = try (1 ... 20).map { try tip(Animator.evaluate(loose, at: 1.5 + Double($0) * 0.03)).z }
        XCTAssertGreaterThan(try XCTUnwrap(after.max()), 2.03)
        // And then it hangs still again, as drawn.
        XCTAssertTrue(try tip(Animator.evaluate(loose, at: 4)).isApproximately(Vec3(1.5, 0, 2), tolerance: 1e-6))
        // The bones keep their length.
        let animated = Animator.evaluate(loose, at: 1.25)
        XCTAssertEqual(try tip(animated, joint: 2).distance(to: tip(animated, joint: 3)), 0.5, accuracy: 1e-6)
    }

    func testWithoutDangleNothingMovesAndTheSameTimeGivesTheSamePicture() throws {
        let stiff = try sliding(tailed())
        XCTAssertTrue(try tip(Animator.evaluate(stiff, at: 1.25)).isApproximately(Vec3(1.5, 0, 1), tolerance: 1e-9))
        let loose = try set([PropertyChange(object: "body", key: .dangle("t1"), value: .float(1))], on: stiff)
        let once = Animator.evaluate(loose, at: 1.4)
        let again = Animator.evaluate(loose, at: 1.4)
        XCTAssertEqual(once.poses, again.poses)
        // Looser trails further than tighter.
        let tight = try set([PropertyChange(object: "body", key: .dangle("t1"), value: .float(0.1))], on: stiff)
        XCTAssertLessThan(try tip(once).z, try tip(Animator.evaluate(tight, at: 1.4)).z)
    }

    func testALiveTurnDanglesBeforeItIsKeyed() throws {
        let loose = try set([PropertyChange(object: "body", key: .dangle("t2"), value: .float(0.9))], on: tailed())
        let turned: [ObjectID: [PropertyKey: PropertyValue]] = ["body": [.boneTurn("t1"): .quat(Quat(angle: 0.9, axis: .unitY))]]
        // The joint above was turned a moment ago and the playhead stands still: only the live past knows it moved.
        let past = LivePast(moments: [LivePast.Moment(ago: 0, overrides: turned), LivePast.Moment(ago: 0.1, overrides: [:])], playing: false)
        let following = Animator.evaluate(loose, at: 0, overrides: turned, live: past)
        let rigid = Animator.evaluate(loose, at: 0, overrides: turned)
        XCTAssertGreaterThan(try tip(following).distance(to: tip(rigid)), 0.05)
        XCTAssertEqual(past.overrides(ago: 0.05)?.isEmpty, true)
        XCTAssertNotNil(past.overrides(ago: 5))
    }

    // MARK: Face and hands on skeletons

    func testHeadChannelsTurnAHumanoidsHeadAndNeck() throws {
        let turned = try set([PropertyChange(object: "person", key: .headYaw, value: .float(40))], on: person())
        let animated = Animator.evaluate(turned, at: 0)
        let forward = try joint("head", of: animated).rotation.act(.unitZ)
        // Forty degrees to the side, shared between neck and head.
        XCTAssertEqual(atan2(forward.x, forward.z) * 180 / .pi, 40, accuracy: 0.5)
        let neck = try joint("neck", of: animated).rotation.act(.unitZ)
        XCTAssertEqual(atan2(neck.x, neck.z) * 180 / .pi, 14, accuracy: 0.5)
        // Nothing asked, nothing turned.
        XCTAssertTrue(try joint("head", of: Animator.evaluate(person(), at: 0)).rotation.isApproximately(.identity))
    }

    func testACustomSkeletonTurnsTheJointItNamesAndADrawingTiltsInItsPlane() throws {
        var document = try tailed()
        document = try set([PropertyChange(object: "body", key: .liveHead, value: .string("t3")),
                            PropertyChange(object: "body", key: .headYaw, value: .float(30))], on: document)
        let animated = Animator.evaluate(document, at: 0)
        let rig = try XCTUnwrap(animated.scene.objects["body"]?.rig)
        let forward = try rig.skeleton.modelSpace(XCTUnwrap(animated.poses["body"]))[3].rotation.act(.unitZ)
        XCTAssertEqual(atan2(forward.x, forward.z) * 180 / .pi, 30, accuracy: 0.5)
        XCTAssertEqual(LiveRig.planeNormal(of: Skeleton(joints: [
            Joint(name: "a", parent: nil, rest: Transform()), Joint(name: "b", parent: 0, rest: Transform(position: Vec3(1, 0, 0))),
            Joint(name: "c", parent: 1, rest: Transform(position: Vec3(0, 1, 0)))
        ])).z, 1, accuracy: 1e-9)
    }

    func testHandChannelsBringAHumanoidsHandsUpByIK() throws {
        let raised = try set([PropertyChange(object: "person", key: .handLeftY, value: .float(1))], on: person())
        let animated = Animator.evaluate(raised, at: 0)
        // The picture's left is the model's −x arm: its hand goes above the shoulder; the other arm hangs.
        XCTAssertGreaterThan(try joint("rightHand", of: animated).position.y, 1.75)
        XCTAssertEqual(try joint("leftHand", of: animated).position.y, 0.85, accuracy: 1e-6)
        // The arm keeps its length.
        let upper = try joint("rightUpperArm", of: animated).position
        let lower = try joint("rightLowerArm", of: animated).position
        XCTAssertEqual(upper.distance(to: lower), Vec3(-0.2, 1.45, 0).distance(to: Vec3(-0.25, 1.15, 0)), accuracy: 1e-6)
    }

    func testAPartRidesItsBoneAndBlinksOnItsOwn() throws {
        var document = try person()
        var eye = SceneObject(id: "eye", name: "Eye", kind: .primitive(.sphere),
                              transform: Transform(position: Vec3(0.05, 1.7, 0.1), scale: Vec3(0.04, 0.04, 0.04)))
        eye[.attachBone] = .string("head")
        eye[.faceRole] = .string("eye.L")
        _ = try EditCommand.insert(SceneFragment(object: eye), parent: "person", index: nil).apply(to: &document)
        let rest = try XCTUnwrap(Animator.evaluate(document, at: 0).scene.objects["eye"]).transform
        XCTAssertTrue(rest.position.isApproximately(Vec3(0.05, 1.7, 0.1), tolerance: 1e-9))
        // The head tilts; the eye goes with it, around the head joint.
        let tilted = try set([PropertyChange(object: "person", key: .boneTurn("head"), value: .quat(Quat(angle: .pi / 2, axis: .unitZ)))],
                             on: document)
        let moved = try XCTUnwrap(Animator.evaluate(tilted, at: 0).scene.objects["eye"]).transform
        XCTAssertTrue(moved.position.isApproximately(Vec3(-0.05, 1.7, 0.1), tolerance: 1e-9), "\(moved.position)")
        // Asked to blink on its own, the eye closes now and then; with blinks keyed it's left alone.
        let blinking = try set([PropertyChange(object: "person", key: .autoBlink, value: .bool(true))], on: document)
        let heights = stride(from: 0.0, to: 8, by: 0.02).map { Animator.evaluate(blinking, at: $0).scene.objects["eye"]?.transform.scale.y ?? 0 }
        XCTAssertLessThan(try XCTUnwrap(heights.min()), 0.01)
        XCTAssertEqual(try XCTUnwrap(heights.max()), 0.04, accuracy: 1e-9)
        XCTAssertEqual(try LiveRig.nearestJoint(to: Vec3(0.26, 1, 0), of: XCTUnwrap(document.scene.objects["person"]?.rig)), "leftLowerArm")
    }

    func testBreathingFillsTheChestAndComesBack() throws {
        let breathing = try set([PropertyChange(object: "person", key: .breathe, value: .float(1))], on: person())
        let depths = stride(from: 0.0, to: 7.2, by: 0.1).map { Animator.evaluate(breathing, at: $0).poses["person"]?[2].scale.z ?? 1 }
        XCTAssertEqual(try XCTUnwrap(depths.max()), 1.045, accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(depths.min()), 0.955, accuracy: 0.002)
        XCTAssertEqual(Idle.breathing(at: 1, seed: "a"), Idle.breathing(at: 1 + Idle.breath, seed: "a"), accuracy: 1e-9)
        // Something with no chest breathes with its whole body.
        let blob = try set([PropertyChange(object: "body", key: .breathe, value: .float(1))], on: tailed())
        let heights = stride(from: 0.0, to: 3.6, by: 0.1).map { Animator.evaluate(blob, at: $0).scene.objects["body"]?.transform.scale.y ?? 1 }
        XCTAssertGreaterThan(try XCTUnwrap(heights.max()), 1.01)
    }

    // MARK: Takes

    private func performed(_ values: [Double], from start: Double, on object: ObjectID = "body", _ key: PropertyKey = .smile) -> PerformTake {
        var take = PerformTake(object: object, property: key)
        take.begin()
        for (index, value) in values.enumerated() {
            take.add(.init(time: start + Double(index) / 30, value: .float(value)))
        }
        return take
    }

    func testARecordingIsKeptAsATakeAndBecomesTheComp() throws {
        var document = try tailed()
        var ids = IDFactory.sequential("k")
        let first = try XCTUnwrap(TakeComp.recording([performed([Double](repeating: 1, count: 61), from: 1)], fps: 30, smoothing: 0,
                                                     timeline: document.scene.timeline, ids: &ids))
        document = try assertReverts(first, on: document)
        XCTAssertEqual(document.scene.timeline.takes.map(\.name), ["Take 1"])
        XCTAssertEqual(document.scene.timeline.takes[0].used, [TimeRange(start: 1, end: 3)])
        XCTAssertEqual(document.scene.timeline.track(for: "body", .smile)?.value(at: 2), .float(1))
        // A second try over the middle: both are kept, the new one plays where it was performed.
        let second = try XCTUnwrap(TakeComp.recording([performed([Double](repeating: 0.25, count: 31), from: 1.5)], fps: 30, smoothing: 0,
                                                      timeline: document.scene.timeline, ids: &ids))
        document = try assertReverts(second, on: document)
        let takes = document.scene.timeline.takes
        XCTAssertEqual(takes.map(\.name), ["Take 1", "Take 2"])
        XCTAssertEqual(takes[1].used, [TimeRange(start: 1.5, end: 2.5)])
        XCTAssertEqual(takes[0].used, [TimeRange(start: 1, end: 1.5), TimeRange(start: 2.5, end: 3)])
        let track = try XCTUnwrap(document.scene.timeline.track(for: "body", .smile))
        XCTAssertEqual(track.value(at: 2), .float(0.25))
        XCTAssertEqual(track.value(at: 1.2), .float(1))
        XCTAssertEqual(track.value(at: 2.9), .float(1))
        // The first take is whole, whatever the comp plays.
        XCTAssertEqual(takes[0].channels[0].value(at: 2), .float(1))
    }

    func testUsingATakeOverAStretchPutsItBackThereAndOnlyThere() throws {
        var document = try tailed()
        var ids = IDFactory.sequential("k")
        for (level, start, count) in [(1.0, 1.0, 61), (0.25, 1.0, 61)] {
            let command = try XCTUnwrap(TakeComp.recording([performed([Double](repeating: level, count: count), from: start)], fps: 30,
                                                           smoothing: 0, timeline: document.scene.timeline, ids: &ids))
            document = try assertReverts(command, on: document)
        }
        let firstID = document.scene.timeline.takes[0].id
        XCTAssertEqual(document.scene.timeline.takes[0].used, [])
        let use = try XCTUnwrap(TakeComp.using(firstID, over: TimeRange(start: 2, end: 2.5), timeline: document.scene.timeline, ids: &ids))
        XCTAssertEqual(use.label, "Use Take 1")
        document = try assertReverts(use, on: document)
        let track = try XCTUnwrap(document.scene.timeline.track(for: "body", .smile))
        XCTAssertEqual(track.value(at: 2.25), .float(1))
        XCTAssertEqual(try XCTUnwrap(track.value(at: 2)?.floatValue), 1, accuracy: 1e-9)
        // A frame outside the stretch the other take still plays, untouched.
        XCTAssertEqual(track.value(at: 2 - 1.0 / 30), .float(0.25))
        XCTAssertEqual(track.value(at: 2.5 + 1.0 / 30), .float(0.25))
        XCTAssertEqual(track.value(at: 1.5), .float(0.25))
        XCTAssertEqual(document.scene.timeline.takes[0].used, [TimeRange(start: 2, end: 2.5)])
        XCTAssertEqual(document.scene.timeline.takes[1].used, [TimeRange(start: 1, end: 2), TimeRange(start: 2.5, end: 3)])
        // A stretch that misses the take does nothing; deleting a take leaves what plays.
        XCTAssertNil(TakeComp.using(firstID, over: TimeRange(start: 5, end: 6), timeline: document.scene.timeline, ids: &ids))
        let before = document.scene.timeline.tracks
        document = try assertReverts(XCTUnwrap(TakeComp.removing(firstID, timeline: document.scene.timeline)), on: document)
        XCTAssertEqual(document.scene.timeline.tracks, before)
        XCTAssertEqual(document.scene.timeline.takes.count, 1)
        let renamed = try XCTUnwrap(TakeComp.renaming(document.scene.timeline.takes[0].id, to: "The good one", timeline: document.scene.timeline))
        XCTAssertEqual(try assertReverts(renamed, on: document).scene.timeline.takes[0].name, "The good one")
    }

    func testTakesSurviveTheSceneFileAndRangesMerge() throws {
        var document = try tailed()
        var ids = IDFactory.sequential("k")
        let command = try XCTUnwrap(TakeComp.recording([performed([0, 0.5, 1], from: 0)], fps: 30, smoothing: 0, timeline: document.scene.timeline,
                                                       ids: &ids))
        _ = try command.apply(to: &document)
        let data = try SchemaCoder.shared.encode(document.scene, kind: .scene)
        XCTAssertEqual(try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: data).timeline.takes, document.scene.timeline.takes)
        XCTAssertEqual(TakeComp.merged([TimeRange(start: 2, end: 3), TimeRange(start: 0, end: 1), TimeRange(start: 1, end: 2.5)]),
                       [TimeRange(start: 0, end: 3)])
        XCTAssertEqual(TakeComp.subtract(TimeRange(start: 1, end: 2), from: TimeRange(start: 0, end: 3)),
                       [TimeRange(start: 0, end: 1), TimeRange(start: 2, end: 3)])
    }

    // MARK: Triggers

    func testATriggerPressedAndLetGoIsHeldKeysAtItsOwnMoments() throws {
        var take = PerformTake(object: "body", property: .smile, stepped: true)
        take.begin()
        take.add(.init(time: 1.013, value: .float(0)))
        take.add(.init(time: 1.013, value: .float(0.8)))
        take.add(.init(time: 1.5, value: .float(0.8)))
        take.add(.init(time: 1.731, value: .float(0)))
        let keys = PerformBaker.keys(from: take.segments[0], fps: 30, smoothing: 0.5, stepped: take.isStepped)
        XCTAssertEqual(keys.map(\.time), [1.013, 1.731])
        XCTAssertEqual(keys.map(\.value), [.float(0.8), .float(0)])
        XCTAssertTrue(keys.allSatisfy { $0.easing == .step })
        // A mouth shape is a switch whether or not anyone says so.
        var mouth = PerformTake(object: "body", property: .mouth)
        mouth.add(.init(time: 0, value: .enumeration("A")))
        XCTAssertTrue(mouth.isStepped)
        XCTAssertFalse(performed([0, 1], from: 0).isStepped)
    }

    func testTheDeckIsKeptOnTheCharacterAndASwapShowsOneThingAtATime() throws {
        var document = try tailed()
        var ids = IDFactory.sequential("g")
        for name in ["Cup", "Sword"] {
            let prop = SceneObject(id: ObjectID(raw: name.lowercased()), name: name, kind: .primitive(.cube))
            _ = try EditCommand.insert(SceneFragment(object: prop), parent: "body", index: nil).apply(to: &document)
        }
        var deck = TriggerDeck.swap(of: ["cup", "sword"], in: document.scene, deck: [], ids: &ids)
        XCTAssertEqual(deck.map(\.name), ["Cup", "Sword"])
        XCTAssertEqual(deck.map(\.key), ["1", "2"])
        deck.append(Trigger(id: "happy", name: "Happy", kind: .expression, key: TriggerDeck.freeKey(in: deck), holds: true, expression: .happy))
        document = try assertReverts(.setProperties([TriggerDeck.storing(deck, on: "body")]), on: document)
        XCTAssertEqual(try TriggerDeck.triggers(of: XCTUnwrap(document.scene.objects["body"])), deck)
        let swap = TriggerDeck.changes(for: deck[1], on: "body", in: document.scene)
        XCTAssertEqual(swap, [PropertyChange(object: "sword", key: .visible, value: .bool(true)),
                              PropertyChange(object: "cup", key: .visible, value: .bool(false))])
        // Letting go puts back what was showing.
        XCTAssertEqual(TriggerDeck.restoring(swap, in: document.scene).map(\.value), [.bool(true), .bool(true)])
        let happy = TriggerDeck.changes(for: deck[2], on: "body", in: document.scene)
        XCTAssertEqual(happy.first { $0.key == .smile }?.value, .float(0.8))
        XCTAssertEqual(TriggerDeck.restoring(happy, in: document.scene).first { $0.key == .smile }?.value, .float(0))
        // Fired at the playhead: held keys, with what was there before kept at the start.
        let edits = TriggerDeck.keyed(swap, at: 2, in: document.scene, timeline: document.scene.timeline, ids: &ids)
        document = try assertReverts(.setTracks(edits), on: document)
        XCTAssertEqual(Animator.evaluate(document, at: 1).scene.objects["cup"]?.isVisible, true)
        XCTAssertEqual(Animator.evaluate(document, at: 2.5).scene.objects["cup"]?.isVisible, false)
    }

    func testAPoseTriggerTurnsTheJointsThePoseKept() throws {
        var document = try tailed()
        let pose = CharacterPose(id: "curl", name: "Curl", joints: ["t1": Quat(angle: 0.6, axis: .unitZ)])
        document = try set([PoseLibrary.storing([pose], on: "body")], on: document)
        let trigger = Trigger(id: "t", name: "Curl", kind: .pose, pose: "curl")
        let changes = TriggerDeck.changes(for: trigger, on: "body", in: document.scene)
        XCTAssertEqual(changes, [PropertyChange(object: "body", key: .boneTurn("t1"), value: .quat(Quat(angle: 0.6, axis: .unitZ)))])
        XCTAssertEqual(try JSONDecoder().decode(Trigger.self, from: JSONEncoder().encode(trigger)), trigger)
    }

    // MARK: Voice

    /// A voiced sound: harmonics of a pitch, loudest near two formants.
    private func vowel(_ first: Double, _ second: Double, pitch: Double = 120, seconds: Double = 0.4, rate: Double = 44100) -> [Float] {
        (0 ..< Int(seconds * rate)).map { index in
            var sample = 0.0
            var harmonic = pitch
            while harmonic < 5000 {
                let near = exp(-pow((harmonic - first) / 110, 2)) + 0.25 * exp(-pow((harmonic - second) / 160, 2))
                sample += (near + 0.01) * sin(2 * .pi * harmonic * Double(index) / rate)
                harmonic += pitch
            }
            return Float(sample * 0.12)
        }
    }

    private func hiss(seconds: Double = 0.4, rate: Double = 44100) -> [Float] {
        var random = SeededRandom(seed: 7)
        var previous = 0.0
        return (0 ..< Int(seconds * rate)).map { _ in
            let white = random.unit() * 2 - 1
            let high = white - previous
            previous = white
            return Float(high * 0.2)
        }
    }

    private func mouths(_ sound: [Float], solver: inout VoiceSolver) -> [VoiceSolver.Mouth] {
        stride(from: 0, to: sound.count - 1024, by: 1024).map { solver.process(Array(sound[$0 ..< $0 + 1024])) }
    }

    func testTheVoiceOpensTheMouthAndTheSoundPicksItsShape() throws {
        var solver = VoiceSolver(sampleRate: 44100)
        let quiet = [Float](repeating: 0.0005, count: 22050)
        XCTAssertTrue(mouths(quiet, solver: &solver).allSatisfy { $0.viseme == .X && $0.jaw < 0.01 })
        let ah = try XCTUnwrap(mouths(vowel(730, 1090), solver: &solver).last)
        XCTAssertTrue([.C, .D].contains(ah.viseme), "\(ah)")
        XCTAssertGreaterThan(ah.jaw, 0.5)
        _ = mouths(quiet, solver: &solver)
        let ee = try XCTUnwrap(mouths(vowel(270, 2290), solver: &solver).last)
        XCTAssertEqual(ee.viseme, .B, "\(ee)")
        XCTAssertGreaterThan(ee.wide, 0)
        _ = mouths(quiet, solver: &solver)
        let oo = try XCTUnwrap(mouths(vowel(300, 870), solver: &solver).last)
        XCTAssertTrue([.F, .E].contains(oo.viseme), "\(oo)")
        XCTAssertLessThan(oo.wide, 0)
        XCTAssertLessThan(oo.jaw, ah.jaw)
        _ = mouths(quiet, solver: &solver)
        XCTAssertEqual(try XCTUnwrap(mouths(hiss(), solver: &solver).last).viseme, .B)
        // Silence closes it again.
        let closed = try XCTUnwrap(mouths(quiet, solver: &solver).last)
        XCTAssertEqual(closed.viseme, .X)
        XCTAssertLessThan(closed.jaw, 0.02)
        XCTAssertEqual(VoiceSolver.channels(ah)[.mouth], .enumeration(ah.viseme.rawValue))
    }
}
