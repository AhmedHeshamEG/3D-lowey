import Foundation
import LoweyCore
@testable import LoweyFeatures
import XCTest

/// Live performance in the editor: every recording is a take and the comp is chosen from them; triggers are performed
/// while a take records and are edits otherwise; loose bones, breathing and parts are ordinary undoable edits.
@MainActor
final class LiveFlowTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Live \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        return try XCTUnwrap(app.editor)
    }

    /// A cube with a tail of three joints along +x, rigged without waiting for weights (the flows here don't bend it).
    private func tailed(_ editor: EditorModel) throws -> ObjectID {
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection)
        let rig = ObjectRig(names: ["root", "t1", "t2", "t3"], parents: [nil, 0, 1, 2],
                            positions: [Vec3(0, 0, 0), Vec3(0.5, 0, 0), Vec3(1, 0, 0), Vec3(1.5, 0, 0)])
        XCTAssertTrue(editor.perform(.setRig(cube.id, rig)))
        return cube.id
    }

    /// Records one take of a smile held at `level` from `start` for `seconds`, as a performance would.
    private func record(_ level: Double, from start: Double, seconds: Double, on id: ObjectID, in editor: EditorModel) {
        editor.takes = [:]
        editor.performPhase = .recording
        var moment = start
        while moment <= start + seconds + 1e-9 {
            editor.time = moment
            editor.performLive(.float(level), .smile, on: id)
            moment += 1.0 / 30
        }
        editor.finishPerform()
    }

    func testEveryRecordingIsATakeAndTheCompIsChosenFromThem() throws {
        let editor = try makeEditor()
        let id = try tailed(editor)
        record(1, from: 1, seconds: 2, on: id, in: editor)
        XCTAssertEqual(editor.recordedTakes.map(\.name), ["Take 1"])
        XCTAssertEqual(editor.share(of: editor.recordedTakes[0]), 1, accuracy: 1e-6)
        record(0.25, from: 1, seconds: 2, on: id, in: editor)
        XCTAssertEqual(editor.recordedTakes.count, 2, "the first take is kept")
        XCTAssertEqual(editor.live.selectedTake, editor.recordedTakes[1].id)
        XCTAssertEqual(editor.share(of: editor.recordedTakes[0]), 0, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(editor.timeline.track(for: id, .smile)?.value(at: 2)?.floatValue), 0.25, accuracy: 1e-6)
        // Drag across the first take from 1.5 s to 2.5 s: that stretch plays it again.
        editor.useTake(editor.recordedTakes[0].id, over: TimeRange(start: 1.5, end: 2.5))
        let track = try XCTUnwrap(editor.timeline.track(for: id, .smile))
        XCTAssertEqual(try XCTUnwrap(track.value(at: 2)?.floatValue), 1, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(track.value(at: 1.2)?.floatValue), 0.25, accuracy: 1e-6)
        XCTAssertEqual(editor.share(of: editor.recordedTakes[0]), 0.5, accuracy: 0.02)
        editor.undo()
        XCTAssertEqual(try XCTUnwrap(editor.timeline.track(for: id, .smile)?.value(at: 2)?.floatValue), 0.25, accuracy: 1e-6, "one undo step")
        editor.renameTake(editor.recordedTakes[0].id, to: "The good one")
        XCTAssertEqual(editor.recordedTakes[0].name, "The good one")
        editor.deleteTake(editor.recordedTakes[0].id)
        XCTAssertEqual(editor.recordedTakes.count, 1)
        XCTAssertEqual(try XCTUnwrap(editor.timeline.track(for: id, .smile)?.value(at: 2)?.floatValue), 0.25, accuracy: 1e-6, "what plays stays")
    }

    func testATriggerIsPerformedWhileATakeRecordsAndIsAnEditOtherwise() throws {
        let editor = try makeEditor()
        let id = try tailed(editor)
        editor.select(id)
        editor.addTrigger(.happy, to: id)
        let trigger = try XCTUnwrap(editor.triggers(of: id).first)
        XCTAssertEqual(trigger.key, "1")
        XCTAssertTrue(trigger.holds)
        XCTAssertTrue(editor.hasTrigger(key: "1"))
        // Pressed at 1 s and let go at 2 s of a recording: held keys at those moments.
        editor.takes = [:]
        editor.performPhase = .recording
        editor.time = 1
        editor.pressTrigger(trigger, on: id)
        XCTAssertTrue(editor.live.held.contains(trigger.id))
        XCTAssertEqual(editor.displayed.scene.objects[id]?[.smile], .float(0.8), "shown at once")
        editor.time = 2
        editor.releaseTrigger(trigger)
        XCTAssertTrue(editor.live.held.isEmpty)
        editor.finishPerform()
        let smile = try XCTUnwrap(editor.timeline.track(for: id, .smile))
        XCTAssertEqual(smile.value(at: 1.5), .float(0.8))
        XCTAssertEqual(smile.value(at: 2.5), .float(0))
        XCTAssertTrue(smile.keyframes.allSatisfy { $0.easing == .step })
        XCTAssertEqual(editor.recordedTakes.count, 1)
        // Not recording, in Compose: the trigger just sets the face, one undo step.
        editor.undo()
        editor.timelineMode = .compose
        editor.pressTrigger(trigger, on: id)
        XCTAssertEqual(editor.baseScene.objects[id]?[.smile], .float(0.8))
        XCTAssertNil(editor.timeline.track(for: id, .smile))
        editor.undo()
        XCTAssertNil(editor.baseScene.objects[id]?[.smile])
        editor.setTriggerKey("5", for: trigger.id, of: id)
        XCTAssertEqual(editor.triggers(of: id).first?.key, "5")
        editor.removeTrigger(trigger.id, of: id)
        XCTAssertTrue(editor.triggers(of: id).isEmpty)
    }

    func testAJointHangsLooseWithEverythingBelowItAndBreathingIsOneSlider() throws {
        let editor = try makeEditor()
        let id = try tailed(editor)
        editor.setDangle(0.7, joint: "t2", on: id)
        editor.endGesture()
        XCTAssertEqual(editor.dangle(of: "t2", on: id), 0.7, accuracy: 1e-9)
        XCTAssertEqual(editor.dangle(of: "t3", on: id), 0.7, accuracy: 1e-9)
        XCTAssertEqual(editor.dangle(of: "t1", on: id), 0, accuracy: 1e-9)
        editor.setDangle(0, joint: "t2", on: id)
        editor.endGesture()
        XCTAssertNil(editor.baseScene.objects[id]?[.dangle("t3")], "off leaves nothing behind")
        editor.setBreathing(0.5, on: id)
        editor.endGesture()
        XCTAssertEqual(editor.breathing(of: id), 0.5, accuracy: 1e-9)
        XCTAssertFalse(editor.blinksOnItsOwn(id))
        XCTAssertEqual(editor.headChoices(of: id), ["root", "t1", "t2", "t3"])
        editor.setHead("t3", on: id)
        XCTAssertEqual(editor.baseScene.objects[id]?[.liveHead], .string("t3"))
    }

    func testALooseObjectBecomesAPartThatRidesTheNearestBone() throws {
        let editor = try makeEditor()
        let id = try tailed(editor)
        let body = editor.baseScene.worldTransform(of: id).position
        editor.addPrimitive(.sphere)
        let ball = try XCTUnwrap(editor.singleSelection)
        editor.perform(.setProperties([PropertyChange(object: ball.id, key: .position, value: .vec3(body + Vec3(1.3, 0.2, 0)))]))
        let loose = try XCTUnwrap(editor.baseScene.objects[ball.id])
        XCTAssertEqual(editor.partHosts(for: loose).map(\.id), [id])
        let before = editor.baseScene.worldTransform(of: ball.id).position
        editor.attachPart(ball.id, to: id)
        let part = try XCTUnwrap(editor.baseScene.objects[ball.id])
        XCTAssertEqual(part.parent, id)
        XCTAssertEqual(part[.attachBone], .string("t2"), "the bone from 1.0 to 1.5 is the nearest")
        XCTAssertTrue(editor.baseScene.worldTransform(of: ball.id).position.isApproximately(before, tolerance: 1e-9), "it stays where it is")
        XCTAssertTrue(editor.partHosts(for: part).isEmpty)
        editor.setPartRole(.eyeLeft, of: ball.id)
        XCTAssertEqual(editor.baseScene.objects[ball.id]?[.faceRole], .string("eye.L"))
        // Its bone turns: the part goes with it.
        editor.perform(.setProperties([PropertyChange(object: id, key: .boneTurn("t2"), value: .quat(Quat(angle: .pi / 2, axis: .unitZ)))]))
        let shown = editor.displayed.scene.worldTransform(of: ball.id).position
        XCTAssertGreaterThan(shown.distance(to: before), 0.2)
        editor.detachPart(ball.id)
        XCTAssertNil(editor.baseScene.objects[ball.id]?.parent)
        XCTAssertNil(editor.baseScene.objects[ball.id]?[.attachBone])
    }
}
