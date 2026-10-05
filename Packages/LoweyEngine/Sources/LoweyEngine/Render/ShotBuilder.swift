import CoreGraphics
import Foundation
import LoweyCore

/// Builds the renderer's request for a moment of a document, exactly the same way for the stage's playback, a
/// snapshot and every exported frame: animation evaluated, the cut's camera framed for the output shape, the
/// transition and screen effects of that moment, overlays and burnt-in captions drawn at the output size.
@MainActor
public final class ShotBuilder {
    public var document: Document
    public var catalog: AssetCatalog
    public let models: ModelLibrary
    /// Stills in the project's assets and decoded video frames, by key.
    public var mediaImage: (String) -> CGImage? = { _ in nil }
    private var captionPages: [Framing: [CaptionPage]] = [:]

    public init(document: Document, catalog: AssetCatalog, models: ModelLibrary = .shared) {
        self.document = document
        self.catalog = catalog
        self.models = models
    }

    public var timeline: Timeline { document.scene.timeline }

    /// Rigs the animator needs: every character with a clip track and every clip's source.
    public func rigs() -> [AssetID: RigAsset] {
        guard !timeline.clipTracks.isEmpty else { return [:] }
        var needed = Set<AssetID>()
        for track in timeline.clipTracks {
            if let asset = document.scene.objects[track.target]?.kind.assetID { needed.insert(asset) }
            for segment in track.segments {
                needed.insert(segment.clip.asset)
            }
        }
        var result: [AssetID: RigAsset] = [:]
        for id in needed {
            guard let asset = catalog.manifest.asset(id) else { continue }
            _ = models.model(asset, catalog: catalog)
            if let rig = models.rig(id) { result[id] = rig }
        }
        return result
    }

    /// The evaluated scene at `time`.
    public func evaluate(at time: Double, overrides: [ObjectID: [PropertyKey: PropertyValue]] = [:]) -> AnimatedScene {
        Animator.evaluate(document, at: time, rigs: rigs(), overrides: overrides)
    }

    /// The request for `time` in a frame of `size` pixels.
    public func request(at time: Double, framing: Framing, size: CGSize, frameIndex: Int, transparent: Bool = false,
                        renderScale: Float = 1, animated: AnimatedScene? = nil, captions: Bool = true) -> FrameRequest {
        let animated = animated ?? evaluate(at: time)
        let evaluated = Document(project: document.project, scene: animated.scene)
        let aspect = framing.aspect
        let viewpoint = document.scene.viewpoint
        let transition = timeline.transition(at: time, fallback: document.scene.activeCamera)
        let mainID = transition?.to ?? animated.camera
        let camera = RenderCamera.shot(mainID, in: animated.scene, fallback: viewpoint, aspect: aspect)
        var input = RenderInput(document: evaluated, time: time, poses: animated.poses, mediaImage: mediaImage, catalog: catalog,
                                lightBudget: 16)
        input.smears = Smear.smears(in: document, at: time)
        var request = FrameRequest(input: input, camera: camera, lens: mainID.flatMap { animated.scene.objects[$0] }.map(CameraLens.init),
                                   screen: ScreenEffects.state(at: time, effects: timeline.effects, fps: timeline.fps), frameIndex: frameIndex,
                                   renderScale: renderScale, transparent: transparent)
        if let transition {
            let from = RenderCamera.shot(transition.from, in: animated.scene, fallback: viewpoint, aspect: aspect)
            request.transition = (from, animated.scene.objects[transition.from].map(CameraLens.init), transition.kind, transition.progress)
        }
        request.overlay = overlayImage(animated, camera: camera, framing: framing, size: size, captions: captions)
        request.flipbooks = flipbookDraws(animated, camera: camera, size: size)
        return request
    }

    /// Overlays (titles, labels, arrows…) and captions drawn by Core Graphics at the frame's size (nil when none).
    /// The flipbook drawings showing at the moment, laid out for a frame of `size` pixels.
    public func flipbookDraws(_ animated: AnimatedScene, camera: RenderCamera, size: CGSize) -> [FlipbookDraw] {
        guard !timeline.flipbooks.isEmpty else { return [] }
        let pose = CoreTransform(position: Vec3(camera.position), rotation: Quat(camera.orientation))
        let layout = FlipbookLayout(width: Double(size.width), height: Double(size.height), camera: pose, fieldOfView: Double(camera.fieldOfView))
        return layout.draws(timeline, scene: animated.scene, palette: document.palette, at: animated.time)
    }

    public func overlayImage(_ animated: AnimatedScene, camera: RenderCamera, framing: Framing, size: CGSize, captions: Bool) -> CGImage? {
        let cameraTransform = CoreTransform(position: Vec3(camera.position), rotation: Quat(camera.orientation))
        let placements = OverlayLayout.placements(in: animated.scene, palette: document.palette, width: Double(size.width),
                                                  height: Double(size.height), time: animated.time) { point in
            OverlayLayout.project(point, camera: cameraTransform, fieldOfView: Double(camera.fieldOfView), aspect: framing.aspect)
        }
        let settings = timeline.captions
        let burns = captions && (settings?.enabled ?? false) && (settings?.burnIn ?? false) && !timeline.transcripts.isEmpty
        let caption = burns ? Captions.page(at: animated.time, in: pages(for: framing)) : nil
        guard !placements.isEmpty || caption != nil else { return nil }
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        OverlayRenderer.draw(placements, in: context, size: size, image: mediaImage)
        if let caption, let settings {
            OverlayRenderer.drawCaption(caption.page, activeWord: caption.word, settings: settings, in: context, size: size)
        }
        return context.makeImage()
    }

    /// Caption pages for a framing (narrow frames get shorter lines).
    func pages(for framing: Framing) -> [CaptionPage] {
        if let cached = captionPages[framing] { return cached }
        guard let settings = timeline.captions else { return [] }
        let factor = framing.aspect < 1 ? 0.6 : (framing.aspect == 1 ? 0.8 : 1)
        let pages = Captions.pages(timeline.words, maxCharacters: max(Int(Double(settings.maxCharacters) * factor), 8), maxLines: settings.maxLines)
        captionPages[framing] = pages
        return pages
    }
}
