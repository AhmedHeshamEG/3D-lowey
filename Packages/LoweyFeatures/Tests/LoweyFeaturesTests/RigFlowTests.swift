import Foundation
import LoweyCore
@testable import LoweyFeatures
import XCTest

/// Cast ▸ Rig in the editor: a drawn bone rigs an object in one undo step (its weights written to the project first),
/// joints turned in Keyframe mode are keyed like any property, and removing the rig takes its pose and keys with it.
@MainActor
final class RigFlowTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Rig \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        return try XCTUnwrap(app.editor)
    }

    /// Waits for the background weighing to land.
    private func waitForRig(on id: ObjectID, in editor: EditorModel, file: StaticString = #filePath, line: UInt = #line) async throws -> ObjectRig {
        for _ in 0 ..< 200 where editor.baseScene.objects[id]?.rig == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        return try XCTUnwrap(editor.baseScene.objects[id]?.rig, "the rig arrived", file: file, line: line)
    }

    /// A stroke straight down through the cube's top, left to right.
    private func stroke(across id: ObjectID, in editor: EditorModel) -> [Ray] {
        let centre = editor.baseScene.worldTransform(of: id).position
        return stride(from: -0.45, through: 0.45, by: 0.05).map { Ray(origin: centre + Vec3($0, 3, 0), direction: Vec3(0, -1, 0)) }
    }

    func testADrawnBoneRigsACubeInOneStep() async throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection)
        XCTAssertNil(editor.rigBlocker(cube))
        editor.startRigging(cube.id)
        XCTAssertEqual(editor.tool, .rig)
        editor.drawBone(rays: stroke(across: cube.id, in: editor))
        let rig = try await waitForRig(on: cube.id, in: editor)
        XCTAssertGreaterThanOrEqual(rig.skeleton.joints.count, 3)
        let file = try XCTUnwrap(rig.skin)
        XCTAssertNotNil(editor.paintFiles(file), "the weights are in the project")
        XCTAssertTrue(try editor.rigFits(XCTUnwrap(editor.baseScene.objects[cube.id])))
        XCTAssertEqual(editor.castType(of: cube.id), .drawn, "a rigged object joins the cast")
        editor.undo()
        XCTAssertNil(editor.baseScene.objects[cube.id]?.rig, "one undo step")
    }

    func testRiggingGoesBonesThenSkinThenPose() async throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        var cube = try XCTUnwrap(editor.singleSelection)
        XCTAssertEqual(editor.rigStep(for: cube), .bones)
        XCTAssertTrue(editor.rigStepIsOpen(.bones, for: cube))
        XCTAssertFalse(editor.rigStepIsOpen(.skin, for: cube), "no bones yet")
        XCTAssertFalse(editor.rigStepIsOpen(.pose, for: cube))
        editor.setRigStep(.pose, on: cube.id)
        XCTAssertEqual(editor.rigStep(for: cube), .bones, "a step that isn't open can't be entered")

        editor.startRigging(cube.id)
        editor.drawBone(rays: stroke(across: cube.id, in: editor))
        _ = try await waitForRig(on: cube.id, in: editor)
        cube = try XCTUnwrap(editor.baseScene.objects[cube.id])
        XCTAssertTrue(editor.rigStepIsOpen(.skin, for: cube), "the next step lights up")
        XCTAssertTrue(editor.rigStepIsOpen(.pose, for: cube))
        XCTAssertEqual(editor.rigStep(for: cube), .bones, "it stays on Bones until you move on")

        editor.setRigStep(.skin, on: cube.id)
        XCTAssertEqual(editor.rigging.mode, .weights)
        XCTAssertEqual(editor.tool, .rig)
        XCTAssertNotNil(editor.rigging.joint, "a bone is chosen to paint")

        editor.setRigStep(.pose, on: cube.id)
        XCTAssertEqual(editor.tool, .select, "joints are dragged with the Select tool")
        XCTAssertEqual(editor.selection, [cube.id])
        XCTAssertEqual(editor.rigStep(for: cube), .pose)

        editor.setRigStep(.bones, on: cube.id)
        XCTAssertEqual(editor.rigging.mode, .bone)
    }

    func testDrawingABoneAgainReplacesItAndForgetsItsPose() async throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection)
        editor.startRigging(cube.id)
        editor.drawBone(rays: stroke(across: cube.id, in: editor))
        let first = try await waitForRig(on: cube.id, in: editor)
        let turned = try XCTUnwrap(first.skeleton.names.last)
        editor.setProperty(.boneTurn(turned), .quat(Quat(angle: 0.4, axis: .unitZ)))
        XCTAssertNotNil(editor.baseScene.objects[cube.id]?[.boneTurn(turned)])

        // The same stroke a little to one side: the chain is replaced, not doubled.
        let again = stroke(across: cube.id, in: editor).map { Ray(origin: $0.origin + Vec3(0, 0, 0.04), direction: $0.direction) }
        editor.drawBone(rays: again)
        // Bone heat on CI's simulator takes several seconds each time.
        for _ in 0 ..< 900 where editor.baseScene.objects[cube.id]?.rig == first {
            try await Task.sleep(for: .milliseconds(50))
        }
        let second = try XCTUnwrap(editor.baseScene.objects[cube.id]?.rig)
        XCTAssertEqual(second.skeleton.joints.count, first.skeleton.joints.count, "one chain, as before")
        XCTAssertNotEqual(second.restPositions, first.restPositions, "where it was drawn this time")
        XCTAssertNil(editor.baseScene.objects[cube.id]?[.boneTurn(turned)], "the old joint's turn went with it")
        XCTAssertTrue(editor.rigging.preview.isEmpty)
        editor.undo()
        XCTAssertEqual(editor.baseScene.objects[cube.id]?.rig, first, "one undo step")
        XCTAssertNotNil(editor.baseScene.objects[cube.id]?[.boneTurn(turned)])
    }

    func testJointsTurnedInKeyframeModeAreKeyedAndGoWithTheRig() async throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection)
        editor.startRigging(cube.id)
        editor.drawBone(rays: stroke(across: cube.id, in: editor))
        let rig = try await waitForRig(on: cube.id, in: editor)
        editor.tool = .select
        let character = try XCTUnwrap(CharacterRig.of(cube.id, in: editor.baseScene))
        editor.timelineMode = .keyframe
        editor.setTime(1)
        _ = editor.perform(.setProperties(character.changes(turning: [rig.skeleton.joints.count - 2: Quat(angle: 0.5, axis: .unitZ)])))
        let key = PropertyKey.boneTurn(rig.skeleton.joints[rig.skeleton.joints.count - 2].name)
        XCTAssertNotNil(editor.timeline.track(for: cube.id, key), "a bone turn is keyed at the playhead")
        let handles = IKHandles.handles(of: cube.id, in: editor.displayed.scene)
        XCTAssertFalse(handles.isEmpty, "its joints are handles")
        editor.removeRig(cube.id)
        XCTAssertNil(editor.baseScene.objects[cube.id]?.rig)
        XCTAssertNil(editor.timeline.track(for: cube.id, key), "its keys go with it")
        XCTAssertFalse(editor.baseScene.objects[cube.id]?.properties.keys.contains { $0.boneJoint != nil } ?? true)
    }

    func testRiggingIsRefusedWhereItCantWork() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.plane)
        let plane = try XCTUnwrap(editor.singleSelection)
        XCTAssertNotNil(editor.rigBlocker(plane))
        editor.startRigging(plane.id)
        XCTAssertNotEqual(editor.tool, .rig)
    }
}
