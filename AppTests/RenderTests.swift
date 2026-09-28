import LoweyCore
@testable import LoweyRender
import RealityKit
import UIKit
import XCTest

/// Library stand-in for the renderer.
@MainActor
final class TestLibrary: LibraryProviding {
    var manifest = LibraryManifest()
    let store: LibraryStore
    var measured: [AssetID: AssetInfo] = [:]

    init(store: LibraryStore) {
        self.store = store
    }

    func fileURL(for asset: LibraryAsset) -> URL { store.fileURL(for: asset) }

    func didMeasure(_ asset: AssetID, info: AssetInfo) {
        measured[asset] = info
        if let index = manifest.assets.firstIndex(where: { $0.id == asset }) {
            manifest.assets[index].bounds = info.bounds
        }
    }
}

@MainActor
final class RenderTests: XCTestCase {
    private func fixture(_ path: String) throws -> URL {
        let bundle = Bundle(for: RenderTests.self)
        let url = try XCTUnwrap(bundle.resourceURL).appendingPathComponent("Fixtures").appendingPathComponent(path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing fixture \(path)")
        return url
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lowey-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func attach(_ image: CGImage, name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Fraction of pixels that differ noticeably from the first pixel (a blank render is ~0).
    private func variety(_ image: CGImage) -> Double {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        let stride = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        let reference = (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
        var different = 0
        var total = 0
        for y in Swift.stride(from: 0, to: image.height, by: 8) {
            for x in Swift.stride(from: 0, to: image.width, by: 8) {
                let offset = y * stride + x * bpp
                let delta = abs(Int(bytes[offset]) - reference.0) + abs(Int(bytes[offset + 1]) - reference.1) + abs(Int(bytes[offset + 2]) - reference.2)
                if delta > 24 { different += 1 }
                total += 1
            }
        }
        return Double(different) / Double(max(total, 1))
    }

    private func waitUntil(timeout: TimeInterval = 20, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: Shader

    /// First launch crashed: the tour opened the welcome island (a scene with post-processing) straight into a new
    /// stage, which installed RealityKit's render callbacks before the view had rendered (RealityKit traps there).
    /// The pass must wait for the stage's first frames, and arrive once it renders.
    func testPostProcessingWaitsForTheFirstFrames() throws {
        let stage = StageView(renderer: SceneRenderer())
        var settings = PostSettings.none
        settings.vignette = 0.4
        stage.post = StagePost(look: FrameLook(post: settings), frameRect: CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertFalse(stage.isPostProcessing, "not installed on a stage that never rendered (this is where it trapped)")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.isHidden = false
        window.addSubview(stage)
        stage.frame = window.bounds
        XCTAssertFalse(stage.isPostProcessing, "still waiting: nothing rendered yet (the second place it trapped)")
        let deadline = Date().addingTimeInterval(5)
        while !stage.isPostProcessing, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard stage.isPostProcessing else {
            throw XCTSkip("the simulator didn't render the stage in a test window; the crash itself is covered above")
        }
        stage.post = nil
        XCTAssertFalse(stage.isPostProcessing)
        stage.removeFromSuperview()
    }

    func testFogShaderCompiledIntoThePackage() {
        XCTAssertTrue(MaterialFactory.shared.customShaderAvailable, "loweySurface must load (fog + glow)")
    }

    // MARK: Offscreen rendering (the Phase 2 export path)

    func testEnigmaSetsRenderOffscreen() async throws {
        let (info, scenes) = try EnigmaSample.build()
        let renderer = SceneRenderer()
        let offscreen = OffscreenRenderer()
        for (index, scene) in scenes.enumerated() {
            renderer.load(Document(project: info, scene: scene))
            for framing in [Framing.landscape, .portrait] {
                let image = try await offscreen.snapshot(of: renderer, viewpoint: scene.viewpoint, framing: framing, longSide: 960)
                let size = framing.pixelSize(longSide: 960)
                XCTAssertEqual(image.width, size.width)
                XCTAssertEqual(image.height, size.height)
                XCTAssertGreaterThan(variety(image), 0.05, "scene \(index) \(framing.rawValue) looks blank")
                attach(image, name: "enigma-\(index + 1)-\(framing.rawValue.replacingOccurrences(of: ":", with: "x"))")
            }
        }
    }

    func testEveryLightingPresetRenders() async throws {
        let (info, scenes) = try EnigmaSample.build()
        var scene = scenes[2]
        let renderer = SceneRenderer()
        let offscreen = OffscreenRenderer()
        for preset in LightingPreset.allCases {
            scene.look = info.look.applying(preset)
            renderer.load(Document(project: info, scene: scene))
            let image = try await offscreen.snapshot(of: renderer, viewpoint: scene.viewpoint, framing: .square, longSide: 512)
            attach(image, name: "preset-\(preset.rawValue)")
            XCTAssertGreaterThan(variety(image), 0.02, "\(preset) looks blank")
        }
    }

    // MARK: Import → library with thumbnails, rig detection

    func testAnimalPackImportsWithThumbnailsAndRig() async throws {
        let root = try temporaryDirectory()
        let store = LibraryStore(root: root)
        let offscreen = OffscreenRenderer()
        let packURL = try fixture("AnimalPack")
        let files = try FileManager.default.contentsOfDirectory(at: packURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "glb" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(files.count, 4)
        var manifest = LibraryManifest()
        for file in files {
            var asset = try store.importModel(from: file)
            let entity = try await AssetLoader.load(url: store.fileURL(for: asset), format: asset.format)
            let info = AssetLoader.info(for: entity)
            asset.bounds = info.bounds
            asset.rig = info.rig
            asset.clips = info.clips
            XCTAssertGreaterThan(info.triangleCount, 0, asset.name)
            XCTAssertGreaterThan(info.bounds.size.y, 0.1, asset.name)
            let thumbnail = try await offscreen.thumbnail(of: entity, size: 256, environment: nil)
            let png = try XCTUnwrap(OffscreenRenderer.pngData(thumbnail))
            try store.writeThumbnail(png, named: LibraryItem.asset(asset).thumbnailName)
            XCTAssertGreaterThan(variety(thumbnail), 0.02, "\(asset.name) thumbnail is blank")
            attach(thumbnail, name: "thumbnail-\(asset.name)")
            manifest.assets.append(asset)
        }
        try store.save(manifest)
        let reloaded = try store.load()
        XCTAssertEqual(reloaded.assets.count, 4)
        for asset in reloaded.assets {
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.thumbnailURL(for: .asset(asset)).path))
        }
        let tiger = try XCTUnwrap(reloaded.assets.first { $0.name.hasPrefix("Tiger") })
        XCTAssertEqual(tiger.rig, .quadruped, "joints: rig detected from bone names")
        XCTAssertTrue(tiger.clips.contains("Walk"), "clips kept intact: \(tiger.clips)")
        XCTAssertEqual(LibrarySearch.search("tiger", in: reloaded).first?.name, tiger.name)
    }

    // MARK: Scene sync & instancing

    func testFiftyInstancesPlaceAndRender() async throws {
        let root = try temporaryDirectory()
        let store = LibraryStore(root: root)
        var fox = try store.importModel(from: fixture("AnimalPack/Fox.glb"), id: "fox")
        fox.bounds = Bounds(min: Vec3(-0.25, 0, -0.5), max: Vec3(0.25, 0.9, 0.6))
        let library = TestLibrary(store: store)
        library.manifest.assets = [fox]

        var session = EditSession(document: Document(project: ProjectInfo(id: "p", name: "p"), scene: CoreScene(id: "s", name: "s")))
        var factory = ObjectFactory(ids: .sequential("f"))
        var operations = Operations(ids: .sequential("o"), library: library.manifest)
        let source = factory.asset(fox, at: .zero)
        try session.perform(operations.add(source))
        let (scatter, group) = try XCTUnwrap(operations.scatter(source.id, center: .zero,
                                                                settings: ScatterSettings(count: 50, radius: 12, spacing: 0.3), in: session.document.scene))
        try session.perform(scatter)
        XCTAssertEqual(session.document.scene.objects[group]?.children.count, 50)

        let renderer = SceneRenderer()
        renderer.library = library
        let start = CFAbsoluteTimeGetCurrent()
        renderer.load(session.document)
        await waitUntil { renderer.assets.cachedPrototype("fox") != nil }
        let children = session.document.scene.objects[group]?.children ?? []
        // Content swaps from placeholder to model once the prototype is loaded.
        await waitUntil {
            children.allSatisfy { id in
                guard let node = renderer.node(for: id) else { return false }
                var models = 0
                AssetLoader.visitModels(node) { _ in models += 1 }
                return models >= 1 && node.visualBounds(recursive: true, relativeTo: nil).extents.y > 0.3
            }
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(elapsed, 15, "placing 50 instances took \(elapsed)s")
        for id in children {
            XCTAssertNotNil(renderer.node(for: id))
        }
        // All instances share one mesh resource (RealityKit batches them).
        var meshes = Set<ObjectIdentifier>()
        for id in children {
            AssetLoader.visitModels(renderer.node(for: id)!) { entity in
                if let mesh = entity.components[ModelComponent.self]?.mesh { meshes.insert(ObjectIdentifier(mesh)) }
            }
        }
        XCTAssertEqual(meshes.count, 1, "instances must share the prototype's mesh")

        var viewpoint = Viewpoint(target: Vec3(0, 0.5, 0), yaw: 30, pitch: 35, distance: 22)
        viewpoint.fieldOfView = 50
        let image = try await OffscreenRenderer().snapshot(of: renderer, viewpoint: viewpoint, framing: .landscape, longSide: 1280)
        attach(image, name: "fifty-foxes")
        XCTAssertGreaterThan(variety(image), 0.05)
    }

    func testDiffSyncOnlyRebuildsChangedObjects() throws {
        let (info, scenes) = try EnigmaSample.build()
        var session = EditSession(document: Document(project: info, scene: scenes[0]))
        let renderer = SceneRenderer()
        renderer.load(session.document)
        let ids = session.document.scene.orderedIDs()
        XCTAssertTrue(ids.allSatisfy { renderer.node(for: $0) != nil })
        let paper = try XCTUnwrap(session.document.scene.objects.values.first { $0.name == "Army message" }).id
        let desk = try XCTUnwrap(session.document.scene.objects.values.first { $0.name == "Desk top" }).id
        let deskContent = renderer.node(for: desk)?.findEntity(named: "content")
        let paperContentBefore = renderer.node(for: paper)?.findEntity(named: "content")
        let changes = try session.perform(.setProperties([PropertyChange(object: paper, key: .color, value: .color(.palette(2)))]))
        renderer.sync(session.document, changes: changes)
        XCTAssertTrue(renderer.node(for: desk)?.findEntity(named: "content") === deskContent, "untouched objects keep their entities")
        // A colour change swaps the material in place (animated colours don't rebuild entities).
        let paperContentAfter = renderer.node(for: paper)?.findEntity(named: "content")
        XCTAssertTrue(paperContentAfter === paperContentBefore, "colour change keeps the entity")
        XCTAssertNotNil((paperContentAfter as? ModelEntity)?.model?.materials.first)
        // Moving only updates the transform.
        let paperContent = renderer.node(for: paper)?.findEntity(named: "content")
        let moved = try session.perform(.setProperties([PropertyChange(object: paper, key: .position, value: .vec3(Vec3(0, 1, 0)))]))
        renderer.sync(session.document, changes: moved)
        XCTAssertTrue(renderer.node(for: paper)?.findEntity(named: "content") === paperContent)
        XCTAssertEqual(renderer.node(for: paper)?.position.y ?? 0, 1, accuracy: 1e-5)
        // Undo deletes → entity removed; redo → back.
        let deleted = try session.perform(.delete([paper]))
        renderer.sync(session.document, changes: deleted)
        XCTAssertNil(renderer.node(for: paper))
        let restored = try XCTUnwrap(try session.undo())
        renderer.sync(session.document, changes: restored)
        XCTAssertNotNil(renderer.node(for: paper))
        // Picking resolves child entities back to their object.
        let content = try XCTUnwrap(renderer.node(for: paper)?.findEntity(named: "content"))
        XCTAssertEqual(renderer.objectID(for: content), paper)
    }

    func testFlatShadingOfImportedModel() async throws {
        let root = try temporaryDirectory()
        let store = LibraryStore(root: root)
        let asset = try store.importModel(from: fixture("box.glb"), id: "box")
        let loader = AssetLoader()
        _ = try await loader.prototype(for: asset, url: store.fileURL(for: asset))
        XCTAssertNotNil(loader.facetedPrototype("box"))
        let mesh = try MeshUpload.meshData(from: XCTUnwrap(loader.cachedPrototype("box")?.findModel()?.mesh))
        XCTAssertEqual(mesh.triangleCount, 12)
        // Drawing on objects: raycast the world mesh.
        let hit = MeshRaycast.intersect(Ray(origin: Vec3(0, 5, 0), direction: -Vec3.unitY), mesh: mesh)
        XCTAssertEqual(hit?.point.y ?? 0, 1, accuracy: 1e-4)
    }
}

private extension Entity {
    func findModel() -> ModelComponent? {
        if let model = components[ModelComponent.self] { return model }
        for child in children {
            if let model = child.findModel() { return model }
        }
        return nil
    }
}
