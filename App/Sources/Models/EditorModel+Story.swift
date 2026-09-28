import Foundation
import LoweyCore
import LoweyRender
import SwiftUI
import UIKit

/// Text & overlays, particles, screen effects, transitions, captions and post-processing (Phase 3).
extension EditorModel {
    // MARK: Adding

    /// 3D text standing in the world where you're looking.
    func addText3D(_ text: String = "ENIGMA", style: TextRecipe.Style = .blocky) {
        refreshOperationsLibrary()
        var object = SceneObject(id: .make(), name: ObjectFactory.uniqueName("Text", in: scene), kind: .text(TextRecipe(text: text, style: style)))
        object[.color] = .color(currentColor)
        object = operations.placeOnGround(object, at: dropPoint())
        object = operations.nudgedToFreeSpot(object, in: scene)
        if perform(operations.add(object)) { select(object.id) }
    }

    /// A 2D overlay in the middle of the frame (titles near the top, the X and ? in the centre).
    func addOverlay(_ shape: OverlayRecipe.Shape, text: String? = nil) {
        var recipe = OverlayRecipe.default(shape)
        if let text { recipe.text = text }
        let y: Double = switch shape {
        case .title: 0.55
        case .label: -0.45
        default: 0
        }
        let layer = Double(baseScene.objects.values.filter(\.kind.isOverlay).count)
        var object = SceneObject(id: .make(), name: ObjectFactory.uniqueName(shape.title, in: scene), kind: .overlay(recipe),
                                 transform: CoreTransform(position: Vec3(0, y, layer)))
        if shape == .cross || shape == .question { object.transform.scale = Vec3(1.6, 1.6, 1) }
        if perform(operations.add(object)) {
            select(object.id)
            app.show(mode == .camera ? "Drag it in the frame; pinch to size it" : "Overlays show in the frame — Camera mode frames them like the export")
        }
    }

    /// A label that follows the selected object around the shot.
    func addLabel(following target: ObjectID) {
        guard let object = scene.objects[target] else { return }
        let recipe = OverlayRecipe(shape: .label, text: object.name, anchor: target)
        let label = SceneObject(id: .make(), name: "\(object.name) label", kind: .overlay(recipe), transform: CoreTransform(position: Vec3(0, 0.12, 50)))
        if perform(operations.add(label)) { select(label.id) }
    }

    func addParticles(_ preset: ParticleRecipe.Preset) {
        refreshOperationsLibrary()
        var recipe = ParticleRecipe.preset(preset, seed: UInt64.random(in: 1 ... 999_999))
        if recipe.burst { recipe.burstTime = time }
        var object = SceneObject(id: .make(), name: ObjectFactory.uniqueName(preset.title, in: scene), kind: .particles(recipe))
        // Rain and snow cover the view from above; everything else sits where you look (or on the selection).
        let anchor = selectionPivot.map { Vec3($0.x, selectionBounds?.max.y ?? $0.y, $0.z) } ?? dropPoint()
        object.transform.position = preset == .rain || preset == .snow ? Vec3(anchor.x, 0, anchor.z) : anchor
        if perform(operations.add(object)) {
            select(object.id)
            if recipe.burst { app.show("\(preset.title) goes off at \(TimelineDrawer.format(time)) — move it in the inspector") }
        }
    }

    // MARK: Editing recipes

    func updateKind(_ id: ObjectID, label: String, _ change: (inout ObjectKind) -> Void) {
        guard let object = baseScene.objects[id] else { return }
        var kind = object.kind
        change(&kind)
        guard kind != object.kind else { return }
        perform(.batch(label, [.setKind(id, kind)]))
    }

    func updateText(_ id: ObjectID, _ change: (inout TextRecipe) -> Void) {
        updateKind(id, label: "Edit text") { kind in
            guard case var .text(recipe) = kind else { return }
            change(&recipe)
            kind = .text(recipe)
        }
    }

    func updateOverlay(_ id: ObjectID, _ change: (inout OverlayRecipe) -> Void) {
        updateKind(id, label: "Edit overlay") { kind in
            guard case var .overlay(recipe) = kind else { return }
            change(&recipe)
            kind = .overlay(recipe)
        }
    }

    func updateParticles(_ id: ObjectID, _ change: (inout ParticleRecipe) -> Void) {
        updateKind(id, label: "Edit effect") { kind in
            guard case var .particles(recipe) = kind else { return }
            change(&recipe)
            kind = .particles(recipe)
        }
    }

    // MARK: Overlays on the stage

    /// Where the export frame is on the stage (points): the framing guide when looking through a camera or
    /// exporting, else the whole view.
    var frameRect: CGRect {
        guard let stage else { return .zero }
        let size = stage.bounds.size
        if mode == .export { return snapshotFraming.guideRect(in: size) }
        if stage.lookThrough != nil { return cameraFraming.guideRect(in: size) }
        return CGRect(origin: .zero, size: size)
    }

    /// Overlays as they appear on the stage (points), for drawing, hit testing and dragging.
    func stageOverlayPlacements() -> [OverlayPlacement] {
        guard let stage, displayed.scene.objects.values.contains(where: \.kind.isOverlay) else { return [] }
        let rect = frameRect
        guard rect.width > 1, rect.height > 1 else { return [] }
        let aspect = Double(rect.width / rect.height)
        let camera: CoreTransform
        let fieldOfView: Double
        if stage.lookThrough != nil || mode == .export {
            let shot = VideoExporter.camera(for: displayed, fallback: scene.viewpoint, aspect: aspect)
            camera = CoreTransform(position: Vec3(shot.position), rotation: Quat(shot.orientation))
            fieldOfView = Double(shot.fieldOfView)
        } else {
            let pose = StageView.cameraPose(for: stage.viewpoint)
            camera = CoreTransform(position: pose.eye, rotation: pose.rotation)
            fieldOfView = pose.fieldOfView
        }
        return OverlayLayout.placements(in: displayed.scene, palette: document.palette, width: Double(rect.width), height: Double(rect.height)) { point in
            OverlayLayout.project(point, camera: camera, fieldOfView: fieldOfView, aspect: aspect)
        }
    }

    /// The top-most overlay under a stage point.
    func overlayHit(at point: CGPoint) -> ObjectID? {
        let rect = frameRect
        let local = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
        for placement in stageOverlayPlacements().reversed() {
            let box = OverlayRenderer.boxSize(placement, frame: rect.size)
            // Undo the overlay's rotation, then test its box (with a comfortable touch margin).
            let dx = Double(local.x) - placement.center.x
            let dy = Double(local.y) - placement.center.y
            let c = cos(placement.angle)
            let s = sin(placement.angle)
            let rx = dx * c - dy * s
            let ry = dx * s + dy * c
            if abs(rx) <= Double(box.width) / 2 + 22, abs(ry) <= Double(box.height) / 2 + 22 { return placement.id }
        }
        return nil
    }

    /// Drag an overlay in the frame (keyed at the playhead when animating).
    func moveOverlay(_ id: ObjectID, by pixels: CGSize, gesture: String) {
        guard let object = scene.objects[id], object.kind.isOverlay else { return }
        let rect = frameRect
        guard rect.width > 0, rect.height > 0 else { return }
        var position = object.transform.position
        position.x += Double(pixels.width / (rect.width / 2))
        position.y -= Double(pixels.height / (rect.height / 2))
        perform(.setProperties([PropertyChange(object: id, key: .position, value: .vec3(position))]), coalesceKey: gesture)
    }

    func scaleOverlay(_ id: ObjectID, by factor: Double, gesture: String) {
        guard let object = scene.objects[id], object.kind.isOverlay else { return }
        var scale = object.transform.scale
        scale.x = min(max(scale.x * factor, 0.05), 40)
        scale.y = min(max(scale.y * factor, 0.05), 40)
        perform(.setProperties([PropertyChange(object: id, key: .scale, value: .vec3(scale))]), coalesceKey: gesture)
    }

    func rotateOverlay(_ id: ObjectID, by radians: Double, gesture: String) {
        guard let object = scene.objects[id], object.kind.isOverlay else { return }
        let rotation = (Quat(angle: radians, axis: .unitZ) * object.transform.rotation).normalized
        perform(.setProperties([PropertyChange(object: id, key: .rotation, value: .quat(rotation))]), coalesceKey: gesture)
    }

    var selectedOverlay: ObjectID? {
        guard let object = singleSelection, object.kind.isOverlay else { return nil }
        return object.id
    }

    // MARK: Screen effects

    func addScreenEffect(_ kind: ScreenEffect.Kind) {
        updateTimeline(kind.title) { timeline in
            timeline.effects.append(ScreenEffect(id: UUID().uuidString.lowercased(), kind: kind, start: time))
        }
        Haptics.success()
    }

    func removeScreenEffect(_ id: String) {
        updateTimeline("Remove effect") { $0.effects.removeAll { $0.id == id } }
    }

    func updateScreenEffect(_ id: String, coalesce: String? = nil, _ change: (inout ScreenEffect) -> Void) {
        guard let index = timeline.effects.firstIndex(where: { $0.id == id }) else { return }
        var copy = timeline
        change(&copy.effects[index])
        guard copy != timeline else { return }
        perform(.batch("Edit effect", [.setTimeline(copy)]), coalesceKey: coalesce)
    }

    // MARK: Transitions & match cut

    /// The cut at (or just before) the playhead.
    var cutAtPlayhead: CameraCut? {
        timeline.cuts.filter { $0.time <= time + 0.5 / Double(max(timeline.fps, 1)) }.max { $0.time < $1.time }
    }

    func setTransition(_ kind: TransitionSpec.Kind, duration: Double = 0.6, forCutAt cutTime: Double) {
        updateTimeline(kind == .cut ? "Straight cut" : kind.title) { timeline in
            guard let index = timeline.cuts.firstIndex(where: { abs($0.time - cutTime) < 1e-6 }) else { return }
            timeline.cuts[index].transition = kind == .cut ? nil : TransitionSpec(kind: kind, duration: duration)
        }
    }

    /// Match cut: aims the camera that takes over at this cut so the selected subject sits exactly where it
    /// was in the previous shot's frame (a key on its rotation at the cut).
    func matchCut() {
        guard let cut = cutAtPlayhead else {
            app.show("Put the playhead on a cut first")
            return
        }
        let cuts = timeline.cuts.sorted { $0.time < $1.time }
        guard let index = cuts.firstIndex(where: { $0.time == cut.time }) else { return }
        let previousCamera = index > 0 ? cuts[index - 1].camera : baseScene.activeCamera
        guard let previousCamera, previousCamera != cut.camera, let subject = selectionSubject else {
            app.show("Select what should line up across the cut")
            return
        }
        let before = Animator.evaluate(session.document, at: max(cut.time - 1 / Double(timeline.fps), 0), rigs: rigs)
        let after = Animator.evaluate(session.document, at: cut.time, rigs: rigs)
        guard let fromObject = before.scene.objects[previousCamera], let toObject = after.scene.objects[cut.camera] else { return }
        let aspect = cameraFraming.aspect
        let fromWorld = before.scene.worldTransform(of: previousCamera)
        let fromLens = CameraLens(fromObject).framing(aspect: aspect)
        guard let spot = OverlayLayout.project(subject, camera: fromWorld, fieldOfView: fromLens.fieldOfView, aspect: aspect) else {
            app.show("The subject isn't in the previous shot")
            return
        }
        let toWorld = after.scene.worldTransform(of: cut.camera)
        let toLens = CameraLens(toObject).framing(aspect: aspect)
        let rotation = MatchCut.aim(cameraAt: toWorld.position, subject: subject, framePoint: spot, fieldOfView: toLens.fieldOfView, aspect: aspect)
        let parentWorld = after.scene.objects[cut.camera]?.parent.map { after.scene.worldTransform(of: $0) } ?? .identity
        let local = (parentWorld.rotation.inverse * rotation).normalized
        let previousTime = time
        setTime(cut.time, snap: false)
        var keys = KeyOperations()
        let edit = keys.setKey(cut.camera, .rotation, value: .quat(local), at: cut.time,
                               previous: baseScene.objects[cut.camera]?[.rotation], in: timeline)
        perform(.batch("Match cut", [.setTracks([edit])]))
        setTime(previousTime, snap: false)
        app.show("Lined up across the cut")
    }

    // MARK: Captions

    var captions: CaptionSettings? { timeline.captions }

    func setCaptions(_ settings: CaptionSettings?, coalesce: String? = nil) {
        guard settings != timeline.captions else { return }
        var copy = timeline
        copy.captions = settings
        perform(.batch(settings == nil ? "Captions off" : "Captions", [.setTimeline(copy)]), coalesceKey: coalesce)
    }

    /// Writes .srt (and .vtt) subtitles next to the renders.
    func exportSubtitles() -> URL? {
        let pages = Captions.pages(words, maxCharacters: captions?.maxCharacters ?? 32, maxLines: captions?.maxLines ?? 2)
        guard !pages.isEmpty else {
            app.show("Transcribe a voiceover first")
            return nil
        }
        let base = rendersFolder.appendingPathComponent(ProjectStore.sanitize(baseScene.name))
        do {
            try FileManager.default.createDirectory(at: rendersFolder, withIntermediateDirectories: true)
            try Data(Captions.srt(pages).utf8).write(to: base.appendingPathExtension("srt"), options: .atomic)
            try Data(Captions.vtt(pages).utf8).write(to: base.appendingPathExtension("vtt"), options: .atomic)
            return base.appendingPathExtension("srt")
        } catch {
            app.show("Couldn't write subtitles: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Post-processing (the Look)

    func updatePost(coalesce: String? = nil, _ change: (inout PostSettings) -> Void) {
        updateLook(coalesce: coalesce) { look in change(&look.post) }
    }

    // MARK: Stage preview

    /// Overlay images live in the project's assets folder.
    func overlayImage(_ name: String) -> CGImage? {
        if let cached = overlayImages[name] { return cached }
        let url = projectURL.appendingPathComponent(ProjectLayout.assetsFolder).appendingPathComponent(name)
        guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        overlayImages[name] = image
        return image
    }

    /// Feeds the stage's post-process pass: the look, the shot lens, screen effects, overlays and captions at the playhead.
    func updateStagePost() {
        guard let stage else { return }
        let look = displayDocument.effectiveLook
        let camera = stage.lookThrough != nil ? shotCamera : nil
        let lens = camera.flatMap { displayed.scene.objects[$0] }.map(CameraLens.init)
        let showsShot = stage.lookThrough != nil || mode == .export
        let screen = showsShot && previewEffects ? ScreenEffects.state(at: time, effects: timeline.effects, fps: timeline.fps) : ScreenState()
        var caption: (page: CaptionPage, word: Int?, settings: CaptionSettings)?
        if showsShot, let settings = timeline.captions, settings.enabled, !timeline.transcripts.isEmpty {
            let rect = frameRect
            let factor = rect.width < rect.height ? 0.6 : 1
            if captionCache?.factor != factor || captionCache?.revision != session.revision {
                captionCache = (factor, session.revision, Captions.pages(words, maxCharacters: max(Int(Double(settings.maxCharacters) * factor), 8),
                                                                         maxLines: settings.maxLines))
            }
            if let current = Captions.page(at: time, in: captionCache?.pages ?? []) {
                caption = (current.page, current.word, settings)
            }
        }
        let reduced = ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
        let overlays = stageOverlayPlacements()
        var images: [String: CGImage] = [:]
        for placement in overlays {
            if let name = placement.recipe.image, let image = overlayImage(name) { images[name] = image }
        }
        let glow = previewPost ? FrameLook.glow(in: displayed.scene) : 0
        stage.post = StagePost(look: FrameLook(post: previewPost ? look.post : PostSettings(), lens: lens, screen: screen, frame: timeline.frame(for: time),
                                               glow: glow),
                               frameRect: frameRect, overlays: overlays, caption: caption, reduced: reduced, images: images)
    }
}
