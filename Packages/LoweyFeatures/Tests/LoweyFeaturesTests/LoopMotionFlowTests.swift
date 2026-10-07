import LoweyCore
@testable import LoweyFeatures
import XCTest

/// The Motion row: one tap starts a looping motion on the selection and plays, a second tap stops it, the slider
/// retimes what's running, Make keyframes turns it into keys.
@MainActor
final class LoopMotionFlowTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Loop \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        return try XCTUnwrap(app.editor)
    }

    func testOneTapStartsAndASecondStops() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection?.id)
        XCTAssertTrue(editor.loopMotions.isEmpty)

        editor.toggleLoopMotion(.bounce)
        XCTAssertTrue(editor.hasLoopMotion(.bounce))
        XCTAssertTrue(editor.isPlaying, "it moves straight away, no timeline needed")
        XCTAssertEqual(editor.behaviors(of: cube).map(\.kind), [.bounce(height: 0.4, period: 1)])
        editor.pause()

        editor.toggleLoopMotion(.spin)
        XCTAssertEqual(Set(editor.loopMotions.map(\.motion)), [.bounce, .spin], "motions add up")

        editor.toggleLoopMotion(.bounce)
        XCTAssertFalse(editor.hasLoopMotion(.bounce))
        XCTAssertTrue(editor.hasLoopMotion(.spin))
        editor.undo()
        XCTAssertTrue(editor.hasLoopMotion(.bounce), "stopping is one undo step")
    }

    func testTheSpeedSliderRetimesWhatIsRunning() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection?.id)
        editor.toggleLoopMotion(.spin)
        editor.toggleLoopMotion(.swing)
        editor.pause()
        editor.setLoopMotionSpeed(1.5)
        editor.setLoopMotionSpeed(2)
        editor.endGesture()
        XCTAssertEqual(editor.loopMotionSpeed, 2, accuracy: 1e-9)
        XCTAssertEqual(Set(editor.behaviors(of: cube).map(\.kind)), [.spin(degreesPerSecond: 180, axis: .y), .swing(angle: 25, period: 1)])
        editor.undo()
        XCTAssertEqual(editor.loopMotionSpeed, 1, accuracy: 1e-9, "one drag is one undo step")

        editor.setSelection([])
        editor.addPrimitive(.sphere)
        editor.setLoopMotionSpeed(3)
        editor.toggleLoopMotion(.float)
        editor.pause()
        XCTAssertEqual(editor.loopMotionSpeed, 3, accuracy: 1e-9, "a new motion starts at the slider's speed")
    }

    func testFollowAPathNeedsALine() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        editor.toggleLoopMotion(.followPath)
        XCTAssertFalse(editor.hasLoopMotion(.followPath), "nothing to follow yet")
        XCTAssertFalse(editor.isPlaying)
    }

    func testMakeKeyframes() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection?.id)
        editor.toggleLoopMotion(.bounce)
        editor.toggleLoopMotion(.spin)
        editor.pause()
        editor.makeLoopMotionKeyframes()
        XCTAssertTrue(editor.loopMotions.isEmpty)
        XCTAssertTrue(editor.behaviors(of: cube).isEmpty)
        XCTAssertNotNil(editor.timeline.track(for: cube, .position))
        XCTAssertNotNil(editor.timeline.track(for: cube, .rotation))
        editor.undo()
        XCTAssertEqual(editor.loopMotions.count, 2, "one undo step brings both motions back")
    }
}
