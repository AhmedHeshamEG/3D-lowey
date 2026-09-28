import AVFoundation
import LoweyCore
@testable import LoweyRender
import LoweyScript
import RealityKit
import UIKit
import XCTest

/// Phase 2 on the simulator: animated renders, video export, characters, scripts, 3D export.
@MainActor
final class Phase2Tests: XCTestCase {
    private func fixture(_ path: String) throws -> URL {
        let bundle = Bundle(for: Phase2Tests.self)
        return try XCTUnwrap(bundle.resourceURL).appendingPathComponent("Fixtures").appendingPathComponent(path)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lowey-p2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func attach(_ image: CGImage, name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data, let pointer = CFDataGetBytePtr(data) else { return [] }
        return Array(UnsafeBufferPointer(start: pointer, count: CFDataGetLength(data)))
    }

    private func variety(_ image: CGImage) -> Double {
        let pixels = bytes(image)
        guard pixels.count >= 4 else { return 0 }
        let bpp = image.bitsPerPixel / 8
        var different = 0
        var total = 0
        for index in stride(from: 0, to: pixels.count - bpp, by: bpp * 37) {
            let delta = abs(Int(pixels[index]) - Int(pixels[0])) + abs(Int(pixels[index + 1]) - Int(pixels[1])) + abs(Int(pixels[index + 2]) - Int(pixels[2]))
            if delta > 24 { different += 1 }
            total += 1
        }
        return Double(different) / Double(max(total, 1))
    }

    private func opening() throws -> Document {
        let (info, scenes) = try EnigmaSample.buildWithOpening()
        return try Document(project: info, scene: XCTUnwrap(scenes.last))
    }

    // MARK: The Enigma opening, rendered

    func testEnigmaOpeningRendersThroughItsCameras() async throws {
        let document = try opening()
        let exporter = VideoExporter(document: document, library: nil, rigs: RigCache())
        for (time, beat) in [(1.0, "desk-push-in"), (5.0, "room-paper-grows"), (7.6, "big-x"), (9.8, "hero-robot"), (11.6, "question-mark")] {
            let images = try await exporter.images(at: time, framings: [.landscape, .portrait], longSide: 640)
            XCTAssertEqual(images.count, 2)
            XCTAssertEqual(images[0].width, 640)
            XCTAssertEqual(images[1].height, 640)
            for (image, framing) in zip(images, ["16x9", "9x16"]) {
                XCTAssertGreaterThan(variety(image), 0.03, "\(beat) \(framing) looks blank")
                attach(image, name: "opening-\(beat)-\(framing)")
            }
        }
    }

    func testExportIsDeterministic() async throws {
        let document = try opening()
        let first = try await VideoExporter(document: document, library: nil, rigs: RigCache()).images(at: 7.4, framings: [.landscape], longSide: 320)
        let second = try await VideoExporter(document: document, library: nil, rigs: RigCache()).images(at: 7.4, framings: [.landscape], longSide: 320)
        let a = try bytes(XCTUnwrap(first.first))
        let b = try bytes(XCTUnwrap(second.first))
        XCTAssertEqual(a.count, b.count)
        var differing = 0
        for index in a.indices where abs(Int(a[index]) - Int(b[index])) > 2 {
            differing += 1
        }
        XCTAssertLessThan(Double(differing) / Double(max(a.count, 1)), 0.001, "the same scene renders the same frame twice")
    }

    func testVideoExportWritesSixteenNineAndNineSixteen() async throws {
        let document = try opening()
        let folder = try temporaryDirectory()
        var progress: [Double] = []
        let settings = VideoExportSettings(framings: [.landscape, .portrait], longSide: 480, range: TimeRange(start: 6.8, end: 7.8), fps: 24)
        let urls = try await VideoExporter(document: document, library: nil, rigs: RigCache())
            .export(settings: settings, to: folder, baseName: "Opening") { progress.append($0) }
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(progress.last ?? 0, 1, accuracy: 1e-9)
        for (url, size) in zip(urls, [CGSize(width: 480, height: 270), CGSize(width: 270, height: 480)]) {
            XCTAssertEqual(url.pathExtension, "mp4")
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            XCTAssertEqual(duration.seconds, 1, accuracy: 0.1, "\(url.lastPathComponent)")
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let natural = try await track.load(.naturalSize)
            XCTAssertEqual(natural.width, size.width)
            XCTAssertEqual(natural.height, size.height)
            // The video decodes (plays in Photos): grab a frame from the middle.
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let (frame, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
            attach(frame, name: "video-frame-\(Int(size.width))x\(Int(size.height))")
        }
    }

    func testPNGSequenceAndTransparentBackground() async throws {
        let document = try opening()
        let folder = try temporaryDirectory()
        let settings = VideoExportSettings(framings: [.square], longSide: 256, range: TimeRange(start: 10.5, end: 10.75), fps: 12,
                                           format: .pngSequence, transparent: true)
        let urls = try await VideoExporter(document: document, library: nil, rigs: RigCache())
            .export(settings: settings, to: folder, baseName: "Question") { _ in }
        let frames = try FileManager.default.contentsOfDirectory(atPath: XCTUnwrap(urls.first).path).filter { $0.hasSuffix(".png") }
        XCTAssertEqual(frames.count, 3)
        let image = try XCTUnwrap(UIImage(contentsOfFile: urls[0].appendingPathComponent("frame_00003.png").path)?.cgImage)
        XCTAssertNotEqual(image.alphaInfo, .none)
        // One cube in an empty world: the background is see-through, the cube solid.
        var scene = CoreScene(id: "t", name: "t")
        var cube = SceneObject(id: "cube", name: "Cube", kind: .primitive(.cube))
        cube[.color] = .color(.rgba(RGBA(1, 0.5, 0.2)))
        scene.objects["cube"] = cube
        scene.roots = ["cube"]
        scene.viewpoint = Viewpoint(target: Vec3(0, 0.5, 0), yaw: 30, pitch: 20, distance: 3)
        let single = Document(project: ProjectInfo(id: "p", name: "p"), scene: scene)
        let transparent = try await VideoExporter(document: single, library: nil, rigs: RigCache())
            .images(at: 0, framings: [.square], longSide: 128, transparent: true)
        let matte = try XCTUnwrap(transparent.first)
        let pixels = bytes(matte)
        XCTAssertLessThan(pixels[3], 10, "the background is see-through")
        let center = 64 * matte.bytesPerRow + 64 * 4
        XCTAssertGreaterThan(pixels[center + 3], 245, "the cube is solid")
        attach(matte, name: "transparent-cube")
    }

    // MARK: Characters

    func testRiggedTigerWalksAlongAPathWithItsWalkClip() async throws {
        let root = try temporaryDirectory()
        let store = LibraryStore(root: root)
        var tiger = try store.importModel(from: fixture("AnimalPack/Tiger_Rigged.glb"), id: "tiger")
        tiger.rig = .quadruped
        tiger.clips = ["Walk"]
        let library = TestLibrary(store: store)
        library.manifest.assets = [tiger]
        let rigs = RigCache()
        let rig = try XCTUnwrap(rigs.rig(for: tiger, url: store.fileURL(for: tiger)), "the glTF skeleton is read in Core")
        XCTAssertEqual(rig.clipNames, ["Walk"])
        XCTAssertEqual(rig.standard, .quadruped)

        var scene = CoreScene(id: "s", name: "Tiger walk")
        scene.objects["tiger-1"] = SceneObject(id: "tiger-1", name: "Tiger", kind: .asset("tiger"))
        scene.roots = ["tiger-1"]
        scene.timeline.clipTracks = [ClipTrack(id: "walk", target: "tiger-1", segments: [
            ClipSegment(id: "w", clip: ClipRef(asset: "tiger", name: "Walk"), start: 0, duration: 4)
        ])]
        scene.timeline.behaviors = [Behavior(id: "path", target: "tiger-1",
                                             kind: .followPath(
                                                 .points([Vec3(-3, 0, 0), Vec3(0, 0, 2), Vec3(3, 0, 0)]),
                                                 duration: 4,
                                                 loop: false,
                                                 orient: true
                                             ))]
        scene.viewpoint = Viewpoint(target: Vec3(0, 0.5, 0.5), yaw: 20, pitch: 30, distance: 9)
        let document = Document(project: ProjectInfo(id: "p", name: "p"), scene: scene)
        let rigTable = rigs.rigs(for: document, library: library)
        XCTAssertNotNil(rigTable["tiger"])

        let renderer = SceneRenderer()
        renderer.library = library
        var positions: [Vec3] = []
        var spineHeights: [Float] = []
        for time in [0.25, 0.5, 2.0] {
            let animated = Animator.evaluate(document, at: time, rigs: rigTable)
            let evaluated = Document(project: document.project, scene: animated.scene)
            if positions.isEmpty {
                renderer.load(evaluated)
                await renderer.waitForAssets()
                renderer.load(evaluated)
            } else {
                renderer.sync(evaluated, changes: ChangeSet(objects: ["tiger-1"]))
            }
            renderer.applyPoses(animated.poses, rigs: rigTable)
            XCTAssertNotNil(animated.poses["tiger-1"], "the Walk clip poses the skeleton")
            try positions.append(Vec3(XCTUnwrap(renderer.node(for: "tiger-1")).position(relativeTo: nil)))
            var spine: Float?
            try AssetLoader.visitModels(XCTUnwrap(renderer.node(for: "tiger-1"))) { entity in
                guard let model = entity as? ModelEntity,
                      let index = model.jointNames.firstIndex(where: { SceneRenderer.jointKey($0) == "spine" }) else { return }
                spine = model.jointTransforms[index].translation.y
            }
            try spineHeights.append(XCTUnwrap(spine, "the model's joints are reachable by name"))
            if time == 2.0 {
                let image = try await OffscreenRenderer().snapshot(of: renderer, viewpoint: scene.viewpoint, framing: .landscape, longSide: 640)
                attach(image, name: "tiger-walks-path")
            }
        }
        XCTAssertGreaterThan(positions[2].distance(to: positions[0]), 1, "it walks along the path")
        XCTAssertGreaterThan(abs(spineHeights[0] - spineHeights[1]), 0.01, "the walk clip moves the spine: \(spineHeights)")
    }

    // MARK: Scripts

    func testExampleScriptsBuildAndAnimate() throws {
        for example in ScriptExamples.all {
            var document = Document(project: ProjectInfo(id: "p", name: "p"), scene: CoreScene(id: "s", name: "s"))
            let outcome = ScriptRunner.runSynchronously(example.source, name: example.name, document: document, selection: [], time: 0)
            XCTAssertNil(outcome.error, "\(example.name): \(outcome.error ?? "")")
            let command = try XCTUnwrap(outcome.command, example.name)
            _ = try command.apply(to: &document)
            XCTAssertFalse(document.scene.timeline.isEmpty, "\(example.name) animates")
            XCTAssertFalse(outcome.log.isEmpty)
            let groups = document.scene.roots.count
            switch example.name {
            case ScriptExamples.forest.name: XCTAssertEqual(groups, 40)
            case ScriptExamples.flock.name: XCTAssertEqual(groups, 24)
            default: XCTAssertEqual(groups, 16)
            }
            // Undo is exact: the command's inverse restores the empty scene.
            var undone = Document(project: ProjectInfo(id: "p", name: "p"), scene: CoreScene(id: "s", name: "s"))
            let (inverse, _) = try command.apply(to: &undone)
            _ = try inverse.apply(to: &undone)
            XCTAssertTrue(undone.scene.objects.isEmpty)
        }
    }

    func testScriptErrorsAreReportedWithLines() {
        let document = Document(project: ProjectInfo(id: "p", name: "p"), scene: CoreScene(id: "s", name: "s"))
        let syntax = ScriptRunner.runSynchronously("let x = ;", name: "Bad", document: document, selection: [], time: 0)
        XCTAssertNotNil(syntax.error)
        XCTAssertNil(syntax.command)
        let api = ScriptRunner.runSynchronously("lowey.add(\"teapot\")", name: "Bad", document: document, selection: [], time: 0)
        XCTAssertTrue(api.error?.contains("teapot") == true, api.error ?? "")
        let keyed = ScriptRunner.runSynchronously("""
        const id = lowey.add("cube", { position: [0, 0, 0], color: "#ff8800" });
        lowey.key(id, "position", 1, [0, 2, 0], "easeOut");
        lowey.set(id, "emissiveIntensity", 2);
        lowey.log(scene.objects().length);
        """, name: "Key", document: document, selection: [], time: 0)
        XCTAssertNil(keyed.error)
        XCTAssertEqual(keyed.log, ["1"])
        XCTAssertEqual(keyed.created.count, 1)
    }

    // MARK: 3D export

    func testSceneExportsAsGLBAndUSDZ() throws {
        let (info, scenes) = try EnigmaSample.build()
        let renderer = SceneRenderer()
        renderer.load(Document(project: info, scene: scenes[2]))
        let meshes = ModelExport.meshes(nil, scene: scenes[2], look: scenes[2].look ?? info.look, renderer: renderer)
        XCTAssertGreaterThan(meshes.count, 20)
        let glb = ModelExport.data(.glb, meshes: meshes)
        XCTAssertEqual(glb.prefix(4), Data("glTF".utf8))
        let folder = try temporaryDirectory()
        let url = folder.appendingPathComponent("cave.glb")
        try glb.write(to: url)
        let usdz = folder.appendingPathComponent("cave.usdz")
        try ModelExport.data(.usdz, meshes: meshes).write(to: usdz)
        XCTAssertGreaterThan(try Data(contentsOf: usdz).count, 1000)
    }
}
