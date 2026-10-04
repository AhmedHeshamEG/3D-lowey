import CoreGraphics
import Foundation
import HmmPerception
import LoweyCore
@testable import LoweyEngine
import XCTest

/// `observe` and `contact_sheet` through the real renderer: every view is drawn, the colour measures come from the
/// pixels, and the shipped samples pass the rubric. The pictures and reports are attached (the PR shows them).
@MainActor
final class ObserveTests: XCTestCase {
    private func kit() throws -> AssetCatalog {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Kit")
        var manifest = LibraryManifest()
        manifest.kit = try KitIndex.load(from: root).assets
        return AssetCatalog(manifest: manifest) { root.appendingPathComponent($0.file) }
    }

    private func attach(_ report: some Encodable, name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = try XCTAttachment(data: encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testEveryViewOfACube() async throws {
        let document = TestScenes.lookCheck(look: LookPreset.ink.id, mood: .day)
        let session = try TestDocuments.session(document)
        let observation = try await session.observe(at: 0, longSide: 640, views: Set(ObserveView.allCases), subject: "Cube",
                                                    library: LibraryManifest())
        XCTAssertEqual(Set(observation.images.keys), Set(ObserveView.allCases))
        for (view, image) in observation.images {
            XCTAssertEqual(image.width, 640, "\(view)")
            GoldenImage().attach(image, name: "observe-cube-\(view.rawValue)")
        }
        let report = observation.report
        XCTAssertEqual(report.frame.subject, "Cube")
        XCTAssertNotNil(report.frame.contrast, "measured from pixels")
        XCTAssertNotNil(report.frame.palette)
        XCTAssertNotEqual(report.checks.first { $0.name == "Read" }?.result, RubricCheck.Result.skipped)
        XCTAssertEqual(report.object(named: "Pip")?.isCharacter, true)
        // The silhouette is black where the cube is and white elsewhere.
        let silhouette = try XCTUnwrap(observation.images[ObserveView.silhouette])
        let dark = GoldenImage.coverage(silhouette)
        XCTAssertGreaterThan(dark.content, 0.01)
        XCTAssertLessThan(dark.content, 0.5)
        try attach(report, name: "observe-cube.json")
    }

    func testTheSamplesPassTheRubric() async throws {
        let catalog = try kit()
        let (islandInfo, island) = try Showcase.island(kit: catalog.manifest.kit)
        let (enigmaInfo, enigma) = try Showcase.enigma(kit: catalog.manifest.kit)
        let shots = island.map { (islandInfo, $0) } + enigma.map { (enigmaInfo, $0) }
        let subjects = ["Hesham", "Army message", "Screen 5", "Robot", "Screen 5"]
        let times = [2.4, 4.4, 3, 3, 6.4]
        for (index, (info, scene)) in shots.enumerated() {
            let session = try TestDocuments.session(Document(project: info, scene: scene), catalog: catalog)
            let observation = try await session.observe(at: times[index], longSide: 960, views: [.camera, .top, .value], subject: subjects[index],
                                                        library: catalog.manifest)
            let report = observation.report
            print("observe · \(scene.name): \(report.summary)")
            for check in report.checks {
                print("   \(check.name): \(check.result.rawValue) — \(check.detail)")
            }
            let slug = "sample-\(index + 1)"
            for (view, image) in observation.images {
                GoldenImage().attach(image, name: "observe-\(slug)-\(view.rawValue)")
            }
            try attach(report, name: "observe-\(slug).json")
            for check in report.checks where check.result == .fail {
                XCTFail("\(scene.name) · \(check.name): \(check.detail)")
            }
        }
    }

    func testAContactSheetOfTheIsland() async throws {
        let catalog = try kit()
        let (info, scenes) = try Showcase.island(kit: catalog.manifest.kit)
        let scene = try XCTUnwrap(scenes.first)
        let session = try TestDocuments.session(Document(project: info, scene: scene), catalog: catalog)
        let sheet = try await session.contactSheet(from: 0, to: scene.timeline.duration, frames: 6, subject: "Hesham", library: catalog.manifest)
        XCTAssertEqual(sheet.report.frames.count, 6)
        let image = try XCTUnwrap(sheet.image)
        XCTAssertGreaterThan(image.width, 1000)
        XCTAssertNotNil(sheet.report.camera, "the camera cranes and orbits")
        print("contact sheet · \(sheet.report.summary)")
        GoldenImage().attach(image, name: "contact-sheet-island")
        try attach(sheet.report, name: "contact-sheet-island.json")
    }
}
