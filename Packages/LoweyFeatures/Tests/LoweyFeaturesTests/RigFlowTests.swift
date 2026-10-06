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
