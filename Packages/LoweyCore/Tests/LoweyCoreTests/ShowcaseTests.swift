import Foundation
@testable import LoweyCore
import XCTest

/// The shipped samples, built from the real Kit (`App/Resources/Kit`): they compile, everything stands on something,
/// nothing intersects, and each set is in its Look.
final class ShowcaseTests: XCTestCase {
    private func kit() throws -> [LibraryAsset] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Kit")
        let assets = try KitIndex.load(from: root).assets
        XCTAssertGreaterThan(assets.count, 300)
        return assets
    }

    /// Kit objects that float or stand off the ground on purpose.
    private let floating: Set<String> = ["Robot", "Canoe"]

    private func assertWellPlaced(_ scene: Scene, kit: [LibraryAsset], file: StaticString = #filePath, line: UInt = #line) {
        var library = LibraryManifest()
        library.kit = kit
        let solver = RelationSolver(scene: scene, library: library)
        let placed = scene.roots.filter { scene.objects[$0]?.kind.assetID?.raw.hasPrefix("kit.") == true }
        XCTAssertFalse(placed.isEmpty, "built from the Kit", file: file, line: line)
        for id in placed where !floating.contains(scene.objects[id]?.name ?? "") {
            let grounded = solver.isGrounded(id)
            XCTAssertTrue(grounded.grounded, "“\(scene.objects[id]?.name ?? "")” floats \(grounded.gap) m in \(scene.name)", file: file, line: line)
        }
        let boxes = Dictionary(uniqueKeysWithValues: placed.compactMap { id in solver.bounds.worldBounds(of: id, in: scene).map { (id, $0) } })
        for (index, a) in placed.enumerated() {
            for b in placed.dropFirst(index + 1) {
                guard let boxA = boxes[a], let boxB = boxes[b] else { continue }
                XCTAssertFalse(RelationSolver.overlap(boxA, boxB, margin: 0.02),
                               "“\(scene.objects[a]?.name ?? "")” cuts into “\(scene.objects[b]?.name ?? "")” in \(scene.name)", file: file, line: line)
            }
        }
    }

    func testTheWelcomeIsland() throws {
        let kit = try kit()
        let (info, scenes) = try Showcase.island(kit: kit)
        XCTAssertEqual(info.name, Showcase.islandName)
        XCTAssertEqual(info.look.presetID, LookPreset.ink.id)
        let scene = try XCTUnwrap(scenes.first)
        XCTAssertNotNil(scene.activeCamera)
        XCTAssertFalse(scene.timeline.clipTracks.isEmpty, "the Blob waves")
        XCTAssertFalse(scene.timeline.flipbooks.isEmpty)
        assertWellPlaced(scene, kit: kit)
    }

    func testTheEnigmaSetsAndStory() throws {
        let kit = try kit()
        let (info, scenes) = try Showcase.enigma(kit: kit)
        XCTAssertEqual(info.name, Showcase.enigmaName)
        XCTAssertEqual(scenes.map(\.name), [Showcase.deskName, Showcase.roomName, Showcase.caveName, Showcase.storyName])
        XCTAssertEqual(scenes.map { ($0.look ?? info.look).presetID }, ["ink", "comic", "sketch", "ink"])
        XCTAssertEqual(scenes[1].timeline.stepping, .onTwos, "Comic on twos")
        let accents = scenes[2].objects.values.filter(\.isAccent)
        XCTAssertEqual(accents.map(\.name), ["Robot"], "Sketch: one accent")
        for scene in scenes {
            assertWellPlaced(scene, kit: kit)
        }
        let story = scenes[3]
        XCTAssertEqual(story.timeline.cuts.count, 3, "cut on the words")
        XCTAssertFalse(story.timeline.transcripts.isEmpty)
        XCTAssertGreaterThanOrEqual(story.timeline.flipbooks.count, 3)
        let lamp = try XCTUnwrap(scenes[0].objects.values.first { $0.name == "Lamp" })
        let desk = try XCTUnwrap(scenes[0].objects.values.first { $0.name == "Desk" })
        var library = LibraryManifest()
        library.kit = kit
        let bounds = SceneBounds(library: library)
        let lampBox = try XCTUnwrap(bounds.worldBounds(of: lamp.id, in: scenes[0]))
        XCTAssertEqual(lampBox.min.y, try XCTUnwrap(bounds.worldBounds(of: desk.id, in: scenes[0])).max.y, accuracy: 0.02, "the lamp is on the desk")
    }
}
