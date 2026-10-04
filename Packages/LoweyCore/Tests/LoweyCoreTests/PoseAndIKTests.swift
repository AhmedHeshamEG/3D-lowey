import Foundation
@testable import LoweyCore
import XCTest

final class PoseAndIKTests: XCTestCase {
    private func scene(with fragment: SceneFragment) -> Scene {
        var scene = Scene(id: "s", name: "S")
        for object in fragment.objects {
            scene.objects[object.id] = object
        }
        scene.roots = fragment.roots
        return scene
    }

    private func puppet() -> (Scene, ObjectID) {
        var ids = IDFactory.sequential("p")
        let fragment = CharacterBuilder.build(CharacterRecipe(), ids: &ids)
        return (scene(with: fragment), fragment.roots[0])
    }

    private func applied(_ changes: [PropertyChange], to scene: Scene) -> Scene {
        var result = scene
        for change in changes {
            result.objects[change.object]?.properties[change.key] = change.value
        }
        return result
    }

    func testTwoBoneIKReachesTheTarget() throws {
        let (scene, root) = puppet()
        let handles = IKHandles.handles(of: root, in: scene)
        XCTAssertEqual(handles.map(\.name), ["Left hand", "Right hand", "Left foot", "Right foot"])
        let hand = try XCTUnwrap(handles.first)
        guard case let .limb(upper, _, end) = hand.kind else { return XCTFail("a limb") }
        let shoulder = scene.worldTransform(of: upper).position
        let start = scene.worldTransform(of: end).position
        // Somewhere reachable: a bit up and forward of where the hand is.
        let target = start + Vec3(0, 0.15, 0.12)
        XCTAssertLessThan(target.distance(to: shoulder), shoulder.distance(to: start) * 1.0001 + 0.2)
        let posed = applied(IKHandles.solve(hand, to: target, in: scene, rest: scene), to: scene)
        XCTAssertEqual(posed.worldTransform(of: end).position.distance(to: target), 0, accuracy: 0.01)
        XCTAssertEqual(posed.worldTransform(of: upper).position, shoulder, "the shoulder stays put")
        // Out of reach: the arm points straight at it.
        let far = shoulder + (target - shoulder).normalized * 5
        let stretched = applied(IKHandles.solve(hand, to: far, in: scene, rest: scene), to: scene)
        let direction = (stretched.worldTransform(of: end).position - shoulder).normalized
        XCTAssertGreaterThan(direction.dot((far - shoulder).normalized), 0.99)
    }

    func testBlobHandsUseTheReachDials() throws {
        var ids = IDFactory.sequential("b")
        let build = BlobCharacter.build(BlobRecipe(), ids: &ids)
        let scene = scene(with: build.fragment)
        let root = build.fragment.roots[0]
        let handles = IKHandles.handles(of: root, in: scene)
        XCTAssertEqual(handles.count, 2)
        let right = try XCTUnwrap(handles.first { $0.kind == .blobHand(left: false) })
        let rest = scene.worldTransform(of: right.end).position
        let scale = scene.worldTransform(of: root).scale.y
        let changes = IKHandles.solve(right, to: rest + Vec3(0, BlobRig.handReach.y * 0.5 * scale, 0), in: scene, rest: scene)
        XCTAssertEqual(changes.first { $0.key == .handRightY }?.value?.floatValue ?? 0, 0.5, accuracy: 1e-6)
        XCTAssertEqual(changes.first { $0.key == .handRightX }?.value?.floatValue ?? 1, 0, accuracy: 1e-6)
    }

    func testPosesSaveApplyAndMirror() throws {
        var (scene, root) = puppet()
        let leftArm = try XCTUnwrap(scene.subtree(of: root).first { scene.objects[$0]?[.bone]?.stringValue == "leftUpperArm" })
        let rightArm = try XCTUnwrap(scene.subtree(of: root).first { scene.objects[$0]?[.bone]?.stringValue == "rightUpperArm" })
        scene.objects[leftArm]?.transform.rotation = Quat(eulerDegrees: Vec3(0, 20, 60))
        scene.objects[root]?[.smile] = .float(0.8)
        scene.objects[root]?[.headYaw] = .float(15)
        let pose = PoseLibrary.capture(root, in: scene, id: "wave", name: "Wave")
        XCTAssertEqual(pose.dials[.smile], .float(0.8))
        XCTAssertNotNil(pose.hips)
        // Stored on the character, as JSON.
        let stored = applied([PoseLibrary.storing([pose], on: root)], to: scene)
        XCTAssertEqual(try PoseLibrary.poses(of: XCTUnwrap(stored.objects[root])), [pose])
        // Mirrored: the right arm takes the left arm's turn, seen in a mirror; the head turns the other way.
        let mirror = PoseLibrary.mirrored(pose)
        XCTAssertEqual(mirror.dials[.headYaw], .float(-15))
        let changes = PoseLibrary.applying(mirror, to: root, in: scene)
        let posed = applied(changes, to: scene)
        let euler = try XCTUnwrap(posed.objects[rightArm]?.transform.rotation.eulerDegrees)
        XCTAssertEqual(euler.y, -20, accuracy: 0.01)
        XCTAssertEqual(euler.z, -60, accuracy: 0.01)
        XCTAssertEqual(PoseLibrary.mirroredBone("leftFoot"), "rightFoot")
        XCTAssertEqual(PoseLibrary.character(of: rightArm, in: scene), root)
    }
}
