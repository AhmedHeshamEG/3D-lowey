import Foundation
@testable import LoweyCore
import XCTest

final class CharacterOutlineTests: XCTestCase {
    func testOutlineFollowsTheLook() throws {
        XCTAssertEqual(try XCTUnwrap(CharacterOutline.width(look: .ink, scale: 1)), CharacterOutline.baseWidth, accuracy: 1e-12)
        XCTAssertGreaterThan(try XCTUnwrap(CharacterOutline.width(look: .comic, scale: 1)), CharacterOutline.baseWidth, "Comic's lines are heavier")
        XCTAssertNil(CharacterOutline.width(look: .clay, scale: 1), "Clay draws no lines")
        XCTAssertEqual(try XCTUnwrap(CharacterOutline.width(look: .ink, scale: 2)), CharacterOutline.baseWidth * 2, accuracy: 1e-12)
        XCTAssertNil(CharacterOutline.width(look: .ink, scale: 1, lineWeight: 0))
        XCTAssertTrue(CharacterOutline.isDecal(role: "eye.L"))
        XCTAssertTrue(CharacterOutline.isDecal(role: "mouth.smile"))
        XCTAssertFalse(CharacterOutline.isDecal(role: "head"))
        XCTAssertFalse(CharacterOutline.isDecal(role: "hand.L"))
    }

    func testCharactersAreBlobsPuppetsAndClipPlayers() {
        var document = makeDocument()
        XCTAssertFalse(CharacterOutline.isCharacter("a", in: document.scene))
        document.scene["a"]?[.rigStandard] = .enumeration("blob")
        XCTAssertTrue(CharacterOutline.isCharacter("a", in: document.scene))
        document.scene.timeline.clipTracks = [ClipTrack(id: "t", target: "c", segments: [])]
        XCTAssertTrue(CharacterOutline.isCharacter("c", in: document.scene))
    }

    func testShadowPresetsFitTheBounds() throws {
        let bounds = Bounds(min: Vec3(-1, 0, -1), max: Vec3(1, 2, 1))
        for preset in ShadowPreset.allCases {
            let dabs = preset.dabs(in: bounds)
            XCTAssertFalse(dabs.isEmpty, preset.title)
            for dab in dabs {
                XCTAssertLessThanOrEqual(abs(dab.position.x), 1.0001, preset.title)
                XCTAssertTrue((0 ... 2).contains(dab.position.y), preset.title)
            }
        }
        let side = ShadowPreset.sideLight.dabs(in: bounds)
        XCTAssertLessThan(try XCTUnwrap(side.first).amount, 0, "the far side goes into shadow")
        XCTAssertLessThan(try XCTUnwrap(side.first).position.x, 0)
    }
}

final class BlobClipTests: XCTestCase {
    private func blobDocument(clip: String) -> (Document, ObjectID) {
        var ids = IDFactory.sequential("blob")
        let build = BlobCharacter.build(BlobRecipe(), ids: &ids)
        var scene = Scene(id: "s", name: "S")
        for object in build.fragment.objects {
            scene.objects[object.id] = object
        }
        scene.roots = build.fragment.roots
        let root = build.fragment.roots[0]
        scene.timeline.clipTracks = [ClipTrack(id: "t", target: root, segments: [
            ClipSegment(id: "s", clip: ClipRef(asset: BuiltinClips.assetID, name: clip), start: 0, duration: 4, blend: 0)
        ])]
        let info = ProjectInfo(id: "p", name: "P", sceneOrder: ["s"])
        return (Document(project: info, scene: scene), root)
    }

    func testEveryBuiltInClipMovesABlob() {
        for name in BuiltinClips.names {
            let length = BlobClips.duration(name)
            let samples = stride(from: 0.0, to: length, by: length / 8).map { BlobClips.pose(name, at: $0, duration: length) }
            let moving = samples.contains { $0 != samples[0] } || samples[0] != BlobClips.Pose()
            XCTAssertTrue(moving, "\(name) does something")
        }
    }

    func testWaveRaisesTheHandThroughTheRig() throws {
        let (document, root) = blobDocument(clip: "Wave")
        let still = Animator.evaluate(Document(project: document.project, scene: {
            var scene = document.scene
            scene.timeline.clipTracks = []
            return scene
        }()), at: 0.5).scene
        let waving = Animator.evaluate(document, at: 0.5).scene
        let hand = try XCTUnwrap(document.scene.subtree(of: root).first { document.scene.objects[$0]?[.faceRole]?.stringValue == "hand.R" })
        XCTAssertGreaterThan(waving.worldTransform(of: hand).position.y, still.worldTransform(of: hand).position.y + 0.2)
    }

    func testWalkLeansAndBobs() throws {
        let (document, root) = blobDocument(clip: "Walk")
        let quarter = Animator.evaluate(document, at: 0.25).scene
        XCTAssertGreaterThan(try XCTUnwrap(quarter.objects[root]).transform.position.y, document.scene.objects[root]?.transform.position.y ?? 0)
    }
}
