import Foundation
@testable import LoweyCore
import XCTest

final class StarterTemplateTests: XCTestCase {
    func testEveryKindHasOneTemplateInOrder() {
        XCTAssertEqual(StarterTemplate.all.map(\.kind), StarterTemplate.Kind.allCases)
        for template in StarterTemplate.all {
            XCTAssertEqual(StarterTemplate.template(template.kind), template)
            XCTAssertEqual(template.workspace.template, template.kind, "a project remembers the template it came from")
            XCTAssertFalse(template.title.isEmpty)
            XCTAssertFalse(template.subtitle.isEmpty)
            XCTAssertTrue(LookPreset.builtIns.contains { $0.id == template.lookPresetID })
        }
    }

    func testTemplatesSetTheJobUpWithoutPlacingAnything() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (url, document) = try store.createProject(name: "Bracket", template: .print)
        XCTAssertTrue(document.scene.objects.isEmpty, "templates fill no scene")
        XCTAssertEqual(document.project.look.presetID, LookPreset.clay.id)
        XCTAssertEqual(document.project.look.lightingPreset, .studio)
        XCTAssertEqual(document.scene.viewpoint.distance, 0.6)
        let workspace = store.loadWorkspace(at: url)
        XCTAssertEqual(workspace.template, .print)
        XCTAssertTrue(workspace.snap.grid)
        XCTAssertEqual(workspace.snap.gridSize, 0.01)
        XCTAssertEqual(workspace.shapeSize, 0.05)
        XCTAssertEqual(workspace.firstPanel, "model")
        XCTAssertEqual(workspace.timeline, .hidden)
        XCTAssertEqual(try store.openDocument(at: url).scene.viewpoint, document.scene.viewpoint, "the starting view is saved with the scene")
    }

    func testAChosenLookWinsOverTheSuggestion() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        var look = Look.default.applying(.night)
        look.presetID = LookPreset.comic.id
        let (_, document) = try store.createProject(name: "Moody", template: .animation, look: look)
        XCTAssertEqual(document.project.look.presetID, LookPreset.comic.id)
        XCTAssertEqual(document.project.look.lightingPreset, .night)
    }

    func testTimelineTemplates() {
        XCTAssertEqual(StarterTemplate.animation.workspace.timeline, .full)
        XCTAssertEqual(StarterTemplate.character.workspace.timeline, .transport)
        XCTAssertEqual(StarterTemplate.character.workspace.firstPanel, "cast")
        XCTAssertEqual(StarterTemplate.blank.workspace.timeline, .hidden, "the timeline is on call: hidden by default")
    }

    func testSketchOpensOnTheBoard() throws {
        XCTAssertEqual(StarterTemplate.sketch.workspace.firstPanel, ProjectWorkspace.boardPanel)
        XCTAssertEqual(StarterTemplate.sketch.lookPresetID, LookPreset.sketch.id)
        let store = try ProjectStore(root: temporaryDirectory())
        let (url, document) = try store.createProject(name: "Tower", template: .sketch)
        XCTAssertTrue(document.scene.objects.isEmpty)
        XCTAssertEqual(store.loadWorkspace(at: url).firstPanel, "board")
    }
}

final class ProjectWorkspaceTests: XCTestCase {
    func testAProjectWithoutAWorkspaceOpensWithTheDefaults() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (url, _) = try store.createProject(name: "Old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProjectStore.workspaceURL(in: url).path))
        let workspace = store.loadWorkspace(at: url)
        XCTAssertEqual(workspace, ProjectWorkspace())
        XCTAssertEqual(workspace.timeline, .hidden)
        XCTAssertEqual(workspace.timelineHeight, ProjectWorkspace.defaultTimelineHeight)
        XCTAssertNil(workspace.template)
    }

    func testRoundTripsAndSurvivesDuplication() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (url, _) = try store.createProject(name: "Room")
        var workspace = ProjectWorkspace(template: .room, timeline: .full, timelineHeight: 420)
        workspace.snap.grid = true
        workspace.showsGrid = false
        try store.saveWorkspace(workspace, at: url)
        XCTAssertEqual(store.loadWorkspace(at: url), workspace)
        let copy = try store.duplicateProject(at: url)
        XCTAssertEqual(store.loadWorkspace(at: copy), workspace)
    }

    func testDamagedOrFutureValuesFallBackInsteadOfFailing() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (url, _) = try store.createProject(name: "Odd")
        let json = #"{"schemaVersion": 9, "template": "spaceship", "timeline": "floating", "timelineHeight": 99999, "shapeSize": -3, "showsGrid": false}"#
        try Data(json.utf8).write(to: ProjectStore.workspaceURL(in: url))
        let workspace = store.loadWorkspace(at: url)
        XCTAssertNil(workspace.template)
        XCTAssertEqual(workspace.timeline, .hidden)
        XCTAssertEqual(workspace.timelineHeight, ProjectWorkspace.timelineHeightRange.upperBound)
        XCTAssertEqual(workspace.shapeSize, 1)
        XCTAssertFalse(workspace.showsGrid)
        XCTAssertEqual(workspace.schemaVersion, 9)
        try Data("not json".utf8).write(to: ProjectStore.workspaceURL(in: url))
        XCTAssertEqual(store.loadWorkspace(at: url), ProjectWorkspace())
    }

    func testReferenceCardsStayWithTheWorkspace() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (url, _) = try store.createProject(name: "Pinned")
        var workspace = ProjectWorkspace()
        let place = ReferenceCard.place(after: workspace.references)
        workspace.references.append(ReferenceCard(id: "a", image: "references/1.png", title: "Shots", x: place.x, y: place.y, aspect: 0.75))
        let next = ReferenceCard.place(after: workspace.references)
        XCTAssertNotEqual(next.x, place.x, "the next card doesn't land on the last")
        try store.saveWorkspace(workspace, at: url)
        XCTAssertEqual(store.loadWorkspace(at: url).references, workspace.references)
        // A card a file puts off the stage, or makes absurdly large, comes back somewhere a hand can reach.
        let json = #"{"references": [{"id": "b", "image": "x.png", "title": "", "x": 7, "y": -2, "width": 99999, "aspect": 0}]}"#
        try Data(json.utf8).write(to: ProjectStore.workspaceURL(in: url))
        let card = try XCTUnwrap(store.loadWorkspace(at: url).references.first)
        XCTAssertEqual(card.x, 1)
        XCTAssertEqual(card.y, 0)
        XCTAssertEqual(card.width, ReferenceCard.widthRange.upperBound)
        XCTAssertEqual(card.aspect, 1)
        XCTAssertEqual(ReferenceCard(id: "c", image: "y.png", x: .nan, width: .infinity).x, 0.5)
        XCTAssertEqual(ReferenceCard(id: "c", image: "y.png", x: .nan, width: .infinity).width, ReferenceCard.defaultWidth)
    }
}
