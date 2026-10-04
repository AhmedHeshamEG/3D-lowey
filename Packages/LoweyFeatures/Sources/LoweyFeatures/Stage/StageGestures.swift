import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit.UIGestureRecognizerSubclass

/// Turns touches on the stage into camera moves and edits. Fingers navigate (one finger orbits, two pan and pinch),
/// taps select, a drag on the selection moves it, the gizmo's handles move / turn / size, two fingers on the
/// selection twist and pinch it, the Pencil paints with a painting tool. The universal taps (undo, redo, hide the
/// chrome) belong to the window's gesture layer, not to the stage.
@MainActor
final class StageGestures: NSObject, UIGestureRecognizerDelegate {
    weak var editor: EditorModel?
    weak var stage: StageView?

    let tap = UITapGestureRecognizer()
    let doubleTap = UITapGestureRecognizer()
    let oneFingerPan = UIPanGestureRecognizer()
    let twoFingerPan = UIPanGestureRecognizer()
    let pinch = UIPinchGestureRecognizer()
    let longPress = UILongPressGestureRecognizer()
    let stroke = StrokeGestureRecognizer()
    let twist = UIRotationGestureRecognizer()
    let pencilRoll = PencilRollRecognizer()
    let hover = UIHoverGestureRecognizer()

    /// What the current one-finger drag does.
    enum DragKind {
        case orbit
        case moveObjects(planeY: Double, last: Vec3)
        case gizmo(GizmoHandle, pivot: Vec3, lastPoint: CGPoint, accumulated: Double)
        case turn(RingDrag)
        case lasso
        case scatter(center: Vec3)
        case perform(planeY: Double, last: Vec3)
        case aimCamera
        case moveOverlay(ObjectID, last: CGPoint)
        /// Dragging a dot of the motion path (its position key at that time).
        case pathKey(time: Double)
        /// Dragging a character's hand or foot.
        case ik(IKHandle)
        case none
    }

    /// One drag on a rotate ring: pivot and grab fixed for the whole drag; `applied` is what was turned so far.
    struct RingDrag {
        var axis: CoreAxis
        var pivot: Vec3
        var start: CGPoint
        /// The ring's screen direction where it was grabbed (turning forwards), and its radius on screen.
        var tangent: CGVector
        var radius: CGFloat
        /// Seen face-on enough to turn by circling the pivot; edge-on, by sliding along the ring.
        var circular: Bool
        var total: Double = 0
        var applied: Double = 0
    }

    var drag: DragKind = .none
    var gestureKey = UUID().uuidString
    var twistKey = UUID().uuidString
    var pinchKey = UUID().uuidString
    var panKey = UUID().uuidString
    var scatterRadius: Double = 0
    /// Two fingers that landed on the selection hold it (twist turns, pinch sizes) instead of moving the camera.
    var twoFingerOnSelection: Bool?
    var twoFingerActive = Set<ObjectIdentifier>()
    var twoFingerRotation: (pivot: Vec3, total: Double, applied: Double)?
    var strokeGuide: GuideSurface?
    var strokeTargetMesh: MeshData?
    var strokePoints: [Vec3] = []
    var strokePressures: [Double] = []
    var strokeNormals: [Vec3] = []
    var consumedSamples = 0
    /// The shape a held stroke snapped to, where the tip was then, and the stroke's pressure.
    var snapped: (shape: QuickShape.Result, anchor: CGPoint, pressure: Double)?
    /// The Shadow Brush's target and its world mesh (raycast on the CPU for every sample).
    var brushTarget: (id: ObjectID, mesh: MeshData)?
    /// Ink ▸ Erase / Select: the Pencil's path, and where a drag of picked strokes was last.
    var inkPath: [CGPoint] = []
    var inkDragLast: CGPoint?

    /// How far orbit, pan and zoom go per finger movement (Settings ▸ Speed).
    var navigationSpeed: Double { AppSettings.navigationFactor }

    init(editor: EditorModel, stage: StageView) {
        self.editor = editor
        self.stage = stage
        super.init()
        install(on: stage)
    }

    private func install(on stage: StageView) {
        tap.addTarget(self, action: #selector(handleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.addTarget(self, action: #selector(handleDoubleTap(_:)))
        tap.require(toFail: doubleTap)
        oneFingerPan.maximumNumberOfTouches = 1
        oneFingerPan.addTarget(self, action: #selector(handleOneFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.addTarget(self, action: #selector(handleTwoFingerPan(_:)))
        pinch.addTarget(self, action: #selector(handlePinch(_:)))
        longPress.minimumPressDuration = 0.45
        longPress.addTarget(self, action: #selector(handleLongPress(_:)))
        stroke.addTarget(self, action: #selector(handleStroke(_:)))
        stroke.onHold = { [weak self] in self?.snapToQuickShape() }
        twist.addTarget(self, action: #selector(handleTwist(_:)))
        hover.addTarget(self, action: #selector(handleHover(_:)))
        pencilRoll.configure()
        pencilRoll.onRoll = { [weak self] delta in self?.handlePencilRoll(delta) }
        let all: [UIGestureRecognizer] = [tap, doubleTap, oneFingerPan, twoFingerPan, pinch, longPress, stroke, twist, pencilRoll, hover]
        for recognizer in all {
            recognizer.delegate = self
            stage.addGestureRecognizer(recognizer)
        }
        updateTouchTypes()
    }

    /// The Pencil paints with a painting tool; fingers keep navigating (unless "draw with a finger" is on).
    func updateTouchTypes() {
        guard let editor else { return }
        let painting = editor.tool.paints
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        let finger = NSNumber(value: UITouch.TouchType.direct.rawValue)
        stroke.isEnabled = painting
        if painting {
            let erasing = (editor.tool == .ink && editor.ink.mode != .draw) || (editor.tool == .flipbook && editor.flipbook.mode == .erase)
            let pencilOnly = editor.tool == .shadowBrush || erasing || editor.draw.pencilOnly
            stroke.allowedTouchTypes = pencilOnly ? [pencil] : [pencil, finger]
            oneFingerPan.allowedTouchTypes = pencilOnly ? [finger] : []
            oneFingerPan.isEnabled = pencilOnly
        } else {
            oneFingerPan.isEnabled = true
            oneFingerPan.allowedTouchTypes = [finger, pencil]
        }
    }

    // MARK: Delegate

    func gestureRecognizer(_ first: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith second: UIGestureRecognizer) -> Bool {
        if first === pencilRoll || second === pencilRoll || first === hover || second === hover { return true }
        let pair: Set<ObjectIdentifier> = [ObjectIdentifier(first), ObjectIdentifier(second)]
        let twoFinger: Set<ObjectIdentifier> = [ObjectIdentifier(twoFingerPan), ObjectIdentifier(pinch), ObjectIdentifier(twist)]
        return pair.isSubset(of: twoFinger)
    }

    /// Recording a performance of objects (a flown camera goes through the camera gestures instead).
    var isRecordingPerform: Bool {
        guard let editor else { return false }
        return editor.performPhase == .recording && !editor.performTargets.isEmpty && !operatesCamera
    }

    /// The Director view with the shot camera selected (or nothing selected): gestures operate that camera.
    var operatesCamera: Bool {
        guard let editor, editor.directorView, let camera = editor.editedCamera else { return false }
        return editor.selection.isEmpty || editor.selection == [camera]
    }

    // MARK: Pencil hover

    /// The setting rules every tool: off, there is no mark at all; on, a point under the tip (Pencil only: a trackpad
    /// pointer has no height and gets the system's own pointer).
    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        guard let editor else { return }
        guard UserDefaults.standard.bool(forKey: AppSettings.pencilHoverPreview) else {
            if editor.hoverPoint != nil { editor.setHover(nil) }
            return
        }
        let hovering = (recognizer.state == .began || recognizer.state == .changed) && recognizer.zOffset > 0
        editor.setHover(hovering ? recognizer.location(in: stage) : nil)
    }

    // MARK: Taps

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let editor, let stage else { return }
        let point = recognizer.location(in: stage)
        editor.showChrome()
        if !editor.pickActive, !editor.tool.paints, let overlay = editor.overlayHit(at: point) {
            editor.select(overlay)
            return
        }
        let picked = stage.pickObject(at: point)
        if editor.pickActive {
            if let (id, _) = picked { editor.pick(object: id) }
            return
        }
        editor.select(picked?.0)
        editor.refreshGuide()
    }

    @objc private func handleDoubleTap(_: UITapGestureRecognizer) {
        editor?.frameSelection()
    }

    /// Touch and hold: add to (or take out of) the selection.
    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let editor, let stage else { return }
        if let (id, _) = stage.pickObject(at: recognizer.location(in: stage)) {
            editor.select(id, additive: true)
            HmmHaptics.play(.selection)
        }
    }

    /// Apple Pencil Pro barrel roll turns the performed object while it moves.
    func handlePencilRoll(_ delta: Double) {
        guard let editor, isRecordingPerform, editor.performSettings.barrelRoll else { return }
        if !editor.performChannels.contains(where: { $0.property == .rotation }) { editor.performTouchBegan([.rotation]) }
        editor.performRotate(by: -delta)
    }
}

/// Watches Pencil touches for barrel roll (Apple Pencil Pro) without claiming them.
final class PencilRollRecognizer: UIGestureRecognizer {
    var onRoll: ((Double) -> Void)?
    private var lastRoll: CGFloat?

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
