import CoreGraphics
import Foundation
import LoweyCore
@testable import LoweyEngine
import XCTest

/// Drawn rigs through the real renderer (M7): the skinned surface follows the pose on the GPU, exactly as the CPU
/// skins it in Core's checks. Golden images of the acceptance poses.
@MainActor
final class RigRenderTests: XCTestCase {
    /// One stroke along the creature's tail, seen from above.
    private func tailRig(_ mesh: MeshData) throws -> ObjectRig {
        let rays = stride(from: RigSamples.tailStart + 0.12, through: RigSamples.tailEnd - 0.03, by: 0.02).map {
            Ray(origin: Vec3($0, 3, 0), direction: Vec3(0, -1, 0))
        }
        let samples = BoneStroke.centreline(rays: rays, surface: TriangleBVH(mesh))
        return try BoneStroke.addingChain(samples, to: nil, surface: mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) })
    }

    private func applied(_ changes: [PropertyChange], to document: inout Document) {
        for change in changes {
            document.scene.objects[change.object]?.properties[change.key] = change.value
        }
    }

    /// The acceptance pose: a tail drawn on an imported model, its tip dragged up over the back.
    func testADrawnTailBendsOnTheStage() async throws {
        let model = try GLTFMeshReader.model(data: RigSamples.creatureGLB())
        let mesh = try XCTUnwrap(AssetPaint.mergedMesh(model))
        let asset = LibraryAsset(id: "creature", name: "Creature", format: .glb, file: "creature.glb")
        let models = ModelLibrary()
        models.seed(asset.id, model: model, rig: nil)
        let catalog = AssetCatalog(manifest: LibraryManifest(assets: [asset])) { _ in URL(fileURLWithPath: "/dev/null") }
        var object = SceneObject(id: "creature", name: "Creature", kind: .asset(asset.id))
        let weighted = try XCTUnwrap(RigOperations.weighted(tailRig(mesh), object: object, mesh: mesh))
        object.rig = weighted.rig
        var document = TestDocuments.document("Tail", objects: [object], camera: Vec3(0.6, 0.85, 3.4))
        let rest = document
        let tip = try XCTUnwrap(IKHandles.handles(of: object.id, in: document.scene).first { $0.isEnd })
        applied(IKHandles.solve(tip, to: Vec3(0.95, 1.35, 0), in: document.scene, rest: document.scene), to: &document)
        let files = weighted.files
        func render(_ document: Document) async throws -> CGImage {
            let session = try TestDocuments.session(document, catalog: catalog, models: models)
            session.paintFile = { files[$0] }
            return try await session.image(at: 0, framing: .landscape, longSide: 640)
        }
        let posed = try await render(document)
        let still = try await render(rest)
        XCTAssertGreaterThan(GoldenImage().compare(posed, still).differentFraction, 0.01, "the pose reaches the picture")
        // Exports carry the pose: the tail's tip is up over the back in the exported shape.
        let posedObject = try XCTUnwrap(document.scene.objects[object.id])
        let parts = try XCTUnwrap(ModelExport.posedParts(posedObject, pose: nil, look: Look(), catalog: catalog, models: models, file: { files[$0] }))
        XCTAssertGreaterThan(parts.compactMap(\.mesh.bounds).map(\.max.y).max() ?? 0, 1.2, "the exported shape is the posed one")
        try GoldenImage().assertMatches(posed, named: "rig-drawn-tail")
    }

    /// The acceptance walk: the Kit astronaut rigged as a person, mid-stride on the built-in Walk.
    func testAKitAstronautRiggedAsAPersonWalks() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Kit")
        let index = try KitIndex.load(from: root)
        var manifest = LibraryManifest()
        manifest.kit = index.assets
        let catalog = AssetCatalog(manifest: manifest) { root.appendingPathComponent($0.file) }
        let asset = try XCTUnwrap(index.assets.first { $0.id.raw == "kit.space-astronauta" })
        let models = ModelLibrary()
        let loaded = await models.load(asset, catalog: catalog)
        let model = try XCTUnwrap(loaded)
        let mesh = try XCTUnwrap(AssetPaint.mergedMesh(model))
        let bounds = try XCTUnwrap(mesh.bounds)
        let rays = try dots(model).mapValues { Ray(origin: Vec3($0.x, $0.y, bounds.max.z + 5), direction: Vec3(0, 0, -1)) }
        let points = HumanRig.points(rays: rays, surface: TriangleBVH(mesh), bounds: bounds)
        let rig = try XCTUnwrap(HumanRig.rig(from: points, bounds: bounds))
        var object = SceneObject(id: "astro", name: "Astronaut", kind: .asset(asset.id))
        let weighted = try XCTUnwrap(RigOperations.weighted(rig, object: object, mesh: mesh))
        object.rig = weighted.rig
        var document = TestDocuments.document("Walk", objects: [object], camera: Vec3(2.6, 1.1, 2.6), rotation: Quat(eulerDegrees: Vec3(-4, 45, 0)))
        let walk = ClipSegment(id: "walk", clip: ClipRef(asset: BuiltinClips.assetID, name: "Walk"), start: 0, duration: 4)
        document.scene.timeline.clipTracks = [ClipTrack(id: "t", target: object.id, segments: [walk])]
        let session = try TestDocuments.session(document, catalog: catalog, models: models)
        let files = weighted.files
        session.paintFile = { files[$0] }
        let stride = try await session.image(at: (BuiltinClips.rig.clips["Walk"]?.duration ?? 1) * 0.25, framing: .landscape, longSide: 640)
        let start = try await session.image(at: 0, framing: .landscape, longSide: 640)
        XCTAssertGreaterThan(GoldenImage().compare(stride, start).differentFraction, 0.005, "the legs move between the two moments")
        try GoldenImage().assertMatches(stride, named: "rig-astronaut-walk")
    }

    /// Where a person would put the dots: at the astronaut's parts' joints (the character's left is +x).
    private func dots(_ model: ImportedModel) throws -> [HumanRig.Dot: Vec3] {
        var parts: [String: Bounds] = [:]
        for part in model.parts {
            if let bounds = part.mesh.bounds { parts[part.name] = parts[part.name].map { $0.union(bounds) } ?? bounds }
        }
        func part(_ keyword: String, left: Bool?) throws -> Bounds {
            let matches = parts.filter { $0.key.lowercased().contains(keyword) }.map(\.value)
            guard let left else { return try XCTUnwrap(matches.first) }
            return try XCTUnwrap(left ? matches.max { $0.center.x < $1.center.x } : matches.min { $0.center.x < $1.center.x })
        }
        let head = try part("head", left: nil)
        var result: [HumanRig.Dot: Vec3] = [.head: Vec3(head.center.x, head.max.y, 0), .chin: Vec3(head.center.x, head.min.y + head.size.y * 0.15, 0)]
        for (side, left) in [("left", true), ("right", false)] {
            let arm = try part("arm", left: left)
            let leg = try part("leg", left: left)
            let placed: [(String, Vec3)] = [
                ("Shoulder", Vec3(arm.center.x, arm.max.y - arm.size.y * 0.15, 0)), ("Elbow", Vec3(arm.center.x, arm.max.y - arm.size.y * 0.5, 0)),
                ("Wrist", Vec3(arm.center.x, arm.min.y + arm.size.y * 0.15, 0)), ("Hip", Vec3(leg.center.x, leg.max.y - leg.size.y * 0.1, 0)),
                ("Knee", Vec3(leg.center.x, leg.min.y + leg.size.y * 0.5, 0)), ("Ankle", Vec3(leg.center.x, leg.min.y + leg.size.y * 0.15, 0))
            ]
            for (name, point) in placed {
                if let dot = HumanRig.Dot(rawValue: side + name) { result[dot] = point }
            }
        }
        return result
    }
}
