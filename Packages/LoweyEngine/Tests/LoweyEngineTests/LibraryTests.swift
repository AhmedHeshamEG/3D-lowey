import CoreGraphics
import LoweyCore
@testable import LoweyEngine
import XCTest

/// Models from the library: an animal pack imported (rigs and clips found, every model drawn), fifty instances in
/// a few instanced draws, a rigged tiger walking a path with its own clip, and an imported box to draw on.
@MainActor
final class LibraryTests: XCTestCase {
    private var store: LibraryStore!
    private var models: ModelLibrary!

    override func setUp() async throws {
        store = try LibraryStore(root: ImageChecks.temporaryFolder("library"))
        models = ModelLibrary()
    }

    private func fixture(_ name: String, in folder: String = "Fixtures/AnimalPack") throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "glb", subdirectory: folder), "missing fixture \(name)")
    }

    private func catalog(_ assets: [LibraryAsset]) -> AssetCatalog {
        var manifest = LibraryManifest()
        manifest.assets = assets
        let store = store!
        return AssetCatalog(manifest: manifest) { store.fileURL(for: $0) }
    }

    /// Imports a model the way the library does: copied in, then measured (bounds, rig, clips).
    private func importAsset(_ url: URL, id: AssetID) async throws -> LibraryAsset {
        var asset = try store.importModel(from: url, id: id)
        let inspected = await models.inspect(asset, catalog: catalog([asset]))
        let info = try XCTUnwrap(inspected, "\(asset.name) loads")
        asset.bounds = info.bounds
        asset.rig = info.rig
        asset.clips = info.clips
        XCTAssertGreaterThan(info.triangleCount, 0, asset.name)
        XCTAssertGreaterThan(info.bounds.size.y, 0.1, asset.name)
        return asset
    }

    /// A frame of one asset, framed by its bounds (what a library thumbnail shows).
    private func portrait(of asset: LibraryAsset) async throws -> CGImage {
        let bounds = asset.bounds ?? Bounds(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 1, 0.5))
        let object = SceneObject(id: "model", name: asset.name, kind: .asset(asset.id))
        let view = Viewpoint(target: bounds.center, yaw: 30, pitch: 18, distance: max(bounds.size.length, 0.5) * 1.6)
        var document = TestDocuments.document(asset.name, objects: [object], camera: view.eye, rotation: view.rotation)
        document.scene.look?.ground.visible = false
        let session = try ExportSession(document: document, catalog: catalog([asset]), device: RenderDevice.sharedDevice(), models: models)
        return try await session.image(at: 0, framing: .square, longSide: 256)
    }

    func testAnimalPackImportsWithRigsClipsAndPictures() async throws {
        var manifest = LibraryManifest()
        for name in ["Chicken", "Fox", "Horse", "Tiger_Rigged"] {
            let asset = try await importAsset(fixture(name), id: AssetID(raw: name.lowercased()))
            let picture = try await portrait(of: asset)
            XCTAssertGreaterThan(GoldenImage.coverage(picture).content, 0.02, "\(asset.name) is drawn")
            GoldenImage().attach(picture, name: "thumbnail-\(asset.name)")
            manifest.assets.append(asset)
        }
        try store.save(manifest)
        let reloaded = try store.load()
        XCTAssertEqual(reloaded.assets.count, 4)
        let tiger = try XCTUnwrap(reloaded.assets.first { $0.name.hasPrefix("Tiger") })
        XCTAssertEqual(tiger.rig, .quadruped, "rig detected from the bone names")
        XCTAssertTrue(tiger.clips.contains("Walk"), "clips kept intact: \(tiger.clips)")
        XCTAssertEqual(LibrarySearch.search("tiger", in: reloaded).first?.name, tiger.name)
    }

    func testFiftyInstancesDrawInAFewInstancedDraws() async throws {
        var fox = try await importAsset(fixture("Fox"), id: "fox")
        fox.bounds = Bounds(min: Vec3(-0.25, 0, -0.5), max: Vec3(0.25, 0.9, 0.6))
        let catalog = catalog([fox])
        var manifest = LibraryManifest()
        manifest.assets = [fox]
        var session = EditSession(document: Document(project: ProjectInfo(id: "p", name: "p"), scene: Scene(id: "s", name: "s")))
        var factory = ObjectFactory(ids: .sequential("f"))
        var operations = Operations(ids: .sequential("o"), library: manifest)
        let source = factory.asset(fox, at: .zero)
        try session.perform(operations.add(source))
        let (scatter, group) = try XCTUnwrap(operations.scatter(source.id, center: .zero, settings: ScatterSettings(count: 50, radius: 12, spacing: 0.3),
                                                                in: session.document.scene))
        try session.perform(scatter)
        XCTAssertEqual(session.document.scene.objects[group]?.children.count, 50)
        var document = session.document
        var ids = IDFactory.sequential("c")
        let camera = TestScenes.camera(ids: &ids, view: Viewpoint(target: Vec3(0, 0.5, 0), yaw: 30, pitch: 35, distance: 22))
        document.scene.objects[camera.id] = camera
        document.scene.roots.append(camera.id)
        document.scene.activeCamera = camera.id
        _ = await models.load(fox, catalog: catalog)
        let frames = try FrameRenderer(device: RenderDevice.sharedDevice(), models: models)
        let builder = ShotBuilder(document: document, catalog: catalog, models: models)
        let request = builder.request(at: 0, framing: .landscape, size: CGSize(width: 1280, height: 720), frameIndex: 0)
        let report = try await frames.render(request, width: 1280, height: 720)
        XCTAssertGreaterThanOrEqual(report.objects, 50)
        XCTAssertLessThan(report.drawCalls, 50, "repeats share one mesh and draw instanced")
        let image = try await frames.image(request, width: 1280, height: 720)
        GoldenImage().attach(image, name: "fifty-foxes")
        XCTAssertGreaterThan(GoldenImage.coverage(image).content, 0.05)
    }

    func testRiggedTigerWalksAlongAPathWithItsWalkClip() async throws {
        var tiger = try await importAsset(fixture("Tiger_Rigged"), id: "tiger")
        tiger.rig = .quadruped
        let catalog = catalog([tiger])
        let rig = try XCTUnwrap(models.rig(tiger.id), "the glTF skeleton is read in Core")
        XCTAssertEqual(rig.clipNames, ["Walk"])
        XCTAssertEqual(rig.standard, .quadruped)
        let walker = SceneObject(id: "tiger-1", name: "Tiger", kind: .asset(tiger.id))
        var document = TestDocuments.document("Tiger walk", objects: [walker], camera: Vec3(0, 4.5, 8.5),
                                              rotation: Quat(angle: -0.5, axis: .unitX), fieldOfView: 50)
        document.scene.timeline.clipTracks = [ClipTrack(id: "walk", target: "tiger-1", segments: [
            ClipSegment(id: "w", clip: ClipRef(asset: tiger.id, name: "Walk"), start: 0, duration: 4)
        ])]
        let path = BehaviorKind.followPath(.points([Vec3(-3, 0, 0), Vec3(0, 0, 2), Vec3(3, 0, 0)]), duration: 4, loop: false, orient: true)
        document.scene.timeline.behaviors = [Behavior(id: "path", target: "tiger-1", kind: path)]
        let builder = ShotBuilder(document: document, catalog: catalog, models: models)
        let early = builder.evaluate(at: 0.25)
        let stride = builder.evaluate(at: 0.5)
        let later = builder.evaluate(at: 2)
        XCTAssertGreaterThan(later.scene.worldTransform(of: "tiger-1").position.distance(to: early.scene.worldTransform(of: "tiger-1").position), 1,
                             "it walks along the path")
        let poseA = try XCTUnwrap(early.poses["tiger-1"], "the Walk clip poses the skeleton")
        let poseB = try XCTUnwrap(stride.poses["tiger-1"])
        XCTAssertTrue(zip(poseA, poseB).contains { $0.rotation != $1.rotation || $0.position != $1.position }, "the clip moves the joints")
        let session = try ExportSession(document: document, catalog: catalog, device: RenderDevice.sharedDevice(), models: models)
        let image = try await session.image(at: 2, framing: .landscape, longSide: 640)
        GoldenImage().attach(image, name: "tiger-walks-path")
        XCTAssertGreaterThan(GoldenImage.coverage(image).content, 0.01)
    }

    /// An imported box keeps its 12 triangles, and drawing on objects raycasts its world mesh.
    func testImportedBoxIsRaycastable() async throws {
        let box = try await importAsset(fixture("box", in: "Fixtures"), id: "box")
        let loaded = await models.load(box, catalog: catalog([box]))
        let model = try XCTUnwrap(loaded)
        var mesh = MeshData()
        for part in model.parts {
            mesh.append(part.mesh)
        }
        XCTAssertEqual(mesh.triangleCount, 12)
        let hit = MeshRaycast.intersect(Ray(origin: Vec3(0, 5, 0), direction: -Vec3.unitY), mesh: mesh)
        XCTAssertEqual(hit?.point.y ?? 0, box.bounds?.max.y ?? 1, accuracy: 1e-4)
    }
}
