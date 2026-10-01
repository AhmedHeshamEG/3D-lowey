import CoreGraphics
import Foundation
import HmmMedia
import ImageIO
import LoweyCore
import LoweyEngine

/// Pictures of things, drawn by the same renderer as the stage: project thumbnails and their looping previews,
/// library tiles (models, builds, Looks) and the character builder's portrait.
@MainActor
final class Thumbnailer {
    static let loopFile = "thumbnail-loop.gif"
    private var frames: (renderer: FrameRenderer, models: ModelLibrary)?

    private func renderer(models: ModelLibrary) throws -> FrameRenderer {
        if let frames, frames.models === models { return frames.renderer }
        let made = try FrameRenderer(device: RenderDevice.sharedDevice(), models: models)
        frames = (made, models)
        return made
    }

    /// One frame of a document from a viewpoint (the stage's view).
    func still(_ document: Document, viewpoint: Viewpoint, width: Int, height: Int, catalog: AssetCatalog = .empty,
               models: ModelLibrary = .shared) async throws -> CGImage {
        let input = RenderInput(document: document, catalog: catalog)
        let request = FrameRequest(input: input, camera: RenderCamera(viewpoint: viewpoint))
        return try await renderer(models: models).image(request, width: width, height: height)
    }

    /// The first seconds of a document through its shot camera, a few frames a second (Theater cards loop them).
    func loop(_ document: Document, catalog: AssetCatalog, models: ModelLibrary = .shared, seconds: Double = 2.4, fps: Int = 8,
              longSide: Int = 360) async throws -> [CGImage] {
        let builder = ShotBuilder(document: document, catalog: catalog, models: models)
        let size = Framing.landscape.pixelSize(longSide: longSide)
        let count = max(Int(min(seconds, max(document.scene.timeline.duration, 0.1)) * Double(fps)), 1)
        var images: [CGImage] = []
        for index in 0 ..< count {
            let time = Double(index) / Double(fps)
            let request = builder.request(at: time, framing: .landscape, size: CGSize(width: size.width, height: size.height),
                                          frameIndex: builder.timeline.frame(for: time), captions: false)
            try await images.append(renderer(models: models).image(request, width: size.width, height: size.height))
        }
        return images
    }

    static func writeLoop(_ images: [CGImage], to url: URL, fps: Int = 8) throws {
        let writer = try GIFWriter(url: url, frameCount: images.count, fps: fps)
        for image in images {
            writer.append(image)
        }
        try writer.finish()
    }

    nonisolated static func readLoop(_ url: URL) -> [CGImage]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }
        return (0 ..< count).compactMap { CGImageSourceCreateImageAtIndex(source, $0, nil) }
    }

    /// Objects alone on a studio floor, framed to fit (library tiles, the character portrait).
    func portrait(of fragment: SceneFragment, look presetID: String = LookPreset.ink.id, catalog: AssetCatalog = .empty,
                  models: ModelLibrary = .shared, width: Int = 384, height: Int = 384, yaw: Double = 28, pitch: Double = 16) async throws -> CGImage {
        var look = MoodPresets.look(for: .studio)
        look.presetID = presetID
        look.ground.visible = false
        var scene = CoreScene(id: .make(), name: "Thumbnail")
        for object in fragment.objects {
            scene.objects[object.id] = object
        }
        scene.roots = fragment.roots
        scene.look = look
        let document = Document(project: ProjectInfo(id: .make(), name: "Thumbnail", look: look), scene: scene)
        let bounds = SceneBounds(library: catalog.manifest).worldBounds(of: fragment.roots, in: scene) ?? .unitBase
        let radius = max(bounds.size.length / 2, 0.2)
        let fieldOfView = 30.0
        let distance = radius / sin(fieldOfView * .pi / 360) * 1.05
        let viewpoint = Viewpoint(target: bounds.center, yaw: yaw, pitch: pitch, distance: distance, fieldOfView: fieldOfView)
        return try await still(document, viewpoint: viewpoint, width: width, height: height, catalog: catalog, models: models)
    }

    /// A Look shown on a sphere and a bevelled cube.
    func lookSwatch(_ look: Look, customLooks: [LookPreset] = [], width: Int = 256, height: Int = 256) async throws -> CGImage {
        var ids = IDFactory.random
        var cube = SceneObject(id: ids.next(), name: "Cube", kind: .primitive(.cube), transform: Transform(position: Vec3(-0.55, 0, 0)))
        cube[.color] = .color(.palette(0))
        cube[.bevel] = .float(BevelSpec.standard.radius)
        var sphere = SceneObject(id: ids.next(), name: "Sphere", kind: .primitive(.sphere), transform: Transform(position: Vec3(0.6, 0, 0.2)))
        sphere[.color] = .color(.palette(1))
        var scene = CoreScene(id: .make(), name: "Look")
        scene.objects = [cube.id: cube, sphere.id: sphere]
        scene.roots = [cube.id, sphere.id]
        var project = ProjectInfo(id: .make(), name: "Look", look: look)
        project.customLooks = customLooks
        let document = Document(project: project, scene: scene)
        let viewpoint = Viewpoint(target: Vec3(0, 0.5, 0), yaw: 20, pitch: 18, distance: 3.6, fieldOfView: 35)
        return try await still(document, viewpoint: viewpoint, width: width, height: height)
    }
}
