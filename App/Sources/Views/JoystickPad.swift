import LoweyCore
import LoweyRender
import SwiftUI

/// On-screen joystick ("editing feels like gaming"), the same layout in every gizmo mode:
/// - the stick works on the ground plane (the red X and blue Z axes, drawn in the pad as they lie from where you look):
///   Move slides the selection across the ground, Rotate tips it (up/down leans it away/towards you, left/right leans it
///   sideways), Scale grows / shrinks it;
/// - the green slider is the vertical (Y): Move raises / lowers, Rotate spins it around its vertical axis.
/// Both are analog: the further you push, the faster it goes (gently near the middle), and speed is per second, whatever
/// the screen's refresh rate. One touch = one undo step.
struct JoystickPad: View {
    @Bindable var editor: EditorModel
    @State private var stick = CGSize.zero
    @State private var slide: Double = 0
    @State private var stickHeld = false
    @State private var slideHeld = false
    @State private var gestureKey = UUID().uuidString
    @State private var ticker = FrameTicker()
    /// Live values read by the per-frame step (a reference, so the ticker sees updates).
    @State private var input = JoystickInput()
    /// The speed setting (scene menu → Joystick speed); 1 = normal.
    @AppStorage(AppSettings.joystickSpeed) private var speedSetting = 1.0

    private let radius: CGFloat = 58
    private let travel: CGFloat = 30

    // The gizmo's axis colours.
    private static let red = Color(red: 0.96, green: 0.33, blue: 0.36)
    private static let green = Color(red: 0.45, green: 0.86, blue: 0.4)
    private static let blue = Color(red: 0.35, green: 0.58, blue: 1)

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(Theme.raised).frame(width: radius * 2, height: radius * 2)
                Circle().stroke(Theme.panelStroke, lineWidth: 1).frame(width: radius * 2, height: radius * 2)
                compass
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 50, height: 50)
                    .overlay(Image(systemName: centerIcon).font(.system(size: 15, weight: .bold)).foregroundStyle(.black.opacity(0.7)))
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                    .offset(stick)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        var translation = value.translation
                        let length = hypot(translation.width, translation.height)
                        if length > radius {
                            translation = CGSize(width: translation.width / length * radius, height: translation.height / length * radius)
                        }
                        if !stickHeld {
                            stickHeld = true
                            begin()
                        }
                        stick = translation
                        input.x = Double(translation.width / radius)
                        input.y = Double(translation.height / radius)
                    }
                    .onEnded { _ in
                        stickHeld = false
                        stick = .zero
                        input.x = 0
                        input.y = 0
                        end()
                    }
            )
            .accessibilityLabel(stickLabel)

            if editor.gizmoMode != .scale {
                slider
            }
        }
        .padding(12)
        .panelStyle(cornerRadius: 40)
        .animation(.spring(duration: 0.25), value: editor.gizmoMode)
        .onDisappear { ticker.stop() }
    }

    /// The green vertical control: up / down to lift (Move), left / right to spin (Rotate).
    private var slider: some View {
        let vertical = editor.gizmoMode == .move
        let length = travel * 2 + 36
        return ZStack {
            Capsule().fill(Self.green.opacity(0.16))
                .frame(width: vertical ? 44 : length, height: vertical ? length : 44)
            Capsule().stroke(Self.green.opacity(0.45), lineWidth: 1)
                .frame(width: vertical ? 44 : length, height: vertical ? length : 44)
            Image(systemName: vertical ? "arrow.up.and.down" : "arrow.left.and.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Self.green.opacity(0.7))
            Circle().fill(Self.green).frame(width: 34, height: 34)
                .overlay(Image(systemName: vertical ? "y.circle" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.black.opacity(0.65)))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                .offset(x: vertical ? 0 : CGFloat(slide) * travel, y: vertical ? CGFloat(-slide) * travel : 0)
        }
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !slideHeld {
                        slideHeld = true
                        begin()
                    }
                    let moved = vertical ? -value.translation.height : value.translation.width
                    slide = Double(max(-1, min(1, moved / travel)))
                    input.slide = slide
                }
                .onEnded { _ in
                    slideHeld = false
                    slide = 0
                    input.slide = 0
                    end()
                }
        )
        .accessibilityLabel(vertical ? "Up and down (Y)" : "Spin (around Y)")
    }

    /// Where the red X and blue Z axes point on screen from the current view (what the stick follows).
    private var compass: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { _ in
            let yaw = (editor.stage?.viewpoint.yaw ?? 0) * .pi / 180
            let reach = radius - 10
            let xAxis = CGPoint(x: cos(yaw) * reach, y: sin(yaw) * reach)
            let zAxis = CGPoint(x: -sin(yaw) * reach, y: cos(yaw) * reach)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for (axis, color) in [(xAxis, Self.red), (zAxis, Self.blue)] {
                    var line = Path()
                    line.move(to: CGPoint(x: center.x - axis.x, y: center.y - axis.y))
                    line.addLine(to: center)
                    context.stroke(line, with: .color(color.opacity(0.25)), lineWidth: 2)
                    var positive = Path()
                    positive.move(to: center)
                    positive.addLine(to: CGPoint(x: center.x + axis.x, y: center.y + axis.y))
                    context.stroke(positive, with: .color(color.opacity(0.75)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    context.fill(Path(ellipseIn: CGRect(x: center.x + axis.x - 3.5, y: center.y + axis.y - 3.5, width: 7, height: 7)),
                                 with: .color(color))
                }
            }
            .frame(width: radius * 2, height: radius * 2)
            .allowsHitTesting(false)
        }
    }

    private var centerIcon: String {
        switch editor.gizmoMode {
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .rotate: "rotate.3d"
        case .scale: "arrow.up.left.and.arrow.down.right"
        }
    }

    private var stickLabel: String {
        switch editor.gizmoMode {
        case .move: "Move across the ground (X and Z)"
        case .rotate: "Tilt (around X and Z)"
        case .scale: "Size"
        }
    }

    private func begin() {
        // Both controls held together are one gesture (one undo step).
        guard !(stickHeld && slideHeld) else { return }
        gestureKey = UUID().uuidString
        input.lastTimestamp = nil
        input.speed = min(max(speedSetting, AppSettings.joystickSpeedRange.lowerBound), AppSettings.joystickSpeedRange.upperBound)
        ticker.start { timestamp in step(at: timestamp) }
    }

    private func end() {
        guard !stickHeld, !slideHeld else { return }
        ticker.stop()
        switch editor.gizmoMode {
        // Analog to the end: no jump to a snap step when you let go.
        case .rotate: editor.endGesture()
        default: editor.finishTransform(gesture: gestureKey)
        }
    }

    /// Soft centre, full speed at the rim: a small dead zone, then a curve that is gentle near the middle.
    static func response(_ value: Double) -> Double {
        let magnitude = abs(value)
        guard magnitude > 0.06 else { return 0 }
        let t = min((magnitude - 0.06) / 0.94, 1)
        return (value < 0 ? -1 : 1) * (0.25 * t + 0.75 * t * t * t)
    }

    /// The world axis (and its direction) closest to a horizontal direction.
    static func nearestAxis(_ direction: Vec3) -> (CoreAxis, Double) {
        abs(direction.x) >= abs(direction.z) ? (.x, direction.x < 0 ? -1 : 1) : (.z, direction.z < 0 ? -1 : 1)
    }

    /// Runs every frame while a control is held. Speeds are per second (real frame time).
    private func step(at timestamp: CFTimeInterval) {
        guard let stage = editor.stage else { return }
        let dt = input.lastTimestamp.map { min(max(timestamp - $0, 0), 0.05) } ?? 1.0 / 60.0
        input.lastTimestamp = timestamp
        let x = Self.response(input.x)
        let y = Self.response(input.y)
        let slide = Self.response(input.slide)
        let yaw = stage.viewpoint.yaw * .pi / 180
        let right = Vec3(cos(yaw), 0, -sin(yaw))
        let forward = Vec3(-sin(yaw), 0, -cos(yaw))
        switch editor.gizmoMode {
        case .move:
            let speed = max(stage.viewpoint.distance * 0.3, 0.2) * input.speed
            var delta = (right * x + forward * -y) * speed * dt
            delta.y = slide * speed * 0.6 * dt
            if delta.lengthSquared > 1e-12 { editor.translateSelection(by: delta, gesture: gestureKey) }
        case .rotate:
            // Up to about 80° a second at the rim (normal speed).
            let speed = 0.45 * Double.pi * input.speed * dt
            // Stick up leans the top away from you (about the axis to your right), right leans it right (about the
            // axis you look along). Real X / Z axes, so the numbers in the inspector stay clean.
            let (pitchAxis, pitchSign) = Self.nearestAxis(right)
            let (rollAxis, rollSign) = Self.nearestAxis(forward)
            if y != 0 { editor.rotateSelection(by: y * speed * pitchSign, axis: pitchAxis, gesture: gestureKey) }
            if x != 0 { editor.rotateSelection(by: x * speed * rollSign, axis: rollAxis, gesture: gestureKey) }
            // Slider right: the side facing you turns to the right.
            if slide != 0 { editor.rotateSelection(by: slide * speed, axis: .y, gesture: gestureKey) }
        case .scale:
            let factor = exp((-y + x) * 0.6 * input.speed * dt)
            if abs(factor - 1) > 1e-9 { editor.scaleSelection(by: Vec3(factor, factor, factor), gesture: gestureKey) }
        }
    }
}

@MainActor
final class JoystickInput {
    var x = 0.0
    var y = 0.0
    var slide = 0.0
    var lastTimestamp: CFTimeInterval?
    var speed = 1.0
}

/// Calls a closure every display frame while running, with the frame's timestamp.
@MainActor
final class FrameTicker {
    private var link: CADisplayLink?
    private var body: ((CFTimeInterval) -> Void)?

    func start(_ body: @escaping (CFTimeInterval) -> Void) {
        stop()
        self.body = body
        let link = CADisplayLink(target: self, selector: #selector(tick))
        // Every step is an edit; 60 a second is smooth and leaves the rest of the frame to the stage.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        body = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        body?(link.timestamp)
    }
}
