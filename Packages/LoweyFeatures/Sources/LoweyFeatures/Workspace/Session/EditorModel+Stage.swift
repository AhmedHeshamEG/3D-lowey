import CoreGraphics
import Foundation
import HmmDiagnostics
import LoweyCore
import LoweyEngine
import UIKit

/// The stage: what it draws every frame (the same request the export builds, plus the editor layer), the Director
/// view's shot camera, the selection and gizmo, the drawing guide, and where new things land.
extension EditorModel {
    /// Called by the stage host once the Metal view exists.
    func attach(_ stage: StageView) {
        self.stage = stage
        stage.setViewpoint(baseScene.viewpoint, notify: false)
        projection = baseScene.viewpoint.projection
        viewYaw = baseScene.viewpoint.yaw
        stage.showsGrid = showsGrid
        stage.gizmoMode = gizmoMode
        stage.dynamicScale.enabled = !UserDefaults.standard.bool(forKey: AppSettings.fullResolutionStage)
        stage.onCameraChanged = { [weak self] viewpoint in self?.cameraMoved(viewpoint) }
        stage.onFrameTime = { [weak self] gpu, total, scale in
            self?.performance.record(gpu: gpu, total: total, scale: scale)
        }
        stage.frameSource = { [weak self] stage in self?.stageFrame(for: stage) }
        refreshGuide()
        refreshSelectionOverlay()
        stage.redraw()
    }

    /// The frame the stage draws now.
    func stageFrame(for stage: StageView) -> StageFrame? {
        let director = directorShot(in: stage.bounds.size)
        let input = RenderInput(document: displayDocument, time: time, poses: displayed.poses, selection: director == nil ? Set(selection) : [],
                                hidden: director?.id, showsHelpers: director == nil, mediaImage: { [weak self] key in self?.mediaImage(key) },
                                catalog: library.catalog, lightBudget: 16)
        var request = FrameRequest(input: input, camera: stage.camera, frameIndex: timeline.frame(for: time))
        if let director {
            request.lens = displayed.scene.objects[director.id].map(CameraLens.init)
            request.screen = ScreenEffects.state(at: time, effects: timeline.effects, fps: timeline.fps)
            request.guides = FramingGuides(aspect: deliveryFraming.aspect, thirds: showsThirds, safeAreas: showsSafeAreas)
        }
        let overlay = stageOverlay(for: stage, director: director != nil)
        request.overlay = overlay.image
        request.flipbookLayers = overlay.layers
        if director != nil {
            var editor = stage.editorScene(showsSelection: false)
            editor.showsGrid = false
            editor.gizmo = nil
            request.editor = editor
        }
        return StageFrame(request: request, shotCamera: director?.camera)
    }

    /// The camera the shot is seen through at the playhead (cuts, else the active camera).
    var shotCamera: ObjectID? { displayed.camera }

    /// The Director view's camera, widened so the delivery frame (centred, as large as fits) shows exactly the shot.
    func directorShot(in size: CGSize) -> (id: ObjectID, camera: RenderCamera)? {
        guard directorView, let id = shotCamera, displayed.scene.objects[id] != nil, size.width > 1, size.height > 1 else { return nil }
        let frameAspect = deliveryFraming.aspect
        var camera = RenderCamera.shot(id, in: displayed.scene, fallback: baseScene.viewpoint, aspect: frameAspect)
        let viewAspect = Double(size.width / size.height)
        if frameAspect > viewAspect {
            let half = atan(tan(Double(camera.fieldOfView) * .pi / 360) * frameAspect / viewAspect)
            camera.fieldOfView = Float(min(half * 360 / .pi, 170))
        }
        return (id, camera)
    }

    /// Where the delivered frame sits on the stage (points): the Director view's frame, else the whole stage.
    var frameRect: CGRect {
        guard let stage else { return .zero }
        let size = stage.bounds.size
        guard directorView, shotCamera != nil else { return CGRect(origin: .zero, size: size) }
        return DirectorFrame.rect(in: size, aspect: deliveryFraming.aspect)
    }

    // MARK: Selection & guide

    var selectedObjects: [SceneObject] { selection.compactMap { scene.objects[$0] } }
    var singleSelection: SceneObject? { selection.count == 1 ? scene.objects[selection[0]] : nil }

    /// Visual bounds of the selection (what the renderer drew, models included).
    var selectionBounds: Bounds? {
        stage?.visualBounds(of: selection) ?? operations.bounds.worldBounds(of: selection, in: scene)
    }

    var selectionPivot: Vec3? {
        guard let bounds = selectionBounds else { return nil }
        return Vec3(bounds.center.x, bounds.min.y, bounds.center.z)
    }

    /// What the selection turns around: one object around its own origin, several around the middle of their origins.
    var rotationPivot: Vec3? {
        let roots = selection.filter { id in !scene.ancestors(of: id).contains { selection.contains($0) } }
        guard !roots.isEmpty else { return nil }
        let sum = roots.reduce(Vec3.zero) { $0 + scene.worldTransform(of: $1).position }
        return sum * (1 / Double(roots.count))
    }

    /// Whether anything that moves the selection is animated (it, a parent or a part).
    func selectionMoves(_ animated: Set<ObjectID>) -> Bool {
        guard !selection.isEmpty, !animated.isEmpty else { return false }
        return selection.contains { id in
            animated.contains(id) || scene.ancestors(of: id).contains(where: animated.contains) || scene.subtree(of: id).contains(where: animated.contains)
        }
    }

    func refreshSelectionOverlay() {
        guard let stage else { return }
        let showGizmo = tool == .select && !selection.isEmpty && performPhase == .idle && !directorView
            && !selection.contains(where: { scene.isEffectivelyLocked($0) }) && selectedOverlay == nil
        let pivot = gizmoMode == .rotate ? rotationPivot : selectionPivot
        stage.showSelection(pivot: pivot, gizmoVisible: showGizmo)
    }

    func refreshGuide() {
        stage?.showGuide(currentGuide)
    }

    func toolChanged() {
        lassoPoints = []
        scatterPreview = nil
        if tool == .scatter, selection.isEmpty { app.show("Select what to scatter first (a tree, a rock…), then drag an area") }
        if tool == .shadowBrush { app.show("Paint on an object with the Pencil: shadows follow your strokes") }
        if tool != .ink { inkStrokes = [] }
        if tool == .flipbook, flipbook.track == nil { flipbook.track = timeline.flipbooks.last?.id }
        refreshSelectionOverlay()
        refreshGuide()
    }

    // MARK: Camera

    func cameraMoved(_ viewpoint: Viewpoint) {
        if projection != viewpoint.projection { projection = viewpoint.projection }
        if abs(viewYaw - viewpoint.yaw) > 1 { viewYaw = viewpoint.yaw }
        if tool.usesGuide { refreshGuide() }
        viewpointSaveTask?.cancel()
        viewpointSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard let self, !Task.isCancelled else { return }
            session.setViewpoint(viewpoint)
            scheduleAutosave()
        }
    }

    func frameSelection() {
        stage?.frame(selection.isEmpty ? allBounds : selectionBounds)
    }

    var allBounds: Bounds? { stage?.visualBounds(of: baseScene.roots) ?? operations.bounds.worldBounds(of: baseScene.roots, in: scene) }

    func toggleProjection() {
        guard let stage else { return }
        var viewpoint = stage.viewpoint
        viewpoint.projection = viewpoint.projection == .orthographic ? .perspective : .orthographic
        stage.setViewpoint(viewpoint)
    }

    /// Where new things appear: the surface in the middle of the view (or under a point), else the ground.
    func dropPoint(at screenPoint: CGPoint? = nil) -> Vec3 {
        guard let stage else { return .zero }
        let point = screenPoint ?? CGPoint(x: stage.bounds.midX, y: stage.bounds.midY)
        if let (_, hit) = stage.pickObject(at: point), hit.normal.y > 0.6 {
            return snap.grid ? Snapping.snapToGrid(hit.point, size: snap.gridSize) : hit.point
        }
        let target = stage.viewpoint.target
        let ground = stage.groundPoint(at: point) ?? baseScene.viewpoint.target
        let clamped = ground.distance(to: target) > 60 ? Vec3(target.x, 0, target.z) : ground
        return snap.grid ? Snapping.snapToGrid(clamped, size: snap.gridSize) : clamped
    }

    /// Continuous drawing while something moves by itself (playback, a performance, face or iPad camera).
    func updateStageClock() {
        stage?.isContinuous = isPlaying || performPhase != .idle || faceActive || virtualCameraActive
    }

    // MARK: Pictures in the shot

    /// Card pictures, overlay images and video frames (the stage never waits for a video frame).
    func mediaImage(_ key: String) -> CGImage? {
        if let (file, _) = VideoFrameKey.parse(key) {
            guard let url = mediaURL(file) else { return nil }
            return videoPreview.frameNow(key, url: url)
        }
        if let cached = mediaImages[key] { return cached }
        guard let url = mediaURL(key), let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        mediaImages[key] = image
        return image
    }

    /// Titles, labels and captions over the stage, drawn into the frame they'll be delivered in.
    private func stageOverlay(for stage: StageView, director: Bool) -> StageOverlayCache.Entry {
        let rect = frameRect
        let scale = stage.contentScaleFactor
        let pixels = CGSize(width: stage.bounds.width * scale, height: stage.bounds.height * scale)
        let key = StageOverlayCache.Key(revision: session.revision, frame: timeline.frame(for: time), size: pixels, rect: rect,
                                        director: director, viewpoint: director ? nil : stage.viewpoint)
        if let cached = overlayCache.entry(for: key) { return cached }
        let camera = director ? directorShot(in: stage.bounds.size)?.camera : nil
        let pose = camera.map { CoreTransform(position: Vec3($0.position), rotation: Quat($0.orientation)) }
            ?? CoreTransform(position: Vec3(stage.camera.position), rotation: Quat(stage.camera.orientation))
        let fieldOfView = Double(camera?.fieldOfView ?? stage.camera.fieldOfView)
        let aspect = Double(rect.width / max(rect.height, 1))
        let placements = OverlayLayout.placements(in: displayed.scene, palette: document.palette, width: Double(rect.width), height: Double(rect.height),
                                                  time: time) { point in
            OverlayLayout.project(point, camera: pose, fieldOfView: fieldOfView, aspect: aspect)
        }
        let caption = director ? currentCaption(for: rect) : nil
        let flipbooks = stageFlipbookLayout().map { $0.layout.draws(timeline, scene: displayed.scene, palette: document.palette, at: time) } ?? []
        let image = OverlayCanvas.draw(placements, caption: caption, flipbooks: flipbooks.filter { $0.blend == .normal }, rect: rect, pixels: pixels,
                                       scale: scale) { [weak self] in self?.mediaImage($0) }
        let layers = FlipbookPainter.layers(flipbooks, pixels: pixels) { OverlayCanvas.prepare($0, rect: rect, pixels: pixels, scale: scale) }
        let entry = StageOverlayCache.Entry(image: image, layers: layers)
        overlayCache.store(entry, for: key)
        return entry
    }

    /// The caption page shown at the playhead (burnt-in captions, Director view only).
    private func currentCaption(for rect: CGRect) -> (page: CaptionPage, word: Int?, settings: CaptionSettings)? {
        guard let settings = timeline.captions, settings.enabled, !timeline.transcripts.isEmpty else { return nil }
        let factor = rect.width < rect.height ? 0.6 : 1
        let pages = Captions.pages(words, maxCharacters: max(Int(Double(settings.maxCharacters) * factor), 8), maxLines: settings.maxLines)
        return Captions.page(at: time, in: pages).map { ($0.page, $0.word, settings) }
    }
}

/// The delivery frame inside the stage: as large as fits, centred (the renderer masks outside it the same way).
enum DirectorFrame {
    static func rect(in size: CGSize, aspect: Double) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let view = Double(size.width / size.height)
        if aspect > view {
            let height = size.width / CGFloat(aspect)
            return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        }
        let width = size.height * CGFloat(aspect)
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
    }
}

/// Draws overlays (and a caption) into a stage-sized transparent image.
enum OverlayCanvas {
    @MainActor
    static func draw(_ placements: [OverlayPlacement], caption: (page: CaptionPage, word: Int?, settings: CaptionSettings)?,
                     flipbooks: [FlipbookDraw], rect: CGRect, pixels: CGSize, scale: CGFloat, image: (String) -> CGImage?) -> CGImage? {
        guard !placements.isEmpty || caption != nil || !flipbooks.isEmpty, pixels.width >= 1, pixels.height >= 1,
              let context = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        prepare(context, rect: rect, pixels: pixels, scale: scale)
        FlipbookPainter.draw(flipbooks, in: context)
        OverlayRenderer.draw(placements, in: context, size: rect.size, image: image)
        if let caption {
            OverlayRenderer.drawCaption(caption.page, activeWord: caption.word, settings: caption.settings, in: context, size: rect.size)
        }
        return context.makeImage()
    }

    /// Top-left origin, points, the delivery frame's corner at the origin.
    static func prepare(_ context: CGContext, rect: CGRect, pixels: CGSize, scale: CGFloat) {
        context.translateBy(x: 0, y: pixels.height)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: rect.minX, y: rect.minY)
    }
}

/// The last overlay image (and flipbook layers), kept while nothing that changes them changes.
struct StageOverlayCache {
    struct Entry {
        var image: CGImage?
        var layers: [FlipbookBlend: CGImage]
    }

    struct Key: Equatable {
        var revision: Int
        var frame: Int
        var size: CGSize
        var rect: CGRect
        var director: Bool
        var viewpoint: Viewpoint?
    }

    private var key: Key?
    private var cached: Entry?

    func entry(for key: Key) -> Entry? {
        self.key == key ? cached : nil
    }

    mutating func store(_ entry: Entry, for key: Key) {
        self.key = key
        cached = entry
    }
}
