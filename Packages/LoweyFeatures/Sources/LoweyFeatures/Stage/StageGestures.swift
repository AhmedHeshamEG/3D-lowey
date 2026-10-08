import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit.UIGestureRecognizerSubclass

/// Turns touches on the stage into camera moves and edits. Fingers navigate (one finger orbits, two pan and pinch),
/// taps select, a drag on the selection moves it, the gizmo's handles move / turn / size, two fingers on the
/// selection twist and pinch it. With a making tool, Pencil or hand is automatic (CONTEXT §4.4): the Pencil makes;
/// a finger makes too until a Pencil has touched this iPad (or when Settings says so), and then only where there is
/// something to make on, so it still orbits everywhere else. The universal taps (undo, redo, hide the chrome)
/// belong to the window's gesture layer, not to the stage.
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

    /// A finger held still on an object with the Select tool: its menu (CONTEXT §4.1). A finger that moves is a drag.
    private lazy var holdMenu = HmmHoldMenuInteraction { [weak self] point in self?.editor?.stageHoldMenu(at: point) }

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
        /// Pulling the picked face or sketch region along its normal; `grab` is where on the axis the drag began.
        case pushPull(PullAxis, grab: Double)
        /// A Pencil loop around faces, edges or corners.
        case modelLasso
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
    var strokeAltitudes: [Double?] = []
    var strokeTimes: [Double] = []
    /// The stroke's jitter seed, chosen when it starts: the live stroke and the kept one stamp the same.
    var strokeSeed: UInt64 = 0
    /// A flipbook stroke's samples in stage points.
    var flipSamples: [BrushInput<Vec2>] = []
    var consumedSamples = 0
    /// The shape a held stroke snapped to, where the tip was then, and the stroke's pressure.
    var snapped: (shape: QuickShape.Result, anchor: CGPoint, pressure: Double)?
    /// The Shadow Brush's target and its world mesh (raycast on the CPU for every sample).
    var brushTarget: (id: ObjectID, mesh: MeshData)?
    /// Paint ▸ Colour: the object and layer the stroke paints, and the stroke's number.
    var paintStroke: (object: ObjectID, layer: String, number: Int)?
    /// Ink ▸ Erase / Select: the Pencil's path, and where a drag of picked strokes was last.
    var inkPath: [CGPoint] = []
    var inkDragLast: CGPoint?
    /// The kind of touch that started the current one-finger drag (a Pencil loops, a finger orbits).
    var panTouchIsPencil = false

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
        holdMenu.install(on: stage)
        updateTouchTypes()
    }

    /// With a making tool both the Pencil and fingers may reach the stroke; `shouldReceive` decides touch by touch
    /// (Pencil or hand). Otherwise one finger or the Pencil drags.
    func updateTouchTypes() {
        guard let editor else { return }
        let painting = editor.tool.paints
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        let finger = NSNumber(value: UITouch.TouchType.direct.rawValue)
        // With the Select tool a hold is the object's menu; the other tools keep hold-to-add.
        longPress.isEnabled = editor.tool != .select
        stroke.isEnabled = painting
        if painting {
            stroke.allowedTouchTypes = [pencil, finger]
            oneFingerPan.allowedTouchTypes = [finger]
            oneFingerPan.isEnabled = true
        } else {
            oneFingerPan.isEnabled = true
            oneFingerPan.allowedTouchTypes = [finger, pencil]
        }
    }

    // MARK: Delegate

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.type == .pencil { notePencil() }
        if recognizer === oneFingerPan { panTouchIsPencil = touch.type == .pencil }
        guard let editor, editor.tool.paints, touch.type == .direct, recognizer === stroke || recognizer === oneFingerPan else { return true }
        // A finger with a making tool: it makes, or it orbits. Never both.
        let makes = fingerMakes(at: touch.location(in: stage))
        return recognizer === stroke ? makes : !makes
    }

    // MARK: Pencil or hand

    /// Who makes right now (read fresh: Settings can change it while the stage is up).
    var pencilOrHand: HmmPencilOrHand { HmmPencilOrHand(defaults: .standard) }

    /// A Pencil touched (or hovered over) the stage: from now on fingers move the view.
    func notePencil() {
        var input = pencilOrHand
        if input.pencilTouched() { input.save(to: .standard) }
    }

    /// A finger landing here would make something with the tool in the hand: fingers may make, and there is something
    /// under it to make on (an object to paint or rig, the guide to draw on). Anywhere else it orbits.
    func fingerMakes(at point: CGPoint) -> Bool {
        guard let editor, let stage, pencilOrHand.fingerMakes else { return false }
        switch editor.tool {
        case .paint, .shadowBrush, .rig:
            return stage.pickObject(at: point) != nil
        case .ink where editor.ink.mode != .draw:
            // Erasing and picking strokes: they can be anywhere.
            return true
        case .ink, .draw:
            if editor.draw.guide == .object { return stage.pickObject(at: point) != nil }
            guard let ray = stage.worldRay(at: point), let guide = editor.currentGuide else { return false }
            return guide.intersect(ray) != nil
        default:
            // The flipbook's page is the whole frame.
            return true
        }
    }

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
        if hovering { notePencil() }
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
        if editor.tool == .model, !editor.pickActive {
            editor.modelTap(at: point)
            return
        }
        if editor.tool == .paint, !editor.pickActive {
            editor.paintTap(at: point)
            return
        }
        if editor.tool == .rig, editor.rigging.person != nil {
            editor.personTap(at: point)
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

    /// Touch and hold with a tool other than Select: add to (or take out of) the selection, or the Model tool's pick.
    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let editor, let stage else { return }
        if editor.tool == .model, editor.modeling.mode.pickMode != nil {
            editor.pickElement(at: recognizer.location(in: stage), additive: true)
            return
        }
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
