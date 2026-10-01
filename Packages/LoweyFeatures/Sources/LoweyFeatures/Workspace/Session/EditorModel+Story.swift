import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Text in the world, titles and shapes over the frame, particle effects, screen effects, transitions, the match
/// cut and captions.
extension EditorModel {
    // MARK: Adding

    func addText3D(_ text: String = "ENIGMA", style: TextRecipe.Style = .blocky) {
        refreshOperationsLibrary()
        var object = SceneObject(id: .make(), name: ObjectFactory.uniqueName("Text", in: scene), kind: .text(TextRecipe(text: text, style: style)))
        object[.color] = .color(currentColor)
        object = operations.placeOnGround(object, at: dropPoint())
        object = operations.nudgedToFreeSpot(object, in: scene)
        if perform(operations.add(object)) { select(object.id) }
    }

    /// An overlay in the frame (titles near the top, labels near the bottom, marks in the middle).
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
            app.show(directorView ? "Drag it in the frame; pinch to size it" : "It's in the frame: the Director view frames it like the export")
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
            if recipe.burst { app.show("\(preset.title) goes off at \(TimeFormat.clock(time))") }
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

    /// Overlays as they appear on the stage (points), for hit testing, dragging and the selection frame.
    func stageOverlayPlacements() -> [OverlayPlacement] {
        guard let stage, displayed.scene.objects.values.contains(where: \.kind.isOverlay) else { return [] }
        let rect = frameRect
        guard rect.width > 1, rect.height > 1 else { return [] }
        let aspect = Double(rect.width / rect.height)
        let camera = directorShot(in: stage.bounds.size)?.camera ?? stage.camera
        let pose = CoreTransform(position: Vec3(camera.position), rotation: Quat(camera.orientation))
        return OverlayLayout.placements(in: displayed.scene, palette: document.palette, width: Double(rect.width), height: Double(rect.height),
                                        time: time) { point in
            OverlayLayout.project(point, camera: pose, fieldOfView: Double(camera.fieldOfView), aspect: aspect)
        }
    }

    /// The top-most overlay under a stage point.
    func overlayHit(at point: CGPoint) -> ObjectID? {
        let rect = frameRect
        let local = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
        for placement in stageOverlayPlacements().reversed() {
            let box = OverlayRenderer.boxSize(placement, frame: rect.size)
            // Undo the overlay's rotation, then test its box with a comfortable margin.
            let dx = Double(local.x) - placement.center.x
            let dy = Double(local.y) - placement.center.y
            let rx = dx * cos(placement.angle) - dy * sin(placement.angle)
            let ry = dx * sin(placement.angle) + dy * cos(placement.angle)
            if abs(rx) <= Double(box.width) / 2 + 22, abs(ry) <= Double(box.height) / 2 + 22 { return placement.id }
        }
        return nil
    }

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
        updateTimeline(kind.title) { $0.effects.append(ScreenEffect(id: UUID().uuidString.lowercased(), kind: kind, start: time)) }
        HmmHaptics.play(.commit)
    }

    func removeScreenEffect(_ id: String) {
        updateTimeline("Remove effect") { $0.effects.removeAll { $0.id == id } }
    }

    func updateScreenEffect(_ id: String, coalesce: String? = nil, _ change: (inout ScreenEffect) -> Void) {
        guard let index = timeline.effects.firstIndex(where: { $0.id == id }) else { return }
        updateTimeline("Edit effect", coalesce: coalesce) { change(&$0.effects[index]) }
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

    /// Match cut: aims the camera that takes over so the selected subject sits exactly where it was in the previous
    /// shot's frame (a key on its rotation at the cut).
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
        guard let rotation = matchedRotation(cut: cut, previousCamera: previousCamera, subject: subject) else {
            app.show("The subject isn't in the previous shot")
            return
        }
        var keys = KeyOperations()
        let edit = keys.setKey(cut.camera, .rotation, value: .quat(rotation), at: cut.time, previous: baseScene.objects[cut.camera]?[.rotation],
                               in: timeline)
        perform(.batch("Match cut", [.setTracks([edit])]))
        app.show("Lined up across the cut")
    }

    private func matchedRotation(cut: CameraCut, previousCamera: ObjectID, subject: Vec3) -> Quat? {
        let rigs = rigs()
        let before = Animator.evaluate(session.document, at: max(cut.time - 1 / Double(timeline.fps), 0), rigs: rigs)
        let after = Animator.evaluate(session.document, at: cut.time, rigs: rigs)
        guard let fromObject = before.scene.objects[previousCamera], let toObject = after.scene.objects[cut.camera] else { return nil }
        let aspect = deliveryFraming.aspect
        let fromLens = CameraLens(fromObject).framing(aspect: aspect)
        guard let spot = OverlayLayout.project(subject, camera: before.scene.worldTransform(of: previousCamera), fieldOfView: fromLens.fieldOfView,
                                               aspect: aspect) else { return nil }
        let toWorld = after.scene.worldTransform(of: cut.camera)
        let toLens = CameraLens(toObject).framing(aspect: aspect)
        let rotation = MatchCut.aim(cameraAt: toWorld.position, subject: subject, framePoint: spot, fieldOfView: toLens.fieldOfView, aspect: aspect)
        let parentWorld = after.scene.objects[cut.camera]?.parent.map { after.scene.worldTransform(of: $0) } ?? .identity
        return (parentWorld.rotation.inverse * rotation).normalized
    }

    // MARK: Captions

    var captions: CaptionSettings? { timeline.captions }

    func setCaptions(_ settings: CaptionSettings?, coalesce: String? = nil) {
        guard settings != timeline.captions else { return }
        updateTimeline(settings == nil ? "Captions off" : "Captions", coalesce: coalesce) { $0.captions = settings }
    }

    func updateCaptions(coalesce: String? = nil, _ change: (inout CaptionSettings) -> Void) {
        var settings = captions ?? CaptionSettings()
        change(&settings)
        setCaptions(settings, coalesce: coalesce)
    }

    /// .srt (and .vtt) subtitles next to the renders.
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
            app.show("Couldn't write subtitles: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }
}
