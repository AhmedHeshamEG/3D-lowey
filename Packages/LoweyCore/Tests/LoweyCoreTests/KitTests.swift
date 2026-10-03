import Foundation
@testable import LoweyCore
import XCTest

final class KitTests: XCTestCase {
    private func fixtureKit() throws -> KitIndex {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("Kit")
        return try KitIndex.load(from: root)
    }

    func testTheKitLoadsWithItsMetadata() throws {
        let kit = try fixtureKit()
        XCTAssertEqual(kit.sets.map(\.name), ["Office & Computers"])
        let desk = try XCTUnwrap(kit.assets.first)
        XCTAssertEqual(desk.id.raw, "kit.office-desk")
        XCTAssertTrue(desk.isKit)
        XCTAssertEqual(desk.format, .glb)
        XCTAssertEqual(desk.file, "Office-Computers/office-desk.loweyasset/model.glb")
        let info = try XCTUnwrap(desk.kit)
        XCTAssertEqual(info.category, "Desks")
        XCTAssertEqual(info.realSize.y, 0.736, accuracy: 0.01, "a desk is about 74 cm high")
        let top = try XCTUnwrap(info.surfaces.first)
        XCTAssertEqual(top.height, info.realSize.y, accuracy: 0.01, "its top is a surface")
        XCTAssertGreaterThan(top.width, 1)
        XCTAssertEqual(info.front, Vec3(0, 0, 1))
        XCTAssertEqual(kit.browse("Office & Computers").first?.category, "Desks")
    }

    func testKitAssetsAreFoundButNeverSaved() throws {
        let kit = try fixtureKit()
        var manifest = LibraryManifest()
        manifest.kit = kit.assets
        XCTAssertNotNil(manifest.asset("kit.office-desk"))
        XCTAssertEqual(LibrarySearch.items(in: manifest, filter: .sets).count, 1)
        XCTAssertEqual(LibrarySearch.search("desk", in: manifest).first?.name, "Desk")
        let data = try JSONEncoder().encode(manifest)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("office-desk"), "the Kit isn't written into library.json")
        // The GLB loads through the reader the renderer uses.
        let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("Kit")
        let model = try GLTFMeshReader.model(contentsOf: root.appendingPathComponent(manifest.kit[0].file))
        XCTAssertFalse(model.parts.isEmpty)
    }
}
