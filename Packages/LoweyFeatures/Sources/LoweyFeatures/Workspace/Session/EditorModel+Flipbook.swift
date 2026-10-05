import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Flipbook tracks: frame-by-frame drawing over the shot, anchored to the camera (screen FX) or to an object (drawn
/// effects that ride along with it). The Pencil draws into the drawing at the playhead; drawing past the last one
/// keeps the flipbook going. Every change is one `setFlipbooks` command.
extension EditorModel {
    var flipbookTracks: [FlipbookTrack] { timeline.flipbooks }

    /// The track the Pencil draws into.
    var activeFlipbook: FlipbookTrack? { flipbook.track.flatMap(timeline.flipbook) }

    /// The drawing of the active track at the playhead.
    var activeFlipbookFrame: Int? {
        activeFlipbook?.frameIndex(at: time, fps: timeline.fps, sceneDuration: timeline.duration)
    }

    // MARK: Layout on the stage

    /// Flipbooks laid out in stage points (inside `frameRect`), through the camera the stage shows.
    func stageFlipbookLayout() -> (layout: FlipbookLayout, rect: CGRect)? {
        guard let stage else { return nil }
        let rect = frameRect
        guard rect.width > 1, rect.height > 1 else { return nil }
        let camera = directorShot(in: stage.bounds.size)?.camera ?? stage.camera
        let pose = CoreTransform(position: Vec3(camera.position), rotation: Quat(camera.orientation))
        let layout = FlipbookLayout(width: Double(rect.width), height: Double(rect.height), camera: pose, fieldOfView: Double(camera.fieldOfView))
        return (layout, rect)
    }

    /// The anchor frame of a track on the stage, and the stage rect it's drawn in.
    private func stageAnchor(_ track: FlipbookTrack) -> (frame: FlipbookAnchorFrame, rect: CGRect)? {
        guard let (layout, rect) = stageFlipbookLayout(), let frame = layout.anchorFrame(track, in: displayed.scene) else { return nil }
        return (frame, rect)
    }

    // MARK: Drawing

    /// The path the current flipbook brush makes of samples, `pointsPerUnit` stage points to one of their units (1 for
    /// the live stroke in points, a drawing's scale when it's kept): the same function draws both.
    func flipbookPath(_ samples: [BrushInput<Vec2>], pointsPerUnit scale: Double = 1) -> BrushPath<Vec2> {
        BrushStroker.path(samples, brush: currentBrush(for: .flipbook), size: flipbook.width / scale, opacity: flipbook.opacity,
                          minimumSpacing: 1.5 / scale)
    }

    /// A finished stroke from points and pressures alone (tests; the Pencil gives full samples).
    func commitFlipbookStroke(points: [CGPoint], pressures: [Double]) {
        let samples = points.enumerated().map { index, point in
            BrushInput(point: Vec2(Double(point.x), Double(point.y)), pressure: pressures.indices.contains(index) ? pressures[index] : 1,
                       time: Double(index) / 240)
        }
        commitFlipbookStroke(samples, seed: Self.strokeSeed())
    }

    /// A finished Pencil stroke in stage points: joins the drawing at the playhead of the active track (a first
    /// stroke makes a track: on the selected object, else on the camera).
    func commitFlipbookStroke(_ samples: [BrushInput<Vec2>], seed: UInt64) {
        commitFlipbookStrokes([samples], seed: seed)
    }

    /// A stroke and its symmetry copies (the frame's guide), as one undo step.
    func commitFlipbookStrokes(_ copies: [[BrushInput<Vec2>]], seed: UInt64) {
        guard copies.contains(where: { !$0.isEmpty }) else { return }
        var track = activeFlipbook ?? newFlipbookTrack(named: nil, anchor: defaultFlipbookAnchor)
        var anchor = stageAnchor(track)
        if case .none = anchor, track.frames.isEmpty, track.anchor != .camera {
            // A new track whose object is out of view: draw on the camera instead.
            track.anchor = .camera
            anchor = stageAnchor(track)
        }
        guard let (frame, rect) = anchor else {
            app.show("Its object is out of view: draw where you can see it")
            return
        }
        let (key, brushCommand) = projectBrush(currentBrush(for: .flipbook))
        let color = currentColor.resolved(in: look.palette)
        var drawn = track
        for (index, samples) in copies.enumerated() where !samples.isEmpty {
            let units = samples.map { sample in
                var moved = sample
                moved.point = frame.point(Vec2(sample.point.x - Double(rect.minX), sample.point.y - Double(rect.minY)))
                return moved
            }
            let path = flipbookPath(units, pointsPerUnit: frame.pixelsPerUnit)
            guard !path.points.isEmpty else { continue }
            let stroke = FlipStroke(points: path.points, widths: path.widths, color: .rgba(color), alphas: path.alphas, brush: key,
                                    seed: seed &+ UInt64(index))
            drawn = FlipbookEditing.adding(stroke, at: time, fps: timeline.fps, hold: flipbook.hold, to: drawn, newID: Self.newID()).track
        }
        if performStroke(.setFlipbooks([FlipbookEdit(drawn)]), brush: brushCommand) { flipbook.track = track.id }
    }

    /// Erases the active track's drawing at the playhead under the eraser (one undo step per gesture).
    func eraseFlipbook(at points: [CGPoint], gesture: String) {
        guard let track = activeFlipbook, let index = activeFlipbookFrame, let (frame, rect) = stageAnchor(track) else { return }
        let radius = flipbook.eraserRadius
        let erased = FlipbookEditing.erasing(frame: index, in: track) { point in
            let pixel = frame.pixel(point)
            return points.contains { hypot(Double($0.x - rect.minX) - pixel.x, Double($0.y - rect.minY) - pixel.y) <= radius }
        }
        guard erased != track else { return }
        perform(.setFlipbooks([FlipbookEdit(erased)]), coalesceKey: gesture)
    }

    static func newID() -> String { UUID().uuidString.lowercased() }

    /// The selected object (not a camera) when one is selected, else the camera.
    var defaultFlipbookAnchor: FlipbookAnchor {
        if let object = singleSelection, object.kind != .camera, !object.kind.isOverlay { return .object(object.id) }
        return .camera
    }

    // MARK: Tracks

    /// A new empty track (not yet in the timeline: the first stroke or effect adds it).
    func newFlipbookTrack(named name: String?, anchor: FlipbookAnchor) -> FlipbookTrack {
        let number = timeline.flipbooks.count + 1
        let objectName = anchor.object.flatMap { scene.objects[$0]?.name }
        return FlipbookTrack(id: Self.newID(), name: name ?? objectName.map { "\($0) FX" } ?? "Flipbook \(number)", anchor: anchor,
                             start: time)
    }

    /// Starts a new track: the next stroke goes into it.
    func startNewFlipbook() {
        flipbook.track = nil
        tool = .flipbook
        app.show(defaultFlipbookAnchor == .camera ? "Draw: a new flipbook on the camera" : "Draw: a new flipbook on “\(singleSelection?.name ?? "")”")
    }

    func updateFlipbook(_ label: String, coalesceKey: String? = nil, _ change: (inout FlipbookTrack) -> Void) {
        guard var track = activeFlipbook else { return }
        change(&track)
        perform(.batch(label, [.setFlipbooks([FlipbookEdit(track)])]), coalesceKey: coalesceKey)
    }

    func deleteFlipbook() {
        guard let track = activeFlipbook else { return }
        perform(.setFlipbooks([FlipbookEdit(id: track.id, track: nil)]))
        flipbook.track = timeline.flipbooks.last?.id
    }

    /// Pins the active track to the selected object, or back to the camera.
    func anchorFlipbook(to anchor: FlipbookAnchor) {
        updateFlipbook("Anchor flipbook") { $0.anchor = anchor }
    }

    // MARK: Drawings

    func addFlipbookDrawing() {
        guard let track = activeFlipbook else { return }
        let index = activeFlipbookFrame ?? track.frames.count - 1
        let updated = FlipbookEditing.insertingFrame(after: index, hold: flipbook.hold, in: track, newID: Self.newID())
        perform(.setFlipbooks([FlipbookEdit(updated)]))
        setTime(updated.startTime(ofFrame: index + 1, fps: timeline.fps))
    }

    func duplicateFlipbookDrawing() {
        guard let track = activeFlipbook, let index = activeFlipbookFrame else { return }
        perform(.setFlipbooks([FlipbookEdit(FlipbookEditing.duplicatingFrame(index, in: track, newID: Self.newID()))]))
        setTime(track.startTime(ofFrame: index + 1, fps: timeline.fps) + (Double(track.frames[index].hold) / Double(timeline.fps)))
    }

    func deleteFlipbookDrawing() {
        guard let track = activeFlipbook, let index = activeFlipbookFrame else { return }
        perform(.setFlipbooks([FlipbookEdit(FlipbookEditing.removingFrame(index, from: track))]))
    }

    /// Lengthens or shortens the hold of the drawing at the playhead.
    func changeFlipbookHold(by delta: Int) {
        guard let track = activeFlipbook, let index = activeFlipbookFrame else { return }
        let updated = FlipbookEditing.settingHold(track.frames[index].hold + delta, ofFrame: index, in: track)
        perform(.setFlipbooks([FlipbookEdit(updated)]), coalesceKey: "flipbook-hold")
    }

    /// Jumps to a drawing of a track and makes the track active.
    func showFlipbookDrawing(_ index: Int, of trackID: String) {
        guard let track = timeline.flipbook(trackID), track.frames.indices.contains(index) else { return }
        flipbook.track = trackID
        setTime(track.startTime(ofFrame: index, fps: timeline.fps))
    }

    // MARK: Drawn effects

    /// A ready-made drawn effect (impact burst, sparkle…) as a new track at the playhead, on the selection or the camera.
    func addFlipbookEffect(_ fx: FlipbookFX) {
        let anchor = defaultFlipbookAnchor
        var track = newFlipbookTrack(named: fx.title, anchor: anchor)
        var ids = IDFactory.random
        let size: Double = switch anchor {
        case .camera: 0.45
        case let .object(id): max((operations.bounds.worldBounds(of: [id], in: scene).map { $0.size.maxComponent } ?? 1) * 1.4, 0.3)
        }
        let white: ColorValue = .rgba(.white)
        let color: ColorValue = fx == .sweatDrop ? .rgba(RGBA.hex("#8FD3FF")) : (currentColor == .palette(0) ? white : currentColor)
        track.frames = fx.frames(size: size, color: color, seed: UInt64(truncatingIfNeeded: track.id.hashValue), ids: &ids)
        track.loops = fx.loops
        if fx.loops { track.end = min(time + 2, timeline.duration) }
        if case .object = anchor, fx == .sweatDrop { track.offset = Vec2(size * 0.3, size * 0.6) }
        if perform(.setFlipbooks([FlipbookEdit(track)])) {
            flipbook.track = track.id
            HmmHaptics.play(.commit)
        }
    }

    // MARK: Onion skin

    /// The drawings before (tinted red) and after (green) the one at the playhead, faded, in stage points.
    func flipbookOnionSkin() -> [(outlines: [[CGPoint]], before: Bool, fade: Double)] {
        guard tool == .flipbook, flipbook.onionSkin, let track = activeFlipbook, let (frame, rect) = stageAnchor(track) else { return [] }
        let current = activeFlipbookFrame ?? (time >= track.start ? track.frames.count : -1)
        var result: [(outlines: [[CGPoint]], before: Bool, fade: Double)] = []
        let offsets = (1 ... max(flipbook.onionBefore, 1)).map { -$0 } + (1 ... max(flipbook.onionAfter, 1)).map { $0 }
        for offset in offsets where track.frames.indices.contains(current + offset) {
            if offset < 0, -offset > flipbook.onionBefore { continue }
            if offset > 0, offset > flipbook.onionAfter { continue }
            let outlines = track.frames[current + offset].strokes.map { stroke -> [CGPoint] in
                let pixels = FlipbookPixelStroke(points: stroke.points.map(frame.pixel), widths: stroke.widths.map { $0 * frame.pixelsPerUnit },
                                                 color: .white, filled: stroke.filled)
                let shape = stroke.filled ? pixels.points : FlipbookLayout.outline(pixels)
                return shape.map { CGPoint(x: rect.minX + CGFloat($0.x), y: rect.minY + CGFloat($0.y)) }
            }
            result.append((outlines, offset < 0, 1 / Double(abs(offset) + 1)))
        }
        return result
    }
}
