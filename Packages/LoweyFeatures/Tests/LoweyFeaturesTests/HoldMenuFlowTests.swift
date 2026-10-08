import HmmDesign
import LoweyCore
@testable import LoweyFeatures
import XCTest

/// The hold menu's one grammar (CONTEXT §4.1) on the things of a scene: the same first rows and Delete last on an
/// object, a key, a clip and a flipbook drawing, and the rows do what they say in one undo step each.
@MainActor
final class HoldMenuFlowTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Hold \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        return try XCTUnwrap(app.editor)
    }

    private func titles(_ menu: HmmHoldMenu) -> [[String]] {
        menu.sections.map { $0.map(\.title) }
    }

    private func row(_ title: String, in menu: HmmHoldMenu) throws -> HmmHoldMenu.Item {
        try XCTUnwrap(menu.sections.joined().first { $0.title == title }, "no \(title) row")
    }

    func testEveryKindOfThingStartsWithTheSameRows() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection?.id)
        editor.timelineMode = .keyframe
        editor.setTime(1)
        editor.translateSelection(by: Vec3(1, 0, 0), gesture: "key")
        editor.endGesture()
        let key = try XCTUnwrap(KeySelection.all(in: editor.timeline).first)
        let clip = ClipSegment(id: "c", clip: ClipRef(asset: AssetID(raw: "walker"), name: "Walk"), start: 0, duration: 2)
        let menus = [
            editor.holdMenu(for: [cube]),
            editor.holdMenu(forKey: key),
            editor.holdMenu(forClip: clip),
            editor.holdMenu(forFlipbookDrawing: 0, of: "track")
        ]
        for menu in menus {
            let sections = titles(menu)
            XCTAssertEqual(sections.first, ["Duplicate", "Rename", "Copy", "Paste"])
            XCTAssertEqual(sections.last, ["Delete"])
            XCTAssertEqual(sections.count, 3, "extras sit between")
            XCTAssertLessThanOrEqual(sections[1].count, 3)
        }
    }

    func testAnObjectsRowsAct() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection?.id)
        editor.setSelection([])
        let count = editor.scene.objects.count

        try row("Duplicate", in: editor.holdMenu(for: [cube])).action()
        XCTAssertEqual(editor.scene.objects.count, count + 1)
        editor.undo()
        XCTAssertEqual(editor.scene.objects.count, count, "one undo step")

        XCTAssertFalse(try row("Paste", in: editor.holdMenu(for: [cube])).isEnabled, "nothing copied yet")
        try row("Copy", in: editor.holdMenu(for: [cube])).action()
        try row("Paste", in: editor.holdMenu(for: [cube])).action()
        XCTAssertEqual(editor.scene.objects.count, count + 1)
        editor.undo()

        try row("Hide", in: editor.holdMenu(for: [cube])).action()
        XCTAssertEqual(editor.scene.objects[cube]?.isVisible, false)
        XCTAssertEqual(titles(editor.holdMenu(for: [cube]))[1].first, "Show")
        try row("Lock", in: editor.holdMenu(for: [cube])).action()
        XCTAssertEqual(editor.scene.objects[cube]?.isLocked, true)
        try row("Unlock", in: editor.holdMenu(for: [cube])).action()

        try row("Rename", in: editor.holdMenu(for: [cube])).action()
        XCTAssertEqual(editor.renamingObject, cube)
        XCTAssertFalse(try row("Group", in: editor.holdMenu(for: [cube])).isEnabled, "one thing can't be grouped")

        try row("Delete", in: editor.holdMenu(for: [cube])).action()
        XCTAssertNil(editor.scene.objects[cube])
    }

    func testSeveralObjectsGroupAndCannotBeRenamedAtOnce() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection?.id)
        editor.addPrimitive(.sphere)
        let sphere = try XCTUnwrap(editor.singleSelection?.id)
        let menu = editor.holdMenu(for: [cube, sphere])
        XCTAssertFalse(try row("Rename", in: menu).isEnabled)
        try row("Group", in: menu).action()
        let group = try XCTUnwrap(editor.singleSelection)
        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(titles(editor.holdMenu(for: [group.id]))[1].last, "Ungroup")
    }

    func testSplittingAClipAtThePlayhead() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection?.id)
        let whole = ClipSegment(id: "walk", clip: ClipRef(asset: AssetID(raw: "walker"), name: "Walk"), start: 1, duration: 4, offset: 0.5, speed: 2)
        editor.updateTimeline("Clip") { $0.clipTracks = [ClipTrack(id: "track", target: cube, segments: [whole])] }
        editor.setTime(2)
        try row("Split at the playhead", in: editor.holdMenu(forClip: whole)).action()
        let parts = try XCTUnwrap(editor.timeline.clipTracks.first?.segments)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].end, 2, accuracy: 1e-9)
        XCTAssertEqual(parts[1].start, 2, accuracy: 1e-9)
        XCTAssertEqual(parts[1].end, 5, accuracy: 1e-9)
        XCTAssertEqual(parts[1].offset, 2.5, accuracy: 1e-9, "the second half goes on where the first stops")
        editor.undo()
        XCTAssertEqual(editor.timeline.clipTracks.first?.segments.count, 1)
        editor.setTime(0.5)
        XCTAssertFalse(try row("Split at the playhead", in: editor.holdMenu(forClip: whole)).isEnabled, "the playhead isn't on the clip")
    }
}
