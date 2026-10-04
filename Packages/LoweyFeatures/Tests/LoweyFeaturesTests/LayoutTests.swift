import HmmDesign
import LoweyCore
@testable import LoweyFeatures
import SwiftUI
import XCTest

/// The layout of docs/LAYOUT.md as behaviour: time on call, the per-project workspace, starter templates, the Model
/// panel's pages and where the floating inspector may go.
@MainActor
final class LayoutTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor(_ template: StarterTemplate = .blank) throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Layout \(UUID().uuidString.prefix(6))", template: template, mood: template.mood, look: template.lookPresetID)
        return try XCTUnwrap(app.editor)
    }

    func testTheTimelineIsOnCallAndEachProjectRemembersIt() async throws {
        let editor = try makeEditor()
        XCTAssertEqual(editor.timelinePresence, .hidden, "the stage owns the screen until time is called")
        editor.toggleTimeline()
        XCTAssertEqual(editor.timelinePresence, .transport, "the corner control calls the slim transport")
        editor.toggleAnimate()
        XCTAssertEqual(editor.timelinePresence, .full, "Animate opens the whole timeline")
        editor.setTimelineHeight(5000)
        XCTAssertEqual(editor.timelineHeight, ProjectWorkspace.timelineHeightRange.upperBound)
        editor.setTimelineHeight(333)
        editor.toggleAnimate()
        XCTAssertEqual(editor.timelinePresence, .transport)
        editor.toggleAnimate()
        await editor.saveNow(thumbnail: false)
        editor.tearDown()
        let app = try XCTUnwrap(app)
        app.open(url: editor.projectURL)
        let reopened = try XCTUnwrap(app.editor)
        XCTAssertFalse(reopened === editor)
        XCTAssertEqual(reopened.timelinePresence, .full)
        XCTAssertEqual(reopened.timelineHeight, 333)
        reopened.toggleTimeline()
        XCTAssertEqual(reopened.timelinePresence, .hidden, "the corner control sends the whole timeline away too")
    }

    func testAStarterTemplateGetsTheWorkspaceReady() throws {
        let editor = try makeEditor(.print)
        XCTAssertEqual(editor.openPanel, .model, "Model to print opens on Model")
        XCTAssertTrue(editor.snap.grid)
        XCTAssertEqual(editor.snap.gridSize, 0.01)
        XCTAssertEqual(editor.look.presetID, LookPreset.clay.id)
        XCTAssertTrue(editor.baseScene.objects.isEmpty, "a template places nothing")
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection)
        XCTAssertEqual(cube.transform.scale.x, 0.05, accuracy: 1e-9, "new shapes are small parts")
        XCTAssertNil(editor.store.loadWorkspace(at: editor.projectURL).firstPanel, "the first panel opens once")
    }

    func testCharacterAndAnimationTemplates() throws {
        let character = try makeEditor(.character)
        XCTAssertEqual(character.openPanel, .cast)
        XCTAssertEqual(character.timelinePresence, .transport)
        XCTAssertFalse(character.showsGrid)
        let animation = try makeEditor(.animation)
        XCTAssertEqual(animation.timelinePresence, .full)
        XCTAssertNil(animation.openPanel)
    }

    func testSnappingIsTheProjectsOwn() throws {
        let editor = try makeEditor()
        editor.snap.grid = true
        editor.snap.gridSize = 0.5
        editor.showsGrid = false
        editor.saveWorkspace()
        let workspace = editor.store.loadWorkspace(at: editor.projectURL)
        XCTAssertTrue(workspace.snap.grid)
        XCTAssertEqual(workspace.snap.gridSize, 0.5)
        XCTAssertFalse(workspace.showsGrid)
    }

    func testSwappingOpensModelOnItsLibrary() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        editor.openPanel = nil
        editor.beginSwap()
        XCTAssertEqual(editor.openPanel, .model)
        XCTAssertEqual(editor.modelPage, .library)
        XCTAssertNotEqual(editor.libraryPurpose, .place)
    }

    func testTheMakingToolsSplitIntoDrawAndPaint() {
        XCTAssertEqual(StageTool.allCases.filter(\.draws), [.ink, .draw, .flipbook])
        XCTAssertEqual(StageTool.allCases.filter(\.paintsSurfaces), [.shadowBrush, .scatter])
        XCTAssertTrue(StageTool.allCases.filter { $0.draws || $0.paintsSurfaces }.allSatisfy { $0 != .select && $0 != .lasso })
        XCTAssertFalse(ClusterPanel.model.isLeading)
        XCTAssertTrue(ClusterPanel.select.isLeading)
        XCTAssertEqual(ModelPage.allCases.map(\.rawValue), ["add", "library", "snapping"])
    }

    func testTheInspectorsRoomKeepsClearOfTheChromeAndAnOpenPanel() {
        let size = CGSize(width: 1180, height: 820)
        let insets = EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
        let room = FloatingInspector.room(in: size, insets: insets, sidebarOnRight: false, avoiding: nil)
        XCTAssertEqual(room.minX, 16 + 64, "clear of the sidebar")
        XCTAssertEqual(room.maxX, size.width - 16)
        XCTAssertGreaterThan(room.minY, insets.top + 44, "below the corner clusters")
        XCTAssertLessThan(room.maxY, size.height - 44, "above the bottom row")
        let mirrored = FloatingInspector.room(in: size, insets: insets, sidebarOnRight: true, avoiding: nil)
        XCTAssertEqual(mirrored.maxX, size.width - 16 - 64)
        let leftPanel = FloatingInspector.room(in: size, insets: insets, sidebarOnRight: false, avoiding: CGRect(x: 16, y: 90, width: 380, height: 500))
        XCTAssertEqual(leftPanel.minX, 16 + 380 + 12)
        let rightPanel = FloatingInspector.room(in: size, insets: insets, sidebarOnRight: false, avoiding: CGRect(x: 780, y: 90, width: 380, height: 500))
        XCTAssertEqual(rightPanel.maxX, 780 - 12, "right to left: the leading panel is on the right")
    }
}
