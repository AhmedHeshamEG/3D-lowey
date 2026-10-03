import LoweyCore
@testable import LoweyFeatures
import XCTest

@MainActor
final class FlipbookFlowTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Flip \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.comic.id)
        return try XCTUnwrap(app.editor)
    }

    func testDrawnEffectsFollowTheSelectionAndStepThroughDrawings() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection?.id)
        editor.setTime(1)
        editor.addFlipbookEffect(.impactBurst)
        let track = try XCTUnwrap(editor.activeFlipbook)
        XCTAssertEqual(track.anchor, .object(cube), "on the selected object")
        XCTAssertEqual(track.start, 1, accuracy: 1e-9)
        XCTAssertEqual(track.frames.count, FlipbookFX.impactBurst.defaultFrames)
        XCTAssertEqual(editor.activeFlipbookFrame, 0)
        // Holds and drawings.
        editor.changeFlipbookHold(by: 2)
        editor.endGesture()
        XCTAssertEqual(editor.activeFlipbook?.frames[0].hold, 4)
        editor.addFlipbookDrawing()
        XCTAssertEqual(editor.activeFlipbook?.frames.count, FlipbookFX.impactBurst.defaultFrames + 1)
        XCTAssertEqual(editor.activeFlipbookFrame, 1, "the playhead moves to the new drawing")
        editor.deleteFlipbookDrawing()
        XCTAssertEqual(editor.activeFlipbook?.frames.count, FlipbookFX.impactBurst.defaultFrames)
        editor.undo()
        XCTAssertEqual(editor.activeFlipbook?.frames.count, FlipbookFX.impactBurst.defaultFrames + 1)
    }

    func testTrackSettingsAndDeletion() throws {
        let editor = try makeEditor()
        editor.select(nil)
        editor.addFlipbookEffect(.sparkle)
        let track = try XCTUnwrap(editor.activeFlipbook)
        XCTAssertEqual(track.anchor, .camera, "nothing selected: on the camera")
        XCTAssertTrue(track.loops, "sparkles keep going")
        editor.updateFlipbook("Blend") { $0.blend = .screen }
        XCTAssertEqual(editor.activeFlipbook?.blend, .screen)
        editor.deleteFlipbook()
        XCTAssertTrue(editor.timeline.flipbooks.isEmpty)
        XCTAssertNil(editor.activeFlipbook)
        editor.undo()
        XCTAssertEqual(editor.timeline.flipbooks.count, 1)
    }
}
