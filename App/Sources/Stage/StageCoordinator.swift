import LoweyCore
import LoweyRender
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Turns touches on the stage into camera moves and editor actions.
///
/// Fingers navigate (1 finger orbit, 2 fingers pan + pinch zoom), taps select,
/// the Pencil draws when the Draw tool is on, 2-finger tap = undo, 3-finger tap = redo.
@MainActor
final class StageCoordinator: NSObject, UIGestureRecognizerDelegate {
    private weak var editor: EditorModel?
    private weak var stage: StageView?

    private let tap = UITapGestureRecognizer()
    private let doubleTap = UITapGestureRecognizer()
    private let undoTap = UITapGestureRecognizer()
    private let redoTap = UITapGestureRecognizer()
    /// Four fingers: hide or show the interface (focus mode), as in Procreate.
    private let focusTap = UITapGestureRecognizer()
    private let oneFingerPan = UIPanGestureRecognizer()
    private let twoFingerPan = UIPanGestureRecognizer()
    private let pinch = UIPinchGestureRecognizer()
    private let longPress = UILongPressGestureRecognizer()
    private let stroke = StrokeGestureRecognizer()
    private let twist = UIRotationGestureRecognizer()
    private let pencilRoll = PencilRollRecognizer()
    private let hover = UIHoverGestureRecognizer()
    private var twistKey = UUID().uuidString
    private var pinchKey = UUID().uuidString
    private var panKey = UUID().uuidString

    /// What the current one-finger drag is doing.
    private enum DragKind {
        case orbit
        case moveObjects(planeY: Double, last: Vec3)
        case gizmo(GizmoHandle, pivot: Vec3, lastPoint: CGPoint, accumulated: Double)
        /// Turning on a rotate ring: the pivot and grab are fixed for the whole drag; `applied` is what was turned so far
        /// (snapped in steps when rotation snapping is on, while the finger moves freely).
        case turn(RingDrag)
        case lasso
        case scatter(center: Vec3)
        /// Perform mode: moving the selection while the timeline records.
        case perform(planeY: Double, last: Vec3)
        /// Camera mode: aiming the shot camera (pan / tilt).
        case aimCamera
        /// Dragging a 2D overlay in the frame.
        case moveOverlay(ObjectID, last: CGPoint)
        case none
    }

    /// One drag on a rotate ring (see `ringAngle`).
    private struct RingDrag {
        var axis: CoreAxis
        var pivot: Vec3
        var start: CGPoint
        /// The ring's screen direction at the grabbed point (turning forwards) and its radius on screen.
        var tangent: CGVector
        var radius: CGFloat
        /// Seen face-on enough to turn by circling the pivot; edge-on, by sliding along the ring.
        var circular: Bool
        var total: Double = 0
        var applied: Double = 0
    }

    private var drag: DragKind = .none
    /// Two fingers that landed on the selection move it (twist turns, pinch sizes) instead of the camera.
    private var twoFingerOnSelection: Bool?
    private var twoFingerActive = Set<ObjectIdentifier>()
    private var twoFingerRotation: (pivot: Vec3, total: Double, applied: Double)?
    private var gestureKey = UUID().uuidString
    /// Scene menu → Speed: how far orbit, pan and zoom go per finger movement (1 = normal).
    private var navigationSpeed: Double { AppSettings.navigationFactor }
    private var strokeGuide: GuideSurface?
    private var strokeTargetMesh: MeshData?
    private var strokePoints: [Vec3] = []
    private var strokePressures: [Double] = []
    private var strokeNormals: [Vec3] = []

    init(editor: EditorModel, stage: StageView) {
        self.editor = editor
        self.stage = stage
        super.init()
        install()
    }

    private func install() {
        guard let stage else { return }
        tap.addTarget(self, action: #selector(handleTap(_:)))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        doubleTap.numberOfTapsRequired = 2
        doubleTap.addTarget(self, action: #selector(handleDoubleTap(_:)))
        tap.require(toFail: doubleTap)
        undoTap.numberOfTouchesRequired = 2
        undoTap.addTarget(self, action: #selector(handleUndoTap(_:)))
        redoTap.numberOfTouchesRequired = 3
        redoTap.addTarget(self, action: #selector(handleRedoTap(_:)))
        focusTap.numberOfTouchesRequired = 4
        focusTap.addTarget(self, action: #selector(handleFocusTap(_:)))
        oneFingerPan.maximumNumberOfTouches = 1
        oneFingerPan.addTarget(self, action: #selector(handleOneFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.addTarget(self, action: #selector(handleTwoFingerPan(_:)))
        pinch.addTarget(self, action: #selector(handlePinch(_:)))
        longPress.minimumPressDuration = 0.45
        longPress.addTarget(self, action: #selector(handleLongPress(_:)))
        stroke.addTarget(self, action: #selector(handleStroke(_:)))
        stroke.delegate = self
        stroke.onHold = { [weak self] in self?.snapToQuickShape() }
        twist.addTarget(self, action: #selector(handleTwist(_:)))
        twist.delegate = self
        hover.addTarget(self, action: #selector(handleHover(_:)))
        stage.addGestureRecognizer(hover)
        pencilRoll.configure()
        pencilRoll.onRoll = { [weak self] delta in self?.handlePencilRoll(delta) }
        pencilRoll.delegate = self
        for recognizer in [tap, doubleTap, undoTap, redoTap, focusTap, oneFingerPan, twoFingerPan, pinch, longPress] as [UIGestureRecognizer] {
            recognizer.delegate = self
        }
        let all: [UIGestureRecognizer] = [tap, doubleTap, undoTap, redoTap, focusTap, oneFingerPan, twoFingerPan, pinch, longPress, stroke, twist,
                                          pencilRoll]
        for recognizer in all {
            stage.addGestureRecognizer(recognizer)
        }
        updateTouchTypes()
    }

    /// Pencil draws in Draw mode; fingers keep navigating (unless "draw with finger" is on).
    func updateTouchTypes() {
        guard let editor else { return }
        let drawing = editor.tool == .draw && editor.mode == .build
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        let finger = NSNumber(value: UITouch.TouchType.direct.rawValue)
        stroke.isEnabled = drawing
        if drawing {
            stroke.allowedTouchTypes = editor.draw.pencilOnly ? [pencil] : [pencil, finger]
            oneFingerPan.allowedTouchTypes = editor.draw.pencilOnly ? [finger] : []
            oneFingerPan.isEnabled = editor.draw.pencilOnly
        } else {
            oneFingerPan.isEnabled = true
            oneFingerPan.allowedTouchTypes = [finger, pencil]
        }
    }

    // MARK: Delegate

    func gestureRecognizer(_ first: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith second: UIGestureRecognizer) -> Bool {
        if first === pencilRoll || second === pencilRoll { return true }
        let pair: Set<ObjectIdentifier> = [ObjectIdentifier(first), ObjectIdentifier(second)]
        let twoFinger: Set<ObjectIdentifier> = [ObjectIdentifier(twoFingerPan), ObjectIdentifier(pinch), ObjectIdentifier(twist)]
        return pair.isSubset(of: twoFinger)
    }

    /// Recording a performance of objects. Flying the camera while recording goes through the camera
    /// gestures instead (look through it, press Record, and your usual moves become the camera's path).
    private var isRecordingPerform: Bool {
        guard let editor else { return false }
        return editor.performPhase == .recording && !editor.performTargets.isEmpty && !operatesCamera
    }

    /// Camera mode, looking through the shot camera: gestures operate that camera.
    private var operatesCamera: Bool {
        guard let editor else { return false }
        return editor.mode == .camera && editor.lookThrough && editor.editedCamera != nil && editor.stage?.lookThrough != nil
    }

    // MARK: Pencil hover

    /// Apple Pencil hovering above the screen: preview where the stroke will land and how thick it will be.
    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        guard let editor else { return }
        guard UserDefaults.standard.bool(forKey: AppSettings.pencilHoverPreview) else {
            if editor.hoverPoint != nil { editor.hoverPoint = nil }
            return
        }
        switch recognizer.state {
        case .began, .changed:
            // Only the Pencil reports a height; a trackpad pointer doesn't need the preview.
            guard recognizer.zOffset > 0 || editor.tool == .draw else {
                editor.hoverPoint = nil
                return
            }
            editor.hoverPoint = recognizer.location(in: stage)
            editor.hoverHeight = Double(recognizer.zOffset)
        default:
            editor.hoverPoint = nil
        }
    }

    // MARK: Taps

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let editor, let stage else { return }
        let point = recognizer.location(in: stage)
        // Overlays sit on top of the world: they win the tap.
        if !editor.eyedropperActive, editor.tool != .draw, let overlay = editor.overlayHit(at: point) {
            editor.select(overlay)
            return
        }
        let picked = stage.pickObject(at: point)
        if editor.eyedropperActive {
            if let (id, _) = picked { editor.eyedrop(object: id) }
            return
        }
        switch editor.tool {
        case .draw:
            // Tapping an object in draw mode picks it as the guide centre.
            editor.select(picked?.0)
        default:
            editor.select(picked?.0)
        }
        editor.refreshGuide()
    }

    @objc private func handleDoubleTap(_: UITapGestureRecognizer) {
        editor?.frameSelection()
    }

    @objc private func handleUndoTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        editor?.undo()
    }

    @objc private func handleRedoTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        editor?.redo()
    }

    @objc private func handleFocusTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let editor else { return }
        editor.focusMode.toggle()
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let editor, let stage else { return }
        let point = recognizer.location(in: stage)
        if let (id, _) = stage.pickObject(at: point) {
            editor.select(id, additive: true)
            Haptics.tap()
        }
    }

    // MARK: One-finger drag

    @objc private func handleOneFingerPan(_ recognizer: UIPanGestureRecognizer) {
        guard let editor, let stage else { return }
        let point = recognizer.location(in: stage)
        switch recognizer.state {
        case .began:
            gestureKey = UUID().uuidString
            let start = CGPoint(x: point.x - recognizer.translation(in: stage).x, y: point.y - recognizer.translation(in: stage).y)
            drag = beginDrag(at: start, editor: editor, stage: stage)
            continueDrag(to: point, translation: recognizer.translation(in: stage), editor: editor, stage: stage)
            recognizer.setTranslation(.zero, in: stage)
        case .changed:
            continueDrag(to: point, translation: recognizer.translation(in: stage), editor: editor, stage: stage)
            recognizer.setTranslation(.zero, in: stage)
        case .ended, .cancelled, .failed:
            endDrag(at: point, editor: editor, stage: stage, cancelled: recognizer.state != .ended)
            drag = .none
        default:
            break
        }
    }

    private func beginDrag(at point: CGPoint, editor: EditorModel, stage: StageView) -> DragKind {
        if isRecordingPerform {
            let planeY = editor.selectionPivot?.y ?? 0
            let start = GuideSurface.plane(origin: Vec3(0, planeY, 0), normal: .unitY)
                .intersect(stage.worldRay(at: point) ?? Ray(origin: .zero, direction: .unitY))?.point ?? .zero
            editor.performTouchBegan([.position])
            return .perform(planeY: planeY, last: start)
        }
        if let overlay = editor.selectedOverlay, editor.overlayHit(at: point) == overlay {
            return .moveOverlay(overlay, last: point)
        }
        if operatesCamera { return .aimCamera }
        guard editor.mode == .build || editor.mode == .look || editor.mode == .animate else { return .orbit }
        switch editor.tool {
        case .lasso:
            editor.lassoPoints = [point]
            return .lasso
        case .scatter:
            guard !editor.selection.isEmpty, let center = stage.groundPoint(at: point) else { return .orbit }
            editor.scatterPreview = (point, 0)
            return .scatter(center: center)
        case .draw:
            return .orbit
        case .select:
            if editor.gizmoMode == .rotate, let (axis, grab) = stage.pickRotationRing(at: point), let pivot = editor.rotationPivot,
               let ring = ringDrag(axis: axis, pivot: pivot, grab: grab, start: point, stage: stage) {
                return .turn(ring)
            }
            if editor.gizmoMode != .rotate, let handle = stage.pickGizmo(at: point), let pivot = editor.selectionPivot {
                return .gizmo(handle, pivot: pivot, lastPoint: point, accumulated: 0)
            }
            if let (id, hit) = stage.pickObject(at: point), editor.selection.contains(where: { $0 == id || editor.scene.isAncestor($0, of: id) }),
               !editor.selection.contains(where: { editor.scene.isEffectivelyLocked($0) }) {
                let planeY = editor.selectionPivot?.y ?? hit.point.y
                let start = GuideSurface.plane(origin: Vec3(0, planeY, 0), normal: .unitY).intersect(stage.worldRay(at: point) ?? Ray(
                    origin: .zero,
                    direction: .unitY
                ))?.point ?? hit.point
                return .moveObjects(planeY: planeY, last: start)
            }
            return .orbit
        }
    }

    private func continueDrag(to point: CGPoint, translation: CGPoint, editor: EditorModel, stage: StageView) {
        switch drag {
        case .orbit:
            var viewpoint = stage.viewpoint
            let degreesPerPoint = 0.3 * navigationSpeed
            viewpoint.yaw -= Double(translation.x) * degreesPerPoint
            viewpoint.pitch += Double(translation.y) * degreesPerPoint
            stage.setViewpoint(viewpoint)

        case let .moveObjects(planeY, last):
            guard let ray = stage.worldRay(at: point),
                  let hit = GuideSurface.plane(origin: Vec3(0, planeY, 0), normal: .unitY).intersect(ray) else { return }
            var delta = hit.point - last
            delta.y = 0
            // Keep huge jumps (ray near the horizon) in check.
            if delta.length > 20 { return }
            editor.translateSelection(by: delta, gesture: gestureKey)
            drag = .moveObjects(planeY: planeY, last: hit.point)

        case let .gizmo(handle, pivot, lastPoint, accumulated):
            let result = gizmoDelta(handle: handle, pivot: pivot, from: lastPoint, to: point, stage: stage)
            switch handle.kind {
            case .move:
                // With grid snap on, the object jumps cell by cell while the finger moves freely.
                let total = accumulated + result
                var step = result
                if editor.snap.grid {
                    step = Snapping.snapToGrid(total, size: editor.snap.gridSize) - Snapping.snapToGrid(accumulated, size: editor.snap.gridSize)
                }
                if step != 0 { editor.translateSelection(by: handle.axis.unit * step, gesture: gestureKey) }
                drag = .gizmo(handle, pivot: pivot + handle.axis.unit * step, lastPoint: point, accumulated: total)
            case .rotate:
                // Rings are handled by `.turn`; a rotate handle here would come from an old gizmo.
                break
            case .scale:
                let factor = max(0.2, 1 + result)
                var vector = Vec3.one
                vector[handle.axis] = factor
                editor.scaleSelection(by: vector, gesture: gestureKey)
                drag = .gizmo(handle, pivot: pivot, lastPoint: point, accumulated: accumulated)
            case .uniformScale:
                let factor = max(0.2, exp(-Double(point.y - lastPoint.y) * 0.006 + Double(point.x - lastPoint.x) * 0.006))
                editor.scaleSelection(by: Vec3(factor, factor, factor), gesture: gestureKey)
                drag = .gizmo(handle, pivot: pivot, lastPoint: point, accumulated: accumulated)
            }

        case var .turn(ring):
            ring.total = ringAngle(ring, at: point, stage: stage)
            let step = editor.snap.rotation ? editor.snap.rotationStep * .pi / 180 : 0
            let wanted = step > 0 ? (ring.total / step).rounded() * step : ring.total
            if abs(wanted - ring.applied) > 1e-9 {
                editor.rotateSelection(by: wanted - ring.applied, axis: ring.axis, around: ring.pivot, gesture: gestureKey)
                if step > 0 { Haptics.select() }
                ring.applied = wanted
            }
            drag = .turn(ring)

        case .lasso:
            if let last = editor.lassoPoints.last, hypot(last.x - point.x, last.y - point.y) > 4 {
                editor.lassoPoints.append(point)
            }

        case let .scatter(center):
            guard let ground = stage.groundPoint(at: point, height: center.y),
                  let centerScreen = stage.screenPoint(of: center) else { return }
            let radius = Vec3(ground.x - center.x, 0, ground.z - center.z).length
            let right = (stage.viewpoint.rotation.act(.unitX))
            let edgeScreen = stage.screenPoint(of: center + Vec3(right.x, 0, right.z).normalized * radius) ?? point
            editor.scatterPreview = (centerScreen, hypot(edgeScreen.x - centerScreen.x, edgeScreen.y - centerScreen.y))
            scatterRadius = radius

        case let .perform(planeY, last):
            guard let ray = stage.worldRay(at: point),
                  let hit = GuideSurface.plane(origin: Vec3(0, planeY, 0), normal: .unitY).intersect(ray) else { return }
            var delta = hit.point - last
            delta.y = 0
            if delta.length > 20 { return }
            editor.performMove(by: delta)
            drag = .perform(planeY: planeY, last: hit.point)

        case .aimCamera:
            editor.aimCamera(pan: -Double(translation.x) * 0.15 * navigationSpeed, tilt: -Double(translation.y) * 0.15 * navigationSpeed,
                             gesture: gestureKey)

        case let .moveOverlay(id, last):
            editor.moveOverlay(id, by: CGSize(width: point.x - last.x, height: point.y - last.y), gesture: gestureKey)
            drag = .moveOverlay(id, last: point)

        case .none:
            break
        }
    }

    private var scatterRadius: Double = 0

    private func endDrag(at _: CGPoint, editor: EditorModel, stage: StageView, cancelled: Bool) {
        switch drag {
        case .moveObjects:
            editor.finishTransform(gesture: gestureKey)
        case .gizmo:
            editor.finishTransform(gesture: gestureKey)
        case .turn:
            // Snapping happened during the turn (in steps of the whole turn, from where it started).
            editor.endGesture()
        case .lasso:
            if !cancelled { selectInLasso(editor: editor, stage: stage) }
            editor.lassoPoints = []
        case let .scatter(center):
            editor.scatterPreview = nil
            if !cancelled, scatterRadius > 0.2 { editor.scatterSelection(center: center, radius: scatterRadius) }
            scatterRadius = 0
        case .perform:
            editor.performTouchEnded()
        case .orbit, .aimCamera, .moveOverlay, .none:
            break
        }
        editor.endGesture()
    }

    // MARK: Rotate rings

    private func ringDrag(axis: CoreAxis, pivot: Vec3, grab: Vec3, start: CGPoint, stage: StageView) -> RingDrag? {
        guard let center = stage.screenPoint(of: pivot), let grabScreen = stage.screenPoint(of: grab) else { return nil }
        // Turning forwards (right-hand rule about the axis) moves the grabbed point along axis × (grab − pivot).
        let arm = grab - pivot
        let forward = axis.unit.cross(arm).normalized
        guard let ahead = stage.screenPoint(of: grab + forward * max(arm.length * 0.05, 1e-3)) else { return nil }
        var tangent = CGVector(dx: ahead.x - grabScreen.x, dy: ahead.y - grabScreen.y)
        let length = hypot(tangent.dx, tangent.dy)
        guard length > 1e-6 else { return nil }
        tangent = CGVector(dx: tangent.dx / length, dy: tangent.dy / length)
        let toCamera = (stage.viewpoint.eye - pivot).normalized
        let facing = abs(axis.unit.dot(toCamera))
        let radius = max(hypot(grabScreen.x - center.x, grabScreen.y - center.y), 30)
        return RingDrag(axis: axis, pivot: pivot, start: start, tangent: tangent, radius: radius, circular: facing > 0.45)
    }

    /// How far the ring has turned (radians) with the finger at `point`.
    private func ringAngle(_ ring: RingDrag, at point: CGPoint, stage: StageView) -> Double {
        if ring.circular, let center = stage.screenPoint(of: ring.pivot) {
            // Face-on: the angle the finger swept around the pivot on screen (unwrapped, so several turns add up).
            let a0 = atan2(Double(ring.start.y - center.y), Double(ring.start.x - center.x))
            let a1 = atan2(Double(point.y - center.y), Double(point.x - center.x))
            var swept = a1 - a0
            let previous = ring.total
            // Continue from the last value (no jump when crossing ±180°).
            let toCamera = (stage.viewpoint.eye - ring.pivot).normalized
            let sign: Double = ring.axis.unit.dot(toCamera) > 0 ? -1 : 1
            swept *= sign
            let turns = ((previous - swept) / (2 * .pi)).rounded()
            return swept + turns * 2 * .pi
        }
        // Edge-on: slide along the ring's direction where it was grabbed; one ring radius of travel is one radian.
        let moved = Double((point.x - ring.start.x) * ring.tangent.dx + (point.y - ring.start.y) * ring.tangent.dy)
        return moved / Double(ring.radius)
    }

    /// Converts a screen drag into movement along / rotation around a gizmo axis.
    private func gizmoDelta(handle: GizmoHandle, pivot: Vec3, from: CGPoint, to: CGPoint, stage: StageView) -> Double {
        let axis = handle.axis.unit
        guard let p0 = stage.screenPoint(of: pivot) else { return 0 }
        switch handle.kind {
        case .move, .scale:
            // Screen direction of the axis and how many pixels one meter spans.
            let reach = max(stage.gizmo.scale.x, 0.05)
            guard let p1 = stage.screenPoint(of: pivot + axis * Double(reach)) else { return 0 }
            let axisScreen = CGVector(dx: p1.x - p0.x, dy: p1.y - p0.y)
            let pixels = hypot(axisScreen.dx, axisScreen.dy)
            guard pixels > 2 else { return 0 }
            let unit = CGVector(dx: axisScreen.dx / pixels, dy: axisScreen.dy / pixels)
            let moved = Double((to.x - from.x) * unit.dx + (to.y - from.y) * unit.dy)
            let metersPerPixel = Double(reach) / Double(pixels)
            if handle.kind == .scale {
                // Relative: dragging one gizmo length doubles the size.
                return moved / Double(pixels)
            }
            return moved * metersPerPixel
        case .rotate:
            let a0 = atan2(Double(from.y - p0.y), Double(from.x - p0.x))
            let a1 = atan2(Double(to.y - p0.y), Double(to.x - p0.x))
            var delta = a1 - a0
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            // Screen angles grow clockwise; flip when the axis points at the camera.
            let toCamera = (stage.viewpoint.eye - pivot).normalized
            return axis.dot(toCamera) > 0 ? -delta : delta
        case .uniformScale:
            return 0
        }
    }

    private func selectInLasso(editor: EditorModel, stage: StageView) {
        let polygon = editor.lassoPoints
        guard polygon.count >= 3 else { return }
        var hits: [ObjectID] = []
        for id in editor.scene.orderedIDs() {
            guard let object = editor.scene.objects[id], object.parent == nil || !hits.contains(object.parent!),
                  editor.scene.isEffectivelyVisible(id),
                  let bounds = editor.renderer.visualBounds(of: [id]),
                  let screen = stage.screenPoint(of: bounds.center) else { continue }
            if Self.contains(polygon, screen), !hits.contains(where: { editor.scene.isAncestor($0, of: id) }) {
                hits.append(id)
            }
        }
        editor.setSelection(hits)
        if !hits.isEmpty { Haptics.select() }
    }

    static func contains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: Two fingers

    /// Whether this two-finger gesture works on the selection (decided once, by where the fingers first came down).
    private func onSelection(_ recognizer: UIGestureRecognizer) -> Bool {
        let id = ObjectIdentifier(recognizer)
        switch recognizer.state {
        case .began:
            twoFingerActive.insert(id)
            if twoFingerOnSelection == nil { twoFingerOnSelection = touchesSelection(at: recognizer.location(in: stage)) }
        case .ended, .cancelled, .failed:
            twoFingerActive.remove(id)
        default:
            break
        }
        let result = twoFingerOnSelection ?? false
        if twoFingerActive.isEmpty, recognizer.state != .began, recognizer.state != .changed {
            twoFingerOnSelection = nil
            twoFingerRotation = nil
        }
        return result
    }

    /// Two fingers on a selected, unlocked object (Build or Animate, Select tool): they hold the object, not the camera.
    private func touchesSelection(at point: CGPoint) -> Bool {
        guard let editor, let stage, editor.mode == .build || editor.mode == .animate, editor.tool == .select,
              !editor.selection.isEmpty, editor.performPhase == .idle, !operatesCamera, editor.selectedOverlay == nil,
              !editor.selection.contains(where: { editor.scene.isEffectivelyLocked($0) }),
              let (id, _) = stage.pickObject(at: point) else { return false }
        return editor.selection.contains { $0 == id || editor.scene.isAncestor($0, of: id) }
    }

    @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        guard let stage else { return }
        if onSelection(recognizer) {
            // Holding the object: the camera stays where it is.
            recognizer.setTranslation(.zero, in: stage)
            return
        }
        if operatesCamera, let editor {
            if recognizer.state == .began { panKey = UUID().uuidString }
            if recognizer.state == .ended || recognizer.state == .cancelled { editor.endGesture() }
            let translation = recognizer.translation(in: stage)
            recognizer.setTranslation(.zero, in: stage)
            // Truck / pedestal: move the camera sideways and up in its own frame.
            let step = 0.01 * navigationSpeed
            editor.moveCamera(local: Vec3(-Double(translation.x) * step, Double(translation.y) * step, 0), gesture: panKey)
            return
        }
        guard recognizer.state == .changed || recognizer.state == .began else { return }
        let translation = recognizer.translation(in: stage)
        recognizer.setTranslation(.zero, in: stage)
        var viewpoint = stage.viewpoint
        let viewHeight = Double(max(stage.bounds.height, 1))
        // 1× keeps the ground under your fingers; the speed setting scales it.
        let metersPerPixel = 2 * viewpoint.distance * tan(viewpoint.fieldOfView * .pi / 360) / viewHeight * navigationSpeed
        let right = viewpoint.rotation.act(.unitX)
        let up = viewpoint.rotation.act(.unitY)
        viewpoint.target -= right * (Double(translation.x) * metersPerPixel)
        viewpoint.target += up * (Double(translation.y) * metersPerPixel)
        stage.setViewpoint(viewpoint)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let holdsSelection = onSelection(recognizer)
        if isRecordingPerform, let editor {
            switch recognizer.state {
            case .began: editor.performTouchBegan([.scale])
            case .changed: editor.performScale(by: Double(recognizer.scale))
            default: editor.performTouchEnded()
            }
            recognizer.scale = 1
            return
        }
        if let editor, let overlay = editor.selectedOverlay {
            if recognizer.state == .began { pinchKey = UUID().uuidString }
            if recognizer.state == .ended || recognizer.state == .cancelled {
                editor.endGesture()
                return
            }
            editor.scaleOverlay(overlay, by: Double(recognizer.scale), gesture: pinchKey)
            recognizer.scale = 1
            return
        }
        if holdsSelection, let editor {
            // Pinch on the object: it grows or shrinks (from its base), like in Reality Composer.
            if recognizer.state == .began { pinchKey = UUID().uuidString }
            if recognizer.state == .ended || recognizer.state == .cancelled {
                editor.finishTransform(gesture: pinchKey)
                return
            }
            let factor = min(max(Double(recognizer.scale), 0.5), 2)
            if abs(factor - 1) > 1e-4 { editor.scaleSelection(by: Vec3(factor, factor, factor), gesture: pinchKey) }
            recognizer.scale = 1
            return
        }
        if operatesCamera, let editor {
            if recognizer.state == .began { pinchKey = UUID().uuidString }
            if recognizer.state == .ended || recognizer.state == .cancelled {
                editor.endGesture()
                return
            }
            // Dolly: pinch out moves the camera forward.
            editor.moveCamera(local: Vec3(0, 0, -Double(recognizer.scale - 1) * 3 * navigationSpeed), gesture: pinchKey)
            recognizer.scale = 1
            return
        }
        guard let stage, recognizer.state == .changed || recognizer.state == .began else { return }
        var viewpoint = stage.viewpoint
        viewpoint.distance /= pow(Double(max(recognizer.scale, 0.01)), navigationSpeed)
        recognizer.scale = 1
        stage.setViewpoint(viewpoint)
    }

    // MARK: Twist & Pencil roll (Perform)

    @objc private func handleTwist(_ recognizer: UIRotationGestureRecognizer) {
        guard let editor else { return }
        let holdsSelection = onSelection(recognizer)
        if isRecordingPerform {
            switch recognizer.state {
            case .began: editor.performTouchBegan([.rotation])
            case .changed: editor.performRotate(by: -Double(recognizer.rotation))
            default: editor.performTouchEnded()
            }
            recognizer.rotation = 0
            return
        }
        if let overlay = editor.selectedOverlay {
            if recognizer.state == .began { twistKey = UUID().uuidString }
            if recognizer.state == .ended || recognizer.state == .cancelled {
                editor.endGesture()
                return
            }
            editor.rotateOverlay(overlay, by: -Double(recognizer.rotation), gesture: twistKey)
            recognizer.rotation = 0
            return
        }
        if operatesCamera {
            if recognizer.state == .began { twistKey = UUID().uuidString }
            if recognizer.state == .ended || recognizer.state == .cancelled {
                editor.endGesture()
                return
            }
            editor.rollCamera(by: Double(recognizer.rotation), gesture: twistKey)
            recognizer.rotation = 0
            return
        }
        if holdsSelection {
            // Twist on the object: it turns about the vertical, the way your fingers turn (snapping in steps if on).
            switch recognizer.state {
            case .began:
                twistKey = UUID().uuidString
                twoFingerRotation = editor.rotationPivot.map { (pivot: $0, total: 0.0, applied: 0.0) }
            case .changed:
                guard var turn = twoFingerRotation else { break }
                // Fingers turning clockwise on screen turn it clockwise seen from above (negative about +Y).
                turn.total -= Double(recognizer.rotation)
                let step = editor.snap.rotation ? editor.snap.rotationStep * .pi / 180 : 0
                let wanted = step > 0 ? (turn.total / step).rounded() * step : turn.total
                if abs(wanted - turn.applied) > 1e-9 {
                    editor.rotateSelection(by: wanted - turn.applied, axis: .y, around: turn.pivot, gesture: twistKey)
                    if step > 0 { Haptics.select() }
                    turn.applied = wanted
                }
                twoFingerRotation = turn
            default:
                editor.endGesture()
                twoFingerRotation = nil
            }
            recognizer.rotation = 0
        }
    }

    /// Apple Pencil Pro barrel roll turns the performed object while it moves.
    private func handlePencilRoll(_ delta: Double) {
        guard let editor, isRecordingPerform, editor.performSettings.barrelRoll else { return }
        if !editor.performChannels.contains(where: { $0.property == .rotation }) {
            editor.performTouchBegan([.rotation])
        }
        editor.performRotate(by: -delta)
    }

    // MARK: Drawing

    @objc private func handleStroke(_ recognizer: StrokeGestureRecognizer) {
        guard let editor, let stage else { return }
        switch recognizer.state {
        case .began:
            snapped = nil
            strokePoints = []
            strokePressures = []
            strokeNormals = []
            strokeGuide = editor.currentGuide
            strokeTargetMesh = nil
            if editor.draw.guide == .object, let first = recognizer.samples.first {
                if let (id, _) = stage.pickObject(at: first.location) {
                    strokeTargetMesh = editor.renderer.worldMesh(of: id)
                }
                if strokeTargetMesh == nil {
                    editor.app.show("Start the stroke on an object")
                }
            }
            consume(recognizer.samples, editor: editor, stage: stage)
        case .changed:
            if snapped != nil {
                adjustQuickShape(editor: editor, stage: stage)
            } else {
                consume(recognizer.samples.suffix(from: min(consumedSamples, recognizer.samples.count)).map { $0 }, editor: editor, stage: stage)
            }
        case .ended:
            if snapped != nil {
                adjustQuickShape(editor: editor, stage: stage)
            } else {
                consume(recognizer.samples.suffix(from: min(consumedSamples, recognizer.samples.count)).map { $0 }, editor: editor, stage: stage)
            }
            stage.showStrokePreview(nil, color: .white)
            editor.commitStroke(points: strokePoints, pressures: strokePressures, normals: strokeNormals, guide: strokeGuide)
            consumedSamples = 0
            snapped = nil
        default:
            stage.showStrokePreview(nil, color: .white)
            consumedSamples = 0
            snapped = nil
        }
    }

    // MARK: QuickShape

    /// The shape the held stroke snapped to, where the tip was when it snapped, and the stroke's pressure.
    private var snapped: (shape: QuickShape.Result, anchor: CGPoint, pressure: Double)?

    /// Draw, then hold: replace the stroke with the clean shape it was meant to be.
    private func snapToQuickShape() {
        guard let editor, let stage, stroke.state == .began || stroke.state == .changed,
              let anchor = stroke.samples.last?.location else { return }
        let points = stroke.samples.map { Vec2(Double($0.location.x), Double($0.location.y)) }
        guard let shape = QuickShape.fit(points) else { return }
        let pressure = stroke.samples.map(\.pressure).reduce(0, +) / Double(max(stroke.samples.count, 1))
        snapped = (shape, anchor, pressure)
        redrawStroke(shape.points, pressure: pressure, editor: editor, stage: stage)
        Haptics.select()
        editor.app.show("\(shape.kind.title). Keep holding and drag to adjust")
    }

    /// Still holding after the snap: the line's end follows the tip; other shapes turn and scale.
    private func adjustQuickShape(editor: EditorModel, stage: StageView) {
        guard let snapped, let tip = stroke.samples.last?.location else { return }
        let shape = QuickShape.adjusted(snapped.shape, anchor: Vec2(Double(snapped.anchor.x), Double(snapped.anchor.y)),
                                        current: Vec2(Double(tip.x), Double(tip.y)))
        redrawStroke(shape.points, pressure: snapped.pressure, editor: editor, stage: stage)
    }

    /// Replaces the stroke so far with `points` (screen space), projected like any stroke onto its guide.
    private func redrawStroke(_ points: [Vec2], pressure: Double, editor: EditorModel, stage: StageView) {
        strokePoints = []
        strokePressures = []
        strokeNormals = []
        let samples = points.map { StrokeGestureRecognizer.Sample(location: CGPoint(x: $0.x, y: $0.y), pressure: pressure) }
        project(samples, editor: editor, stage: stage)
        updatePreview(editor: editor, stage: stage)
    }

    private var consumedSamples = 0

    private func consume(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel, stage: StageView) {
        consumedSamples += samples.count
        project(samples, editor: editor, stage: stage)
        updatePreview(editor: editor, stage: stage)
    }

    /// Screen samples → points on the stroke's guide (or the object it started on).
    private func project(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel, stage: StageView) {
        for sample in samples {
            guard let ray = stage.worldRay(at: sample.location) else { continue }
            let hit: SurfaceHit? = if let mesh = strokeTargetMesh {
                MeshRaycast.intersect(ray, mesh: mesh)
            } else {
                strokeGuide?.intersect(ray)
            }
            guard let hit else { continue }
            // Tubes sit on top of the surface instead of being half buried.
            let lift = editor.draw.style == .tube ? editor.draw.width * 0.5 : 0.002
            strokePoints.append(hit.point + hit.normal * lift)
            strokePressures.append(sample.pressure)
            strokeNormals.append(hit.normal)
        }
    }

    private func updatePreview(editor: EditorModel, stage: StageView) {
        guard strokePoints.count >= 2 else { return }
        let widths = strokePressures.map { editor.draw.width * (0.35 + 0.65 * $0) }
        let stroke = DrawingRecipe.Stroke(
            points: strokePoints,
            widths: editor.draw.style == .tube || editor.draw.style == .ribbon ? widths : widths.map { _ in 0.012 }
        )
        let mesh: MeshData = if editor.draw.style == .ribbon {
            DrawingMesher.ribbon(stroke, normal: strokeNormals.last ?? .unitY)
        } else {
            DrawingMesher.tube(stroke, sides: 5)
        }
        let color = editor.currentColor.resolved(in: editor.look.palette).uiColor
        stage.showStrokePreview(mesh, color: color)
    }
}

/// Watches Pencil touches for barrel roll (Apple Pencil Pro) without claiming them: other gestures
/// keep working, this one just reports how much the barrel turned.
final class PencilRollRecognizer: UIGestureRecognizer {
    var onRoll: ((Double) -> Void)?
    private var lastRoll: CGFloat?

    /// Never blocks or delays other gestures; Pencil only.
    func configure() {
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    }

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent) {
        lastRoll = touches.first?.rollAngle
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent) {
        guard let touch = touches.first else { return }
        let roll = touch.rollAngle
        if let lastRoll {
            var delta = Double(roll - lastRoll)
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            if abs(delta) > 0.0005 { onRoll?(delta) }
        }
        lastRoll = roll
    }

    override func touchesEnded(_: Set<UITouch>, with _: UIEvent) {
        lastRoll = nil
        state = .failed
    }

    override func touchesCancelled(_: Set<UITouch>, with _: UIEvent) {
        lastRoll = nil
        state = .failed
    }

    override func reset() {
        super.reset()
        lastRoll = nil
    }
}
