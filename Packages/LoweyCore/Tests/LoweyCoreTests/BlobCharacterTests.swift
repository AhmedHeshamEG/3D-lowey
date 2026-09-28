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
        for part in ["head", "eye.L", "eye.R", "pupil.L", "pupil.R", "brow.L", "brow.R", "mouth", "hand.L", "hand.R", "hover"] {
            XCTAssertNotNil(role(part, in: scene, under: root), "has \(part)")
        }
        let shapes = scene.subtree(of: root).compactMap { scene.objects[$0]?[.faceRole]?.stringValue }.filter { $0.hasPrefix("mouth.") }
        XCTAssertEqual(Set(shapes), Set(Viseme.allCases.map { "mouth.\($0.rawValue)" } + ["mouth.smile", "mouth.grin", "mouth.frown"]),
                       "every lip-sync shape plus the expressions")
        let visible = scene.subtree(of: root).filter {
            scene.objects[$0]?[.faceRole]?.stringValue?.hasPrefix("mouth.") == true && scene.objects[$0]?[.visible]?.boolValue == true
        }
        XCTAssertEqual(visible.count, 1, "only the rest mouth (his smirk) shows")
        XCTAssertTrue(scene.subtree(of: root).contains { scene.objects[$0]?.name == "Beret" }, "his beret")
        XCTAssertTrue(scene.subtree(of: root).contains { scene.objects[$0]?.name == "Mark" }, "with the Pisces mark")
        XCTAssertEqual(document.scene.timeline.behaviors.count, 1, "he floats")
        // The recipe travels with him (rebuildable), and survives JSON.
        let json = try XCTUnwrap(scene.objects[root]?[.blobRecipe]?.stringValue)
        XCTAssertEqual(try LoweyJSON.decode(BlobRecipe.self, from: Data(json.utf8)), .hesham)
        XCTAssertEqual(try LoweyJSON.decode(BlobRecipe.self, from: Data(#"{"hat":"topHat"}"#.utf8)).hat, .topHat, "partial recipes fill in")
    }

    func testTheFaceRigBlinksLooksAndTalks() throws {
        var (document, root) = try document()
        document.scene.objects[root]?[.blinkLeft] = .float(1)
        document.scene.objects[root]?[.lookX] = .float(1)
        document.scene.objects[root]?[.brows] = .float(1)
        document.scene.objects[root]?[.mouth] = .enumeration("C")
        let base = document.scene
        let animated = Animator.evaluate(document, at: 0).scene
        let eye = try XCTUnwrap(role("eye.L", in: base, under: root))
        XCTAssertLessThan(animated.objects[eye]!.transform.scale.y, 0.1, "the eye closes")
        let pupil = try XCTUnwrap(role("pupil.L", in: base, under: root))
        let moved = animated.objects[pupil]!.transform.position.x - base.objects[pupil]!.transform.position.x
        XCTAssertEqual(moved, 0.35 * 0.23, accuracy: 1e-9, "the shines slide a few centimetres, not 35")
        let brow = try XCTUnwrap(role("brow.L", in: base, under: root))
        XCTAssertEqual(animated.objects[brow]!.transform.position.y - base.objects[brow]!.transform.position.y, 0.6 * 0.05, accuracy: 1e-9)
        let talking = try XCTUnwrap(role("mouth.C", in: base, under: root))
        let resting = try XCTUnwrap(role("mouth.X", in: base, under: root))
        XCTAssertEqual(animated.objects[talking]?[.visible]?.boolValue, true)
        XCTAssertEqual(animated.objects[resting]?[.visible]?.boolValue, false)
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
