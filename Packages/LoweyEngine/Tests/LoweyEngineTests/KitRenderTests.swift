import CoreGraphics
import Foundation
import LoweyCore
@testable import LoweyEngine
import XCTest

/// The Kit through the real renderer: one asset of every Set in the Ink Look, and a desk set built from Kit pieces
/// standing at their real sizes. Frames are attached for review.
@MainActor
final class KitRenderTests: XCTestCase {
    /// The Kit as the app ships it (`App/Resources/Kit` in the repository).
    private func kit() throws -> (KitIndex, AssetCatalog) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Kit")
        let index = try KitIndex.load(from: root)
        var manifest = LibraryManifest()
        manifest.kit = index.assets
        return (index, AssetCatalog(manifest: manifest) { root.appendingPathComponent($0.file) })
    }

    func testOneAssetOfEverySetRenders() async throws {
        let (index, catalog) = try kit()
        XCTAssertGreaterThanOrEqual(index.assets.count, 300, "about 300 curated assets")
        for kitSet in index.sets {
            guard let asset = index.browse(kitSet.name).first?.assets.first else { continue }
            let size = asset.kit?.realSize ?? Vec3(1, 1, 1)
            let reach = max(size.x, size.y, size.z)
            let object = SceneObject(id: "asset", name: asset.name, kind: .asset(asset.id))
            let document = TestDocuments.document(kitSet.name, objects: [object], camera: Vec3(reach * 0.9, size.y * 0.7 + reach * 0.4, reach * 1.8),
                                                  rotation: Quat(eulerDegrees: Vec3(-14, 26, 0)))
            let session = try TestDocuments.session(document, catalog: catalog)
            let image = try await session.image(at: 0, framing: .square, longSide: 320)
            XCTAssertGreaterThan(GoldenImage.coverage(image).content, 0.03, "\(kitSet.name): \(asset.name) is drawn")
            GoldenImage().attach(image, name: "kit-\(kitSet.name)")
        }
    }

    func testADeskSetAtRealSize() async throws {
        let (index, catalog) = try kit()
        let desk = try XCTUnwrap(index.assets.first { $0.id.raw == "kit.office-desk" })
        let chair = try XCTUnwrap(index.assets.first { $0.id.raw == "kit.office-chairdesk" })
        let screen = try XCTUnwrap(index.assets.first { $0.id.raw == "kit.office-computerscreen" })
        let top = try XCTUnwrap(desk.kit?.surfaces.first)
        let objects = [
            SceneObject(id: "desk", name: "Desk", kind: .asset(desk.id)),
            SceneObject(id: "chair", name: "Chair", kind: .asset(chair.id), transform: Transform(position: Vec3(0, 0, 0.7),
                                                                                               rotation: Quat(angle: .pi, axis: .unitY))),
            SceneObject(id: "screen", name: "Screen", kind: .asset(screen.id), transform: Transform(position: Vec3(0, top.height, -0.15)))
        ]
        let document = TestDocuments.document("Desk", objects: objects, camera: Vec3(1.6, 1.5, 2.6), rotation: Quat(eulerDegrees: Vec3(-20, 30, 0)))
        let session = try TestDocuments.session(document, catalog: catalog)
        let image = try await session.image(at: 0, framing: .landscape, longSide: 640)
        XCTAssertGreaterThan(GoldenImage.coverage(image).content, 0.05)
        GoldenImage().attach(image, name: "kit-desk-set")
    }
}
