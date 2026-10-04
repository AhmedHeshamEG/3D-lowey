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

    /// Each sample, seen through its shot camera halfway through, passes the rubric's geometric lines (Focus, Ground,
    /// Scale, Clutter) — the same checks `observe` gives the AI. (Read and Light need pixels: the Engine's tests.)
    func testTheSamplesPassTheRubric() throws {
        let kit = try kit()
        var library = LibraryManifest()
        library.kit = kit
        let (islandInfo, island) = try Showcase.island(kit: kit)
        let (enigmaInfo, enigma) = try Showcase.enigma(kit: kit)
        // Each shot's subject, and a moment it's on screen.
        let subjects = ["Hesham", "Army message", "Screen 5", "Robot", "Screen 5"]
        let times = [2.4, 4.4, 3, 3, 6.4]
        let shots = island.map { (islandInfo, $0) } + enigma.map { (enigmaInfo, $0) }
        for (index, (info, scene)) in shots.enumerated() {
            let document = Document(project: info, scene: scene)
            let report = ShotObserver(document: document, library: library).observe(at: times[index], subject: subjects[index])
            print("observe · \(scene.name): \(report.summary)")
            XCTAssertEqual(report.frame.subject, subjects[index], scene.name)
            for check in report.checks where ["Focus", "Ground", "Scale", "Clutter"].contains(check.name) {
                XCTAssertNotEqual(check.result, .fail, "\(scene.name) · \(check.name): \(check.detail)")
            }
        }
    }

    /// Every Kit model loads at the real size its metadata says (the size the solver and perception use). Found by
    /// observe: Kenney's stray "tmpParent" node made the reader skip the Kit's scaling root, so whole packs drew at a
    /// third of their size.
    func testEveryKitModelLoadsAtItsRealSize() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Kit")
        var wrong: [String] = []
        for asset in try kit() where asset.kit?.clipsOnly != true {
            guard let real = asset.kit?.realSize else { continue }
            let model = try GLTFMeshReader.model(contentsOf: root.appendingPathComponent(asset.file))
            // Skinned parts are sized by their skeleton when drawn; the rest must match as they are.
            let points = model.parts.filter { !$0.isSkinned }.flatMap(\.mesh.positions).map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
            guard let box = Bounds(points: points) else { continue }
            if abs(box.size.y - real.y) > max(real.y * 0.03, 0.01) {
                wrong.append("\(asset.id.raw): \(String(format: "%.2f", box.size.y)) m drawn, \(real.y) m real")
            }
        }
        XCTAssertTrue(wrong.isEmpty, wrong.prefix(10).joined(separator: "\n"))
    }
}
