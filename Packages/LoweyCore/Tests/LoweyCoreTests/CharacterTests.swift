@testable import LoweyCore
import XCTest

final class CharacterTests: XCTestCase {
    private func characterDocument(_ recipe: CharacterRecipe = CharacterRecipe(extras: [.glasses, .beard])) throws -> (Document, ObjectID) {
        var document = makeDocument()
        var ids = IDFactory.sequential("h")
        let fragment = CharacterBuilder.build(recipe, ids: &ids)
        let command = EditCommand.insert(fragment, parent: nil, index: nil)
        document = try assertReverts(command, on: document)
        return (document, fragment.roots[0])
    }

    func testBuilderMakesAHumanoidPuppetWithAFace() throws {
        let (document, root) = try characterDocument()
        let scene = document.scene
        XCTAssertTrue(scene.validate().isEmpty)
        let bones = Set(scene.subtree(of: root).compactMap { scene.objects[$0]?[.bone]?.stringValue })
        for bone in ["hips", "spine", "chest", "neck", "head", "leftUpperArm", "leftLowerArm", "leftHand", "rightUpperLeg", "rightFoot"] {
            XCTAssertTrue(bones.contains(bone), bone)
        }
        let roles = scene.subtree(of: root).compactMap { scene.objects[$0]?[.faceRole]?.stringValue }
        for role in ["eye.L", "eye.R", "brow.L", "brow.R", "mouth", "mouth.A", "mouth.D", "mouth.X"] {
            XCTAssertTrue(roles.contains(role), role)
        }
        // Only the rest mouth is visible at first.
        let visibleMouths = scene.subtree(of: root).filter {
            (scene.objects[$0]?[.faceRole]?.stringValue?.hasPrefix("mouth.") ?? false) && (scene.objects[$0]?.isVisible ?? false)
        }
        XCTAssertEqual(visibleMouths.map { scene.objects[$0]?[.faceRole]?.stringValue }, ["mouth.X"])
        // Stands on the ground, about 1.7 m tall.
        let bounds = try XCTUnwrap(SceneBounds().worldBounds(of: root, in: scene))
        XCTAssertEqual(bounds.min.y, 0, accuracy: 0.08)
        XCTAssertEqual(bounds.size.y, 1.7, accuracy: 0.25)
        // The recipe travels with the character (re-open in the builder).
        let json = try XCTUnwrap(scene.objects[root]?[.characterRecipe]?.stringValue)
        XCTAssertEqual(try LoweyJSON.decode(CharacterRecipe.self, from: Data(json.utf8)).extras, [.glasses, .beard])
        // Every combination builds.
        for hair in CharacterRecipe.Hair.allCases {
            for top in CharacterRecipe.Top.allCases {
                var ids = IDFactory.sequential("x")
                let recipe = CharacterRecipe(
                    head: .square,
                    hair: hair,
                    eyes: .round,
                    body: .broad,
                    top: top,
                    bottom: .skirt,
                    extras: CharacterRecipe.Extra.allCases
                )
                XCTAssertGreaterThan(CharacterBuilder.build(recipe, ids: &ids).objects.count, 50)
            }
        }
    }

    func testPuppetRigIsATPoseSkeleton() throws {
        let (document, root) = try characterDocument()
        let puppet = try XCTUnwrap(PuppetRig.build(root, in: document.scene))
        let skeleton = puppet.rig.skeleton
        XCTAssertEqual(puppet.rig.standard, .humanoid)
        XCTAssertEqual(skeleton.joints.count, puppet.joints.count)
        let model = skeleton.modelRest
        let leftUpper = try XCTUnwrap(skeleton.index(of: "leftUpperArm"))
        let leftLower = try XCTUnwrap(skeleton.index(of: "leftLowerArm"))
        let armDirection = (model[leftLower].position - model[leftUpper].position).normalized
        XCTAssertEqual(armDirection.x, 1, accuracy: 1e-6, "left arm straight out along +X in the rig's T-pose")
        let rightUpper = try XCTUnwrap(skeleton.index(of: "rightUpperArm"))
        let rightLower = try XCTUnwrap(skeleton.index(of: "rightLowerArm"))
        XCTAssertEqual((model[rightLower].position - model[rightUpper].position).normalized.x, -1, accuracy: 1e-6)
        XCTAssertNil(PuppetRig.build("c", in: document.scene), "not a character")
        XCTAssertEqual(Quat.between(Vec3(0, -1, 0), Vec3(0, 1, 0)).act(Vec3(0, -1, 0)).y, 1, accuracy: 1e-9)
    }

    func testBuiltInClipsPlayOnTheBuiltCharacter() throws {
        var (document, root) = try characterDocument(CharacterRecipe(height: 1.2))
        XCTAssertEqual(Set(BuiltinClips.rig.clipNames), Set(BuiltinClips.names))
        let walk = try XCTUnwrap(BuiltinClips.rig.clips["Walk"])
        XCTAssertNotNil(BuiltinClips.rig.strideSpeed(of: walk), "the walk has a measurable stride")
        let segment = ClipSegment(id: "s", clip: ClipRef(asset: BuiltinClips.assetID, name: "Walk"), start: 0, duration: 4, loop: true)
        document.scene.timeline.clipTracks = [ClipTrack(id: "t", target: root, segments: [segment])]
        let leftLeg = try XCTUnwrap(document.scene.subtree(of: root).first { document.scene.objects[$0]?[.bone]?.stringValue == "leftUpperLeg" })
        let leftArm = try XCTUnwrap(document.scene.subtree(of: root).first { document.scene.objects[$0]?[.bone]?.stringValue == "leftUpperArm" })
        let a = Animator.evaluate(document, at: 0.26)
        let b = Animator.evaluate(document, at: 0.78)
        XCTAssertTrue(a.animated.contains(leftLeg))
        let legA = a.scene.objects[leftLeg]!.transform.rotation.act(Vec3(0, -1, 0))
        let legB = b.scene.objects[leftLeg]!.transform.rotation.act(Vec3(0, -1, 0))
        XCTAssertGreaterThan(legA.z * legB.z < 0 ? 1 : 0, 0, "the leg swings forward, then back")
        // Arms hang down while walking (not T-posing).
        let arm = a.scene.worldTransform(of: leftArm).rotation.act(Vec3(0, -1, 0))
        XCTAssertLessThan(arm.y, -0.8)
        // Without a clip the character keeps its built pose.
        document.scene.timeline.clipTracks = []
        XCTAssertEqual(Animator.evaluate(document, at: 0.26).scene.objects[leftLeg]?.transform, document.scene.objects[leftLeg]?.transform)
        // An imported humanoid clip (a different skeleton) retargets onto it too.
        XCTAssertNotNil(Retargeter.retarget(pose: walk.pose(at: 0.2, skeleton: BuiltinClips.rig.skeleton), from: BuiltinClips.rig,
                                            to: PuppetRig.build(root, in: document.scene)!.rig).first)
    }

    func testFaceChannelsMoveTheFace() throws {
        var (document, root) = try characterDocument()
        let scene = document.scene
        func part(_ role: String) -> ObjectID { scene.subtree(of: root).first { scene.objects[$0]?[.faceRole]?.stringValue == role }! }
        document.scene.objects[root]?[.blinkLeft] = .float(1)
        document.scene.objects[root]?[.brows] = .float(1)
        document.scene.objects[root]?[.mouth] = .enumeration("D")
        document.scene.objects[root]?[.headYaw] = .float(30)
        let result = Animator.evaluate(document, at: 0).scene
        XCTAssertLessThan(result.objects[part("eye.L")]!.transform.scale.y, scene.objects[part("eye.L")]!.transform.scale.y * 0.2, "blinks")
        XCTAssertEqual(result.objects[part("eye.R")]!.transform.scale.y, scene.objects[part("eye.R")]!.transform.scale.y, "one eye only")
        XCTAssertGreaterThan(result.objects[part("brow.L")]!.transform.position.y, scene.objects[part("brow.L")]!.transform.position.y)
        XCTAssertTrue(result.objects[part("mouth.D")]!.isVisible)
        XCTAssertFalse(result.objects[part("mouth.X")]!.isVisible)
        let head = scene.subtree(of: root).first { scene.objects[$0]?[.bone]?.stringValue == "head" }!
        XCTAssertGreaterThan(result.objects[head]!.transform.rotation.act(Vec3(0, 0, 1)).x, 0.4, "head turns")
    }

    func testLipSyncFromWords() throws {
        XCTAssertGreaterThan(Phonemizer.shared.dictionarySize, 100_000, "the pronouncing dictionary ships with Core")
        let enigma = Phonemizer.shared.visemes(for: "Enigma,", language: "en-US")
        XCTAssertEqual(enigma.map(\.0), [.B, .B, .B, .B, .A, .C])
        XCTAssertEqual(Phonemizer.shared.visemes(for: "Blorptastic", language: "en-US").first?.0, .A, "rules for unknown words")
        XCTAssertFalse(Phonemizer.shared.visemes(for: "1941", language: "en-US").isEmpty, "numbers are spelled out")
        XCTAssertEqual(Phonemizer.shared.visemes(for: "mamma", language: "it-IT").map(\.0), [.A, .D, .A, .A, .D])
        let arabic = Phonemizer.shared.visemes(for: "مرحبا", language: "ar-SA")
        XCTAssertEqual(arabic.first?.0, .A)
        XCTAssertTrue(arabic.contains { $0.0 == .D }, "the long a opens the mouth")
        let words = [
            TimelineWord(clip: "vo", index: 0, text: "Nobody", start: 1, end: 1.5),
            TimelineWord(clip: "vo", index: 1, text: "could.", start: 1.5, end: 1.9),
            TimelineWord(clip: "vo", index: 2, text: "Zzzq", start: 3, end: 3.4)
        ]
        let shapes = LipSync.shapes(for: words, language: "en-US", loudness: Array(repeating: 0.8, count: 200), fps: 30)
        XCTAssertEqual(shapes.first?.time, 1)
        XCTAssertTrue(shapes.contains { $0.viseme == .X && abs($0.time - 1.9) < 1e-9 }, "rests in the pause")
        XCTAssertTrue(zip(shapes, shapes.dropFirst()).allSatisfy { $0.time <= $1.time && $0.viseme != $1.viseme })
        // Keys: one command, stepped mouth, reverts.
        let (document, root) = try characterDocument()
        var ids = IDFactory.sequential("k")
        let command = try XCTUnwrap(LipSync.keys(shapes, character: root, range: TimeRange(start: 1, end: 3.4), timeline: document.scene.timeline, ids: &ids))
        let synced = try assertReverts(command, on: document)
        let mouth = try XCTUnwrap(synced.scene.timeline.track(for: root, .mouth))
        XCTAssertTrue(mouth.keyframes.allSatisfy { $0.easing == .step })
        XCTAssertEqual(mouth.keyframes.last?.value, .enumeration("X"))
        let evaluated = Animator.evaluate(synced, at: 1.05).scene
        XCTAssertNotEqual(evaluated.objects[root]?[.mouth], .enumeration("X"))
        XCTAssertNotNil(synced.scene.timeline.track(for: root, .jawOpen))
        XCTAssertEqual(LipSync.thin([(.A, 1), (.B, 0.5), (.C, 1)], to: 2).count, 2)
        XCTAssertEqual(Viseme.D.jaw, 0.9)
    }

    func testFaceSolverAndSmoothing() {
        func face(eyeOpen: Double, mouthOpen: Double, browLift: Double, yaw: Double = 0) -> FaceLandmarks {
            func eye(_ x: Double) -> [Vec2] { [Vec2(x - 0.08, 0.6), Vec2(x + 0.08, 0.6), Vec2(x, 0.6 + eyeOpen / 2), Vec2(x, 0.6 - eyeOpen / 2)] }
            func brow(_ x: Double) -> [Vec2] { [Vec2(x - 0.08, 0.72 + browLift), Vec2(x + 0.08, 0.72 + browLift)] }
            return FaceLandmarks(
                leftEye: eye(0.3), rightEye: eye(0.7), leftBrow: brow(0.3), rightBrow: brow(0.7),
                outerLips: [Vec2(0.38, 0.25), Vec2(0.62, 0.25), Vec2(0.5, 0.28 + mouthOpen), Vec2(0.5, 0.22 - mouthOpen)],
                innerLips: [Vec2(0.42, 0.25), Vec2(0.58, 0.25), Vec2(0.5, 0.25 + mouthOpen), Vec2(0.5, 0.25 - mouthOpen)],
                leftPupil: Vec2(0.32, 0.6), rightPupil: Vec2(0.72, 0.6), yaw: yaw
            )
        }
        let neutral = FaceSolver.measure(face(eyeOpen: 0.06, mouthOpen: 0.005, browLift: 0))!
        let calm = FaceSolver.channels(face(eyeOpen: 0.06, mouthOpen: 0.005, browLift: 0), neutral: neutral)
        XCTAssertEqual(calm[.blinkLeft] ?? 1, 0, accuracy: 0.01)
        XCTAssertEqual(calm[.jawOpen] ?? 1, 0, accuracy: 0.01)
        let surprised = FaceSolver.channels(face(eyeOpen: 0.06, mouthOpen: 0.1, browLift: 0.05, yaw: 0.3), neutral: neutral)
        XCTAssertGreaterThan(surprised[.jawOpen] ?? 0, 0.5)
        XCTAssertGreaterThan(surprised[.brows] ?? 0, 0.5)
        XCTAssertEqual(surprised[.headYaw] ?? 0, 0.3 * 180 / .pi, accuracy: 1e-9)
        XCTAssertGreaterThan(surprised[.lookX] ?? 0, 0, "pupils a bit to the right")
        let blinking = FaceSolver.channels(face(eyeOpen: 0.005, mouthOpen: 0.005, browLift: 0), neutral: neutral)
        XCTAssertGreaterThan(blinking[.blinkLeft] ?? 0, 0.9)
        XCTAssertNil(FaceSolver.measure(FaceLandmarks(leftEye: [], rightEye: [], leftBrow: [], rightBrow: [], outerLips: [], innerLips: [])))
        var filter = OneEuroFilter()
        let jittery = (0 ..< 60).map { index in filter.filter(1 + (index.isMultiple(of: 2) ? 0.05 : -0.05), at: Double(index) / 30) }
        XCTAssertLessThan(abs((jittery.last ?? 0) - 1), 0.03, "jitter smoothed away")
    }
}
