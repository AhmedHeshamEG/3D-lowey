import Foundation
@testable import LoweyCore
import XCTest

final class BlobCharacterTests: XCTestCase {
    /// A document holding one built blob at `at`, with its floating behaviour.
    private func document(_ recipe: BlobRecipe = .hesham, at: Vec3 = Vec3(2, 0, -1)) throws -> (Document, ObjectID) {
        var ids = IDFactory.sequential("blob")
        let build = BlobCharacter.build(recipe, ids: &ids)
        var document = makeDocument()
        var fragment = build.fragment
        let root = try XCTUnwrap(fragment.roots.first)
        let index = try XCTUnwrap(fragment.objects.firstIndex { $0.id == root })
        fragment.objects[index].transform.position = at
        _ = try EditCommand.insert(fragment, parent: nil, index: nil).apply(to: &document)
        var timeline = document.scene.timeline
        timeline.behaviors += build.behaviors
        _ = try EditCommand.setTimeline(timeline).apply(to: &document)
        return (document, root)
    }

    private func role(_ name: String, in scene: Scene, under root: ObjectID) -> ObjectID? {
        scene.subtree(of: root).first { scene.objects[$0]?[.faceRole]?.stringValue == name }
    }

    func testHeshamIsARiggedCharacterWithAWholeFace() throws {
        let (document, root) = try document()
        let scene = document.scene
        XCTAssertTrue(scene.validate().isEmpty, "\(scene.validate())")
        XCTAssertEqual(scene.objects[root]?[.rigStandard]?.stringValue, "blob")
        for part in ["head", "eye.L", "eye.R", "pupil.L", "pupil.R", "brow.L", "brow.R", "mouth.lips", "mouth.curl", "mouth.inside",
                     "mouth.teeth", "mouth.tongue", "hand.L", "hand.R", "hover", "hat"] {
            XCTAssertNotNil(role(part, in: scene, under: root), "has \(part)")
        }
        // At rest: a calm closed mouth (the smirk is the smug face), the open-mouth layers wait.
        for (part, shown) in [("mouth.lips", true), ("mouth.curl", false), ("mouth.inside", false), ("mouth.teeth", false)] {
            XCTAssertEqual(role(part, in: scene, under: root).flatMap { scene.objects[$0]?[.visible]?.boolValue } ?? true, shown, part)
        }
        XCTAssertTrue(scene.subtree(of: root).contains { scene.objects[$0]?.name == "Beret" }, "his beret")
        XCTAssertTrue(scene.subtree(of: root).contains { scene.objects[$0]?.name == "Mark" }, "with the Pisces mark")
        XCTAssertEqual(document.scene.timeline.behaviors.count, 1, "he floats")
        // The recipe travels with him (rebuildable), and survives JSON.
        let json = try XCTUnwrap(scene.objects[root]?[.blobRecipe]?.stringValue)
        XCTAssertEqual(try LoweyJSON.decode(BlobRecipe.self, from: Data(json.utf8)), .hesham)
        XCTAssertEqual(try LoweyJSON.decode(BlobRecipe.self, from: Data(#"{"hat":"topHat"}"#.utf8)).hat, .topHat, "partial recipes fill in")
    }

    /// Keys `expression` on the character at `at` (as the Expressions buttons and the script action do).
    private func key(_ expression: FaceExpression, at time: Double, on root: ObjectID, in document: inout Document) throws {
        var ids = IDFactory.sequential("expr")
        _ = try EditCommand.setTimeline(expression.keyed(on: root, at: time, in: document.scene.timeline, ids: &ids)).apply(to: &document)
    }

    func testTheScriptKeysAnExpressionOnAWord() throws {
        let (document, root) = try document()
        let json = #"{"title": "Take", "actions": [{"do": "expression", "target": "\#(root.raw)", "name": "shocked", "at": 2}]}"#
        let script = try LoweyJSON.decode(SceneScript.self, from: Data(json.utf8))
        let applied = try ScriptCompiler.compile(script, document: document, context: ScriptContext()).document
        let mouth = applied.scene.timeline.tracks.first { $0.target == root && $0.property == .mouth }
        XCTAssertEqual(mouth?.value(at: 1)?.stringValue, "X", "calm before (a neutral key at 0)")
        XCTAssertEqual(mouth?.value(at: 2.5)?.stringValue, "D", "shocked from 2 s")
    }

    func testAnAtRestFaceIsNeverRebuilt() throws {
        let (document, root) = try document()
        let scene = document.scene
        let animated = Animator.evaluate(document, at: 0.5).animated
        for part in ["eye.L", "brow.L", "mouth.lips", "pupil.L", "head"] {
            XCTAssertFalse(try animated.contains(XCTUnwrap(role(part, in: scene, under: root))), "\(part) stays as built")
        }
    }

    func testAKeyedExpressionOvershootsThenSettles() throws {
        var (document, root) = try document()
        try key(.neutral, at: 0, on: root, in: &document)
        try key(.surprised, at: 1, on: root, in: &document)
        let base = document.scene
        let brow = try XCTUnwrap(role("brow.L", in: base, under: root))
        let head = try XCTUnwrap(role("head", in: base, under: root))
        func browHeight(_ t: Double) -> Double {
            let scene = Animator.evaluate(document, at: t).scene
            guard case let .drawing(recipe) = scene.objects[brow]?.kind, let points = recipe.strokes.first?.points else { return 0 }
            return points.map(\.y).reduce(0, +) / Double(points.count)
        }
        let settled = browHeight(3)
        let before = browHeight(0.9)
        XCTAssertGreaterThan(settled, before + 0.03, "surprise raises the brows")
        let peak = stride(from: 1.02, through: 1.5, by: 0.02).map(browHeight).max() ?? 0
        XCTAssertGreaterThan(peak, settled + 0.004, "…past where they end up (overshoot)")
        XCTAssertEqual(browHeight(2.8), settled, accuracy: 0.002, "and they settle")
        // The hit stretches the head, then it's back to round.
        let stretch = stride(from: 1.02, through: 1.4, by: 0.02).map { Animator.evaluate(document, at: $0).scene.objects[head]?.transform.scale.y ?? 1 }.max()
        XCTAssertGreaterThan(stretch ?? 1, 1.08, "squash & stretch on the hit")
        XCTAssertEqual(Animator.evaluate(document, at: 3).scene.objects[head]?.transform.scale.y ?? 0, 1 + 0.22 * 0.5, accuracy: 0.01)
    }

    func testHappyEyesAreCrescentsAndLipSyncOpensTheMouth() throws {
        var (document, root) = try document()
        try key(.laugh, at: 0, on: root, in: &document)
        let scene = Animator.evaluate(document, at: 2).scene
        let eye = try XCTUnwrap(role("eye.L", in: document.scene, under: root))
        guard case let .drawing(recipe) = scene.objects[eye]?.kind, let outline = recipe.strokes.first?.points else { return XCTFail("eye") }
        let height = (outline.map(\.y).max() ?? 0) - (outline.map(\.y).min() ?? 0)
        XCTAssertLessThan(height, BlobCharacter.eye.ry, "a squeezed crescent, not the round eye")
        let inside = try XCTUnwrap(role("mouth.inside", in: document.scene, under: root))
        XCTAssertEqual(scene.objects[inside]?[.visible]?.boolValue, true, "laughing: the mouth is open")
        let curl = try XCTUnwrap(role("mouth.curl", in: document.scene, under: root))
        XCTAssertEqual(scene.objects[curl]?[.visible]?.boolValue, false, "the smirk's curl goes away")
    }

    func testItBlinksOnItsOwnAndTheGlowStaysOnTheGround() throws {
        let (document, root) = try document()
        let eye = try XCTUnwrap(role("eye.L", in: document.scene, under: root))
        let blinks = stride(from: 0.0, through: 12, by: 1.0 / 30).filter { t in
            let scene = Animator.evaluate(document, at: t).scene
            guard case let .drawing(recipe) = scene.objects[eye]?.kind, let outline = recipe.strokes.first?.points else { return false }
            return (outline.map(\.y).max() ?? 0) - (outline.map(\.y).min() ?? 0) < BlobCharacter.eye.ry * 0.6
        }
        XCTAssertGreaterThan(blinks.count, 3, "several blinks in 12 s")
        XCTAssertLessThan(blinks.count, 60, "…but eyes mostly open")
        let glow = try XCTUnwrap(role("hover", in: document.scene, under: root))
        let heights = stride(from: 0.0, through: 3, by: 0.25).map { Animator.evaluate(document, at: $0).scene.worldTransform(of: glow).position.y }
        XCTAssertLessThan((heights.max() ?? 0) - (heights.min() ?? 0), 0.002, "the glow doesn't bob with him")
    }

    func testArmsFollowTheHands() throws {
        var (document, root) = try document()
        let scene = document.scene
        let hand = try XCTUnwrap(role("hand.R", in: scene, under: root))
        let arm = try XCTUnwrap(scene.subtree(of: root).first { scene.objects[$0]?.name == "Arm R" })
        // At rest the arm isn't rebuilt (it was built already bent).
        XCTAssertFalse(Animator.evaluate(document, at: 0).animated.contains(arm))
        // Wave: key the hand up high; the arm reaches it.
        let raised = Vec3(0.55, 1.3, 0.15)
        var timeline = document.scene.timeline
        timeline.tracks.append(Track(id: "wave", target: hand, property: .position, keyframes: [Keyframe(time: 0, value: .vec3(raised))]))
        _ = try EditCommand.setTimeline(timeline).apply(to: &document)
        let waving = Animator.evaluate(document, at: 0)
        XCTAssertTrue(waving.animated.contains(arm))
        guard case let .drawing(recipe) = waving.scene.objects[arm]?.kind, let tip = recipe.strokes.first?.points.last else {
            return XCTFail("the arm is a tube")
        }
        let tipWorld = waving.scene.worldTransform(of: arm).apply(to: tip)
        XCTAssertTrue(tipWorld.isApproximately(waving.scene.worldTransform(of: hand).position, tolerance: 1e-6), "the arm ends at the hand")
    }

    func testLikenessesAreRecognisedByName() throws {
        XCTAssertEqual(Likeness.recipe(for: "Isaac Newton")?.prop, .apple)
        XCTAssertEqual(Likeness.recipe(for: "sir isaac newton")?.hair, .curlyWig)
        XCTAssertEqual(Likeness.recipe(for: "EINSTEIN")?.accessories, [.bigMustache])
        XCTAssertEqual(Likeness.recipe(for: "Alan Turing")?.hair, .parted)
        XCTAssertEqual(Likeness.recipe(for: "me"), .hesham)
        XCTAssertNil(Likeness.recipe(for: "Somebody Unknown"))
    }

    func testEveryLikenessAndHatBuildsAValidScene() throws {
        var recipes = Array(Likeness.people.values)
        for hat in BlobRecipe.Hat.allCases {
            recipes.append(BlobRecipe(name: "Hat \(hat.rawValue)", hat: hat, hatLabel: hat == .topHat ? "NEWTON" : ""))
        }
        for hair in BlobRecipe.Hair.allCases {
            recipes.append(BlobRecipe(name: "Hair \(hair.rawValue)", hair: hair))
        }
        recipes.append(BlobRecipe(name: "Everything", accessories: BlobRecipe.Accessory.allCases))
        for prop in BlobRecipe.Prop.allCases {
            recipes.append(BlobRecipe(name: "Prop \(prop.rawValue)", prop: prop))
        }
        for recipe in recipes {
            let (document, root) = try document(recipe)
            XCTAssertTrue(document.scene.validate().isEmpty, "\(recipe.name): \(document.scene.validate())")
            XCTAssertEqual(document.scene.objects[root]?.name, recipe.name)
            // Every part meshes (nothing degenerate).
            for id in document.scene.subtree(of: root) {
                if case let .drawing(drawing) = document.scene.objects[id]?.kind {
                    XCTAssertFalse(DrawingMesher.mesh(for: drawing).positions.isEmpty, "\(recipe.name) · \(document.scene.objects[id]?.name ?? "?")")
                }
            }
        }
    }

    func testTheFaceSitsOnTheHead() {
        // Parts are painted onto the onion: every face point is within a centimetre of its surface.
        for (x, y) in [(0.0, BlobCharacter.mouthY), (0.22, 0.59), (-0.3, 0.4)] {
            let point = BlobCharacter.onHead(x, y, lift: 0)
            let radius = BlobCharacter.headRadius(at: y)
            let onEllipse = (point.x * point.x) / (radius * radius) + (point.z * point.z) / pow(radius * BlobCharacter.headDepth, 2)
            XCTAssertEqual(onEllipse, 1, accuracy: 0.02)
        }
    }
}
