import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import LoweyCore
import Metal
import os
import RealityKit
import UIKit
import UniformTypeIdentifiers

public enum VideoCodec: String, CaseIterable, Sendable, Identifiable {
    case h264, hevc

    public var id: String { rawValue }
    public var title: String { self == .h264 ? "H.264" : "HEVC" }
}

public enum ExportFormat: String, CaseIterable, Sendable, Identifiable {
    /// .mp4 (or .mov with alpha when transparent).
    case video
    /// One PNG per frame in a folder.
    case pngSequence

    public var id: String { rawValue }
}

public struct VideoExportSettings: Sendable, Hashable {
    public var framings: [Framing]
    /// Long side in pixels (1920 = HD, 3840 = 4K).
    public var longSide: Int
    public var range: TimeRange
    public var fps: Int
    public var codec: VideoCodec
    public var format: ExportFormat
    public var transparent: Bool
    /// The soundtrack for `range`: interleaved stereo at `audioSampleRate` (from `AudioMixer`), or nil for silence.
    public var audio: [Float]?
    public var audioSampleRate: Int

    public init(framings: [Framing] = [.landscape, .portrait], longSide: Int = 1920, range: TimeRange, fps: Int = 30,
                codec: VideoCodec = .h264, format: ExportFormat = .video, transparent: Bool = false,
                audio: [Float]? = nil, audioSampleRate: Int = 48000) {
        self.framings = framings
        self.longSide = longSide
        self.range = range
        self.fps = fps
        self.codec = codec
        self.format = format
        self.transparent = transparent
        self.audio = audio
        self.audioSampleRate = audioSampleRate
    }

    public var frameCount: Int { max(Int((range.duration * Double(fps)).rounded()), 1) }
}

public enum ExportError: Error, CustomStringConvertible {
    case writer(String)
    case cancelled
    case nothingToExport

    public var description: String {
        switch self {
        case let .writer(reason): "The video writer failed: \(reason)"
        case .cancelled: "Export cancelled"
        case .nothingToExport: "Nothing to export"
        }
    }
}

/// Renders a scene frame by frame at a fixed timestep (never real time) and writes videos or
/// PNG sequences. It owns its own world (a second `SceneRenderer` without editor helpers), so the
/// stage stays usable while it runs, and the same document always produces the same frames.
@MainActor
public final class VideoExporter {
    private let document: Document
    private let world = SceneRenderer()
    private let rigCache: RigCache
    private let device: MTLDevice?
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "export")
    private var previousAnimated = Set<ObjectID>()
    /// Second world where every surface writes its distance (lens blur, outlines). Only when the look needs it.
    private var depthWorld: SceneRenderer?
    private var depthSession: RenderSession?
    private var depthTargets: [String: RenderTarget] = [:]
    /// Stored byte → true v (RealityKit's display transform bends even unlit output; measured once per export).
    private var depthTable: [UInt8]?
    private var secondTargets: [String: RenderTarget] = [:]
    private let compositor = FrameCompositor()
    private var captionPages: [Framing: [CaptionPage]] = [:]
    /// Loads overlay images (files in the project's assets folder).
    public var overlayImage: (String) -> CGImage? = { _ in nil }
    /// Where a media file of the project lives (video overlays: clips, Manim renders).
    public var mediaURL: (String) -> URL? = { _ in nil }
    private let videoFrames = VideoFrames(exact: true)
    /// The exact pictures and video frames the cards show this frame (loaded before the frame is shown).
    private var cardFrames: [String: CGImage] = [:]
    /// Whether the GPU may be used now. iOS suspends GPU work in the background (screen locked, another app in
    /// front): the export waits for the app to come back instead of stalling on a frame that never finishes.
    public var canRender: @MainActor () -> Bool = { true }
    /// Called with true while the export waits for the app to come back, false when it resumes.
    public var onWaiting: @MainActor (Bool) -> Void = { _ in }

    public init(document: Document, library: LibraryProviding?, rigs: RigCache) {
        self.document = document
        rigCache = rigs
        device = MTLCreateSystemDefaultDevice()
        world.showsHelpers = false
        world.library = library
        world.mediaImage = { [weak self] key in self?.cardFrames[key] }
        if Self.needsDepth(document) {
            let depth = SceneRenderer()
            depth.showsHelpers = false
            depth.library = library
            depth.depthPass = true
            depthWorld = depth
        }
    }

    // MARK: What a frame needs

    private var timeline: Timeline { document.scene.timeline }
    private var post: PostSettings { document.effectiveLook.post }

    /// Lens blur (a camera with an aperture) or ink outlines need the depth world.
    static func needsDepth(_ document: Document) -> Bool {
        let post = document.effectiveLook.post
        if post.outline > 0 { return true }
        guard post.depthOfField else { return false }
        let cameras = document.scene.objects.values.filter { $0.kind == .camera }
        return cameras.contains { ($0[.aperture]?.floatValue ?? 0) > 0 }
            || document.scene.timeline.tracks.contains { $0.property == .aperture && $0.keyframes.contains { ($0.value.floatValue ?? 0) > 0 } }
    }

    /// Anything beyond the plain render (post, overlays, captions, effects, transitions)?
    var compositing: Bool {
        !post.isNeutral || depthWorld != nil || !timeline.effects.isEmpty || timeline.cuts.contains { ($0.transition?.kind ?? .cut) != .cut }
            || document.scene.objects.values.contains { $0.kind.isOverlay } || burnsCaptions || FrameLook.mayGlow(document)
    }

    private var burnsCaptions: Bool {
        guard let captions = timeline.captions else { return false }
        return captions.enabled && captions.burnIn && !timeline.transcripts.isEmpty
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

    /// Where a specific camera looks from (the transition's other shot).
    public static func camera(_ id: ObjectID?, in animated: AnimatedScene, fallback: Viewpoint, aspect: Double) -> OffscreenRenderer.Camera {
        var copy = animated
        copy.camera = id
        return camera(for: copy, fallback: fallback, aspect: aspect)
    }

    /// Where each framing looks from at `time` (the cut camera, else the scene's saved view).
    public static func camera(for animated: AnimatedScene, fallback: Viewpoint, aspect: Double) -> OffscreenRenderer.Camera {
        if let id = animated.camera, let object = animated.scene.objects[id] {
            let world = animated.scene.worldTransform(of: id)
            let framing = CameraLens(object).framing(aspect: aspect)
            let rotation = (world.rotation * Quat(angle: framing.yaw, axis: .unitY)).normalized
            return OffscreenRenderer.Camera(position: world.position.simd, orientation: rotation.simd, fieldOfView: Float(framing.fieldOfView))
        }
        let pose = StageView.cameraPose(for: fallback)
        return OffscreenRenderer.Camera(position: pose.eye.simd, orientation: pose.rotation.simd, fieldOfView: Float(pose.fieldOfView))
    }

    /// Loads the exact video frames and pictures the cards show at `time` (never the nearest one), then shows the scene.
    func prepareFrame(at time: Double, rigs: [AssetID: RigAsset], first: Bool) async -> AnimatedScene {
        var frames: [String: CGImage] = [:]
        for object in document.scene.objects.values {
            guard case let .card(recipe) = object.kind, let key = recipe.frameKey(at: time) else { continue }
            if recipe.video != nil, let (file, _) = VideoFrameKey.parse(key) {
                if let url = mediaURL(file), let image = await videoFrames.frame(key, url: url) { frames[key] = image }
            } else if let image = overlayImage(key) {
                frames[key] = image
            }
        }
        cardFrames = frames
        return prepare(at: time, rigs: rigs, first: first)
    }

    /// Shows the scene at `time` in the export world.
    func prepare(at time: Double, rigs: [AssetID: RigAsset], first: Bool) -> AnimatedScene {
        let animated = Animator.evaluate(document, at: time, rigs: rigs)
        let evaluated = Document(project: document.project, scene: animated.scene)
        if first {
            world.load(evaluated)
        } else {
            world.sync(evaluated, changes: ChangeSet(objects: animated.animated.union(previousAnimated)))
        }
        world.applyPoses(animated.poses, rigs: rigs)
        world.applyClipFallback(document.scene.timeline, at: time, skipping: Set(animated.poses.keys))
        world.applyParticles(animated.scene, timeline: timeline, time: time)
        world.applyCards(animated.scene, time: time)
        if let depthWorld {
            if first {
                depthWorld.load(evaluated)
            } else {
                depthWorld.sync(evaluated, changes: ChangeSet(objects: animated.animated.union(previousAnimated)))
            }
            depthWorld.applyPoses(animated.poses, rigs: rigs)
        }
        previousAnimated = animated.animated
        return animated
    }

    // MARK: One frame

    /// Renders one framing of one frame into `target` — the shot, then (when the look asks for it) post-processing,
    /// the transition's other shot, screen effects, film look, overlays and captions. The result is left in
    /// `target` (its pixels, or `target.matte` when composited).
    func renderFrame(_ animated: AnimatedScene, framing: Framing, target: RenderTarget, session: RenderSession, frame: Int,
                     deltaTime: Double) async throws {
        let time = animated.time
        let aspect = framing.aspect
        let viewpoint = document.scene.viewpoint
        let transition = compositing ? timeline.transition(at: time, fallback: document.scene.activeCamera) : nil
        let mainID = transition?.to ?? animated.camera
        let mainCamera = Self.camera(mainID, in: animated, fallback: viewpoint, aspect: aspect)
        try await session.render(camera: mainCamera, target: target, world: world, deltaTime: deltaTime)
        guard compositing else { return }
        let look = FrameLook(post: post, lens: lens(mainID, in: animated), screen: ScreenEffects.state(at: time, effects: timeline.effects, fps: timeline.fps),
                             frame: frame, glow: FrameLook.glow(in: animated.scene))
        var picture = try await shot(target: target, camera: mainCamera, look: look, session: session)
        if let transition {
            let key = "\(target.width)x\(target.height)"
            let other = try secondTargets[key] ?? session.target(width: target.width, height: target.height)
            secondTargets[key] = other
            let fromCamera = Self.camera(transition.from, in: animated, fallback: viewpoint, aspect: aspect)
            try await session.render(camera: fromCamera, target: other, world: world, deltaTime: 0)
            var fromLook = look
            fromLook.lens = lens(transition.from, in: animated)
            let from = try await shot(target: other, camera: fromCamera, look: fromLook, session: session)
            picture = compositor.transition(from: from, to: picture, kind: transition.kind, progress: transition.progress)
        }
        let size = CGSize(width: target.width, height: target.height)
        let frames = await videoFrames(for: animated, framing: framing, size: size)
        let overlays = overlayLayer(animated, camera: mainCamera, framing: framing, size: size, videoFrames: frames)
        picture = compositor.finish(picture, look: look, overlays: overlays)
        target.matte = compositor.bytes(picture, width: target.width, height: target.height)
    }

    private func lens(_ id: ObjectID?, in animated: AnimatedScene) -> CameraLens? {
        id.flatMap { animated.scene.objects[$0] }.map(CameraLens.init)
    }

    /// The rendered pixels of `target` (+ its depth when needed) post-processed as a shot.
    private func shot(target: RenderTarget, camera: OffscreenRenderer.Camera, look: FrameLook, session _: RenderSession) async throws -> CIImage {
        let bytes = target.matte ?? target.bytes()
        let image = compositor.image(bytes: bytes, width: target.width, height: target.height)
        var depth: CIImage?
        if let depthWorld, look.post.outline > 0 || (look.post.depthOfField && (look.lens?.aperture ?? 0) > 0) {
            depth = try await depthImage(camera: camera, width: target.width, height: target.height, world: depthWorld)
        }
        return compositor.shot(image, depth: depth, look: look)
    }

    /// Renders the depth world (half resolution) and returns v = 0.5 / distance as a linear grey image.
    private func depthImage(camera: OffscreenRenderer.Camera, width: Int, height: Int, world depthWorld: SceneRenderer) async throws -> CIImage {
        guard let device else { throw OffscreenError.noMetal }
        if depthSession == nil {
            depthSession = try RenderSession(device: device, world: depthWorld, background: .black)
            depthSession?.renderer.lighting.resource = nil
        }
        guard let depthSession else { throw OffscreenError.noMetal }
        if depthTable == nil {
            depthTable = try await DepthCalibration.table(session: depthSession, world: depthWorld)
        }
        let w = max(width / 2, 1)
        let h = max(height / 2, 1)
        let key = "\(w)x\(h)"
        let target = try depthTargets[key] ?? depthSession.target(width: w, height: h)
        depthTargets[key] = target
        try await depthSession.render(camera: camera, target: target, world: depthWorld, deltaTime: 0)
        var bytes = target.bytes()
        // Stored bytes → the true v, through the calibration table.
        let table = depthTable ?? Self.srgbToLinear
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let v = table[Int(bytes[index + 2])]
            bytes[index] = v
            bytes[index + 1] = v
            bytes[index + 2] = v
            bytes[index + 3] = 255
        }
        return CIImage(bitmapData: Data(bytes), bytesPerRow: w * 4, size: CGSize(width: w, height: h), format: .BGRA8, colorSpace: nil)
    }

    static let srgbToLinear: [UInt8] = (0 ..< 256).map { index -> UInt8 in
        let c = Double(index) / 255
        let linear = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        return UInt8((linear * 255).rounded())
    }

    /// The exact frame of every video overlay showing at this time.
    private func videoFrames(for animated: AnimatedScene, framing _: Framing, size: CGSize) async -> [String: CGImage] {
        guard animated.scene.objects.values.contains(where: {
            if case let .overlay(recipe) = $0.kind {
                recipe.video != nil
            } else { false }
        })
        else { return [:] }
        var frames: [String: CGImage] = [:]
        let placements = OverlayLayout.placements(in: animated.scene, palette: document.palette, width: Double(size.width),
                                                  height: Double(size.height), time: animated.time)
        for placement in placements {
            guard let key = placement.recipe.image, let (file, _) = VideoFrameKey.parse(key), let url = mediaURL(file) else { continue }
            if let image = await videoFrames.frame(key, url: url) { frames[key] = image }
        }
        return frames
    }

    /// Overlays and captions for this frame, drawn at the frame's size.
    private func overlayLayer(_ animated: AnimatedScene, camera: OffscreenRenderer.Camera, framing: Framing, size: CGSize,
                              videoFrames: [String: CGImage] = [:]) -> CIImage? {
        let cameraTransform = LoweyCore.Transform(position: Vec3(camera.position), rotation: Quat(camera.orientation))
        let placements = OverlayLayout.placements(in: animated.scene, palette: document.palette, width: Double(size.width),
                                                  height: Double(size.height), time: animated.time) { point in
            OverlayLayout.project(point, camera: cameraTransform, fieldOfView: Double(camera.fieldOfView), aspect: framing.aspect)
        }
        let caption = burnsCaptions ? Captions.page(at: animated.time, in: pages(for: framing)) : nil
        guard !placements.isEmpty || caption != nil else { return nil }
        let stills = overlayImage
        let images: (String) -> CGImage? = { name in videoFrames[name] ?? stills(name) }
        return compositor.overlayImage(size: size) { context in
            OverlayRenderer.draw(placements, in: context, size: size, image: images)
            if let caption, let settings = timeline.captions {
                OverlayRenderer.drawCaption(caption.page, activeWord: caption.word, settings: settings, in: context, size: size)
            }
        }
    }

    /// Renders one frame of every framing at `time` as images (single frames, tests).
    public func images(at time: Double, framings: [Framing], longSide: Int, transparent: Bool = false) async throws -> [CGImage] {
        let session = try await makeSession(transparent: transparent)
        let rigs = rigCache.rigs(for: document, library: world.library)
        let animated = await prepareFrame(at: time, rigs: rigs, first: true)
        await world.waitForAssets()
        await depthWorld?.waitForAssets()
        _ = await prepareFrame(at: time, rigs: rigs, first: false)
        var result: [CGImage] = []
        let frame = timeline.frame(for: time)
        for framing in framings {
            let size = framing.pixelSize(longSide: longSide)
            let target = try session.target(width: size.width, height: size.height)
            // Warm-up renders let textures and lighting settle; export frames get the same treatment once.
            for _ in 0 ..< 3 {
                try await renderFrame(animated, framing: framing, target: target, session: session, frame: frame, deltaTime: 1 / 30)
            }
            try result.append(target.image(transparent: transparent))
        }
        return result
    }

    /// Exports every framing. Returns the files (or folders for PNG sequences) written.
    public func export(
        settings: VideoExportSettings, to folder: URL, baseName: String, progress: @escaping (Double) -> Void
    ) async throws -> [URL] {
        guard !settings.framings.isEmpty else { throw ExportError.nothingToExport }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let session = try await makeSession(transparent: settings.transparent)
        session.canRender = canRender
        let rigs = rigCache.rigs(for: document, library: world.library)
        _ = await prepareFrame(at: settings.range.start, rigs: rigs, first: true)
        await world.waitForAssets()
        await depthWorld?.waitForAssets()

        var outputs: [Output] = []
        for framing in settings.framings {
            let size = framing.pixelSize(longSide: settings.longSide)
            let name = "\(baseName) \(framing.rawValue.replacingOccurrences(of: ":", with: "x"))"
            let target = try session.target(width: size.width, height: size.height)
            switch settings.format {
            case .video:
                let ext = settings.transparent ? "mov" : "mp4"
                let url = folder.appendingPathComponent(name).appendingPathExtension(ext)
                try? FileManager.default.removeItem(at: url)
                let writer = try VideoWriter(url: url, width: size.width, height: size.height, fps: settings.fps, codec: settings.codec,
                                             alpha: settings.transparent, audio: settings.audio, audioSampleRate: settings.audioSampleRate)
                outputs.append(Output(framing: framing, target: target, url: url, writer: writer))
            case .pngSequence:
                let url = folder.appendingPathComponent(name, isDirectory: true)
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                if let audio = settings.audio, !audio.isEmpty {
                    try WAV.data(audio, channels: 2, sampleRate: settings.audioSampleRate).write(to: url.appendingPathComponent("soundtrack.wav"))
                }
                outputs.append(Output(framing: framing, target: target, url: url, writer: nil))
            }
        }

        let frames = settings.frameCount
        let step = 1 / Double(max(settings.fps, 1))
        // Settle textures and lighting once before frame 0.
        try await waitUntilRenderable()
        let first = await prepareFrame(at: settings.range.start, rigs: rigs, first: false)
        for output in outputs {
            for _ in 0 ..< 3 {
                try await renderFrame(first, framing: output.framing, target: output.target, session: session, frame: 0, deltaTime: step)
            }
        }
        do {
            for frame in 0 ..< frames {
                try Task.checkCancellation()
                try await waitUntilRenderable()
                let time = settings.range.start + Double(frame) * step
                let animated = await prepareFrame(at: time, rigs: rigs, first: false)
                for output in outputs {
                    try await renderFrame(animated, framing: output.framing, target: output.target, session: session,
                                          frame: timeline.frame(for: time), deltaTime: step)
                    if let writer = output.writer {
                        try await writer.append(output.target, frame: frame)
                    } else {
                        let image = try output.target.image(transparent: settings.transparent)
                        let url = output.url.appendingPathComponent(String(format: "frame_%05d.png", frame + 1))
                        try Self.writePNG(image, to: url)
                    }
                }
                progress(Double(frame + 1) / Double(frames))
                // Let the UI breathe between frames.
                await Task.yield()
            }
        } catch {
            for output in outputs {
                output.writer?.cancel()
            }
            if error is CancellationError { throw ExportError.cancelled }
            throw error
        }
        for output in outputs {
            try await output.writer?.finish()
        }
        return outputs.map(\.url)
    }

    /// Holds the export while the app can't use the GPU (it resumes by itself when the app is back in front).
    private func waitUntilRenderable() async throws {
        guard !canRender() else { return }
        logger.notice("Export waiting: the app is not in front")
        onWaiting(true)
        defer { onWaiting(false) }
        while !canRender() {
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private struct Output {
        var framing: Framing
        var target: RenderTarget
        var url: URL
        var writer: VideoWriter?
    }

    private func makeSession(transparent: Bool) async throws -> RenderSession {
        guard let device else { throw OffscreenError.noMetal }
        world.environment.backdropHidden = transparent
        world.load(document)
        await world.environment.waitForEnvironment()
        let look = document.effectiveLook
        let background = transparent ? UIColor.clear : look.sky.horizon.uiColor
        let session = try RenderSession(device: device, world: world, background: background)
        session.transparent = transparent
        return session
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw OffscreenError.readback
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw OffscreenError.readback }
    }
}

/// Measures how the depth world's stored bytes map to v = 0.5 / distance: a plane is rendered at known distances with the
/// depth material, and the readings become a 256-entry lookup table (exact, whatever the renderer's tone mapping).
@MainActor
enum DepthCalibration {
    static let distances: [Double] = [0.5, 0.55, 0.62, 0.7, 0.8, 0.9, 1, 1.15, 1.3, 1.5, 1.75, 2, 2.4, 3, 3.6, 4.5, 6, 8, 11, 16, 25, 40, 80]

    static func table(session: RenderSession, world: SceneRenderer) async throws -> [UInt8] {
        let target = try session.target(width: 8, height: 8)
        let plane = ModelEntity(mesh: .generatePlane(width: 1, height: 1), materials: [MaterialFactory.shared.depthMaterial])
        let wasEnabled = world.root.isEnabled
        world.root.isEnabled = false
        session.renderer.entities.append(plane)
        defer {
            session.renderer.entities.removeAll { $0 === plane }
            world.root.isEnabled = wasEnabled
        }
        let camera = OffscreenRenderer.Camera(position: .zero, orientation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), fieldOfView: 40)
        var points: [(raw: Double, v: Double)] = [(0, 0)]
        for distance in distances {
            plane.position = SIMD3<Float>(0, 0, Float(-distance))
            plane.scale = SIMD3<Float>(repeating: Float(distance * 2))
            try await session.render(camera: camera, target: target, world: world, deltaTime: 0)
            let bytes = target.bytes()
            let center = (4 * 8 + 4) * 4
            points.append((Double(bytes[center + 2]), min(0.5 / distance, 1)))
        }
        return table(from: points)
    }

    /// Piecewise-linear raw → v (monotonic), as bytes.
    static func table(from points: [(raw: Double, v: Double)]) -> [UInt8] {
        var sorted = points.sorted { $0.raw < $1.raw }
        // Equal readings: keep the average v (8-bit plateaus).
        var merged: [(raw: Double, v: Double)] = []
        for point in sorted {
            if let last = merged.last, last.raw == point.raw {
                merged[merged.count - 1].v = (last.v + point.v) / 2
            } else {
                merged.append(point)
            }
        }
        sorted = merged
        return (0 ..< 256).map { index -> UInt8 in
            let raw = Double(index)
            guard let upper = sorted.firstIndex(where: { $0.raw >= raw }) else { return UInt8((sorted.last?.v ?? 1) * 255) }
            guard upper > 0 else { return UInt8((sorted[0].v * 255).rounded()) }
            let a = sorted[upper - 1]
            let b = sorted[upper]
            let t = b.raw > a.raw ? (raw - a.raw) / (b.raw - a.raw) : 0
            return UInt8((min(max(a.v + (b.v - a.v) * t, 0), 1) * 255).rounded())
        }
    }
}

/// One persistent `RealityRenderer` for a whole export (creating one per frame is far too slow).
@MainActor
final class RenderSession {
    let device: MTLDevice
    let renderer: RealityRenderer
    let camera = Entity()

    init(device: MTLDevice, world: SceneRenderer, background: UIColor) throws {
        self.device = device
        renderer = try RealityRenderer()
        renderer.entities.append(world.root)
        camera.components.set(PerspectiveCameraComponent(near: 0.02, far: 60000, fieldOfViewInDegrees: 50))
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        if let environment = world.environment.environment {
            renderer.lighting.resource = environment
            renderer.lighting.intensityExponent = world.environment.ambientExponent
        }
        renderer.cameraSettings.colorBackground = .color(background.cgColor)
        renderer.cameraSettings.antialiasing = .multisample4X
    }

    func target(width: Int, height: Int) throws -> RenderTarget {
        try RenderTarget(device: device, width: width, height: height)
    }

    /// Transparent frames: RealityRenderer always writes opaque pixels, so the frame is rendered over black and
    /// over white; alpha = 1 − (white − black) and the over-black colour is the premultiplied colour.
    var transparent = false
    /// Whether the GPU may be used (false in the background); a stalled frame waits for this before retrying.
    var canRender: @MainActor () -> Bool = { true }
    /// How long one frame may take before it counts as stalled.
    var frameDeadline: Duration = .seconds(15)
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "export")

    func render(camera pose: OffscreenRenderer.Camera, target: RenderTarget, world: SceneRenderer, deltaTime: Double) async throws {
        target.matte = nil
        guard transparent else {
            try await renderOnce(camera: pose, target: target, world: world, deltaTime: deltaTime)
            return
        }
        renderer.cameraSettings.colorBackground = .color(UIColor.white.cgColor)
        try await renderOnce(camera: pose, target: target, world: world, deltaTime: deltaTime)
        let white = target.bytes()
        renderer.cameraSettings.colorBackground = .color(UIColor.black.cgColor)
        try await renderOnce(camera: pose, target: target, world: world, deltaTime: 0)
        var black = target.bytes()
        for index in stride(from: 0, to: black.count - 3, by: 4) {
            let spread = (Int(white[index]) - Int(black[index]) + Int(white[index + 1]) - Int(black[index + 1])
                + Int(white[index + 2]) - Int(black[index + 2])) / 3
            black[index + 3] = UInt8(clamping: 255 - max(spread, 0))
        }
        target.matte = black
    }

    private func renderOnce(camera pose: OffscreenRenderer.Camera, target: RenderTarget, world: SceneRenderer, deltaTime: Double) async throws {
        camera.components.set(PerspectiveCameraComponent(near: 0.02, far: 60000, fieldOfViewInDegrees: pose.fieldOfView))
        camera.position = pose.position
        camera.orientation = pose.orientation
        world.environment.follow(camera: Vec3(pose.position))
        var attempts = 0
        while true {
            do {
                try await renderWithDeadline(target: target, deltaTime: attempts == 0 ? deltaTime : 0)
                return
            } catch RenderStall.timedOut {
                attempts += 1
                logger.error("A frame did not finish in time (attempt \(attempts))")
                if attempts >= 3 {
                    throw ExportError.writer("the renderer stopped responding. Keep 3D-lowey in front while it exports")
                }
                // Usually the app went to the background mid-frame: wait until it's back, then render again.
                while !canRender() {
                    try await Task.sleep(for: .milliseconds(250))
                }
            }
        }
    }

    /// One `updateAndRender`, resumed by its completion or by the deadline, whichever comes first (never both).
    private func renderWithDeadline(target: RenderTarget, deltaTime: Double) async throws {
        let gate = ResumeGate()
        let deadline = frameDeadline
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let watchdog = Task {
                try? await Task.sleep(for: deadline)
                if !Task.isCancelled, gate.claim() { continuation.resume(throwing: RenderStall.timedOut) }
            }
            do {
                try renderer.updateAndRender(
                    deltaTime: deltaTime, cameraOutput: target.output, whenScheduled: nil,
                    onComplete: { _ in
                        watchdog.cancel()
                        if gate.claim() { continuation.resume() }
                    }, actionsBeforeRender: [], actionsAfterRender: []
                )
            } catch {
                watchdog.cancel()
                if gate.claim() { continuation.resume(throwing: error) }
            }
        }
    }
}

enum RenderStall: Error {
    case timedOut
}

/// Lets exactly one of several racing callbacks resume a continuation.
final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// True for the first caller only.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// A colour texture plus its RealityRenderer output.
@MainActor
final class RenderTarget {
    let texture: MTLTexture
    let output: RealityRenderer.CameraOutput
    let width: Int
    let height: Int
    /// BGRA that overrides the texture: the transparent matte (premultiplied) or the composited frame.
    var matte: [UInt8]?

    init(device: MTLDevice, width: Int, height: Int) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw OffscreenError.textureCreation }
        self.texture = texture
        output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        self.width = width
        self.height = height
    }

    func bytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return bytes
    }

    func copy(into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        if let matte {
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            matte.withUnsafeBytes { source in
                for row in 0 ..< height {
                    memcpy(base + row * rowBytes, source.baseAddress! + row * width * 4, width * 4)
                }
            }
            return
        }
        texture.getBytes(base, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    }

    func image(transparent: Bool) throws -> CGImage {
        let bytesPerRow = width * 4
        let bytes = matte ?? bytes()
        let alpha: CGImageAlphaInfo = transparent ? .premultipliedFirst : .noneSkipFirst
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | alpha.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { throw OffscreenError.readback }
        return image
    }
}

/// AVAssetWriter wrapper: frames in order at a fixed rate.
@MainActor
final class VideoWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let fps: Int
    private let audioInput: AVAssetWriterInput?
    private let audio: [Float]
    private let audioRate: Int
    private var audioWritten = 0
    private let audioFormat: CMAudioFormatDescription?

    init(url: URL, width: Int, height: Int, fps: Int, codec: VideoCodec, alpha: Bool, audio: [Float]? = nil, audioSampleRate: Int = 48000) throws {
        let type: AVFileType = alpha ? .mov : .mp4
        writer = try AVAssetWriter(outputURL: url, fileType: type)
        let codecType: AVVideoCodecType = alpha ? .hevcWithAlpha : (codec == .hevc ? .hevc : .h264)
        let bitsPerPixel = codec == .hevc || alpha ? 0.08 : 0.12
        let bitrate = Int(Double(width * height * fps) * bitsPerPixel)
        let settings: [String: Any] = [
            AVVideoCodecKey: codecType,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2
            ]
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(input) else { throw ExportError.writer("can't add the video track") }
        writer.add(input)
        self.audio = audio ?? []
        audioRate = audioSampleRate
        if let audio, !audio.isEmpty {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: audioSampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            audioInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(audioInput) else { throw ExportError.writer("can't add the sound track") }
            writer.add(audioInput)
            self.audioInput = audioInput
            var description = AudioStreamBasicDescription(
                mSampleRate: Float64(audioSampleRate), mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
                mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
            )
            var format: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
                                           magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
            audioFormat = format
        } else {
            audioInput = nil
            audioFormat = nil
        }
        guard writer.startWriting() else { throw ExportError.writer(writer.error?.localizedDescription ?? "couldn't start") }
        writer.startSession(atSourceTime: .zero)
        self.fps = fps
    }

    func append(_ target: RenderTarget, frame: Int) async throws {
        var waited = 0
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(4))
            waited += 1
            if waited > 5000 { throw ExportError.writer("the encoder stopped accepting frames") }
        }
        guard let pool = adaptor.pixelBufferPool else { throw ExportError.writer(writer.error?.localizedDescription ?? "no buffer pool") }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw ExportError.writer("no pixel buffer") }
        target.copy(into: buffer)
        let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw ExportError.writer(writer.error?.localizedDescription ?? "couldn't append frame \(frame)")
        }
        // Keep the sound interleaved with the picture: write audio up to the end of this frame.
        try await appendAudio(upTo: Int((Double(frame + 1) / Double(fps) * Double(audioRate)).rounded()))
    }

    private func appendAudio(upTo frameLimit: Int) async throws {
        guard let audioInput, let audioFormat else { return }
        let totalFrames = audio.count / 2
        let limit = min(frameLimit, totalFrames)
        while audioWritten < limit {
            var waited = 0
            while !audioInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(4))
                waited += 1
                if waited > 5000 { throw ExportError.writer("the audio encoder stopped accepting samples") }
            }
            let count = min(limit - audioWritten, 4096)
            let bytes = count * 8
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes, blockAllocator: kCFAllocatorDefault,
                                               customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
            guard let block else { throw ExportError.writer("no audio buffer") }
            audio.withUnsafeBufferPointer { samples in
                _ = CMBlockBufferReplaceDataBytes(with: samples.baseAddress! + audioWritten * 2, blockBuffer: block, offsetIntoDestination: 0,
                                                  dataLength: bytes)
            }
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: audioFormat, sampleCount: count,
                presentationTimeStamp: CMTime(value: CMTimeValue(audioWritten), timescale: CMTimeScale(audioRate)),
                packetDescriptions: nil, sampleBufferOut: &sample
            )
            guard let sample, audioInput.append(sample) else {
                throw ExportError.writer(writer.error?.localizedDescription ?? "couldn't append sound")
            }
            audioWritten += count
        }
    }

    func finish() async throws {
        try await appendAudio(upTo: audio.count / 2)
        audioInput?.markAsFinished()
        input.markAsFinished()
        let writer = writer
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status != .completed {
            throw ExportError.writer(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }
    }

    func cancel() {
        writer.cancelWriting()
    }
}
