import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// The optional on-screen joystick under a selection, the same layout for every gizmo mode: the stick works on the
/// ground (X and Z as they lie from where you look) — Move slides, Turn tips, Size grows; the green slider is the
/// vertical — Move lifts, Turn spins. Analog: the further you push, the faster (per second, whatever the refresh
/// rate). One touch is one undo step.
struct JoystickPad: View {
    @Bindable var editor: EditorModel
    @State private var stick = CGSize.zero
    @State private var slide: Double = 0
    @State private var stickHeld = false
    @State private var slideHeld = false
    @State private var gestureKey = UUID().uuidString
    @State private var ticker = PlaybackClock()
    @State private var input = JoystickInput()
    @Environment(\.hmmTheme) private var theme

    static let radius: CGFloat = 56
    static let travel: CGFloat = 30
    static let green = Color(red: 0.45, green: 0.86, blue: 0.4)

    var body: some View {
        HStack(alignment: .center, spacing: HmmSpacing.s) {
            JoystickWell(stick: stick, held: stickHeld, yaw: editor.viewYaw, mode: editor.gizmoMode)
                .gesture(stickGesture)
                .accessibilityLabel(editor.gizmoMode == .scale ? "Size" : (editor.gizmoMode == .move ? "Move across the ground" : "Tilt"))
            if editor.gizmoMode != .scale {
                JoystickSlider(amount: slide, held: slideHeld, vertical: editor.gizmoMode == .move)
                    .gesture(slideGesture)
                    .accessibilityLabel(editor.gizmoMode == .move ? "Up and down" : "Spin")
            }
        }
        .padding(HmmSpacing.s)
        .hmmPanelBackground(cornerRadius: 36)
        .onDisappear { ticker.stop() }
    }

    private var stickGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var translation = value.translation
                let length = hypot(translation.width, translation.height)
                if length > Self.radius {
                    translation = CGSize(width: translation.width / length * Self.radius, height: translation.height / length * Self.radius)
                }
                if !stickHeld {
                    stickHeld = true
                    HmmHaptics.play(.selection)
                    begin()
                }
                stick = translation
                input.x = Double(translation.width / Self.radius)
                input.y = Double(translation.height / Self.radius)
            }
            .onEnded { _ in
                stickHeld = false
                withHmmAnimation(.snappy) { stick = .zero }
                input.x = 0
                input.y = 0
                end()
            }
    }

    private var slideGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !slideHeld {
                    slideHeld = true
                    HmmHaptics.play(.selection)
                    begin()
                }
                let moved = editor.gizmoMode == .move ? -value.translation.height : value.translation.width
                slide = Double(max(-1, min(1, moved / Self.travel)))
                input.slide = slide
            }
            .onEnded { _ in
                slideHeld = false
                withHmmAnimation(.snappy) { slide = 0 }
                input.slide = 0
                end()
            }
    }

    private func begin() {
        guard !(stickHeld && slideHeld) else { return }
        gestureKey = UUID().uuidString
        input.speed = AppSettings.joystickFactor
        ticker.preferred = 60
        ticker.onTick = { dt in step(dt: dt) }
        ticker.start()
    }

    private func end() {
        guard !stickHeld, !slideHeld else { return }
        ticker.stop()
        if editor.gizmoMode == .rotate { editor.endGesture() } else { editor.finishTransform(gesture: gestureKey) }
    }

    /// A small dead zone, then a curve gentle near the middle and full speed at the rim.
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

    private func step(dt rawDelta: Double) {
        guard let stage = editor.stage else { return }
        let dt = rawDelta > 0 ? min(rawDelta, 0.05) : 1.0 / 60
        let x = Self.response(input.x), y = Self.response(input.y), slide = Self.response(input.slide)
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
            let speed = 0.45 * Double.pi * input.speed * dt
            let (pitchAxis, pitchSign) = Self.nearestAxis(right)
            let (rollAxis, rollSign) = Self.nearestAxis(forward)
            if y != 0 { editor.rotateSelection(by: y * speed * pitchSign, axis: pitchAxis, gesture: gestureKey) }
            if x != 0 { editor.rotateSelection(by: x * speed * rollSign, axis: rollAxis, gesture: gestureKey) }
            if slide != 0 { editor.rotateSelection(by: slide * speed, axis: .y, gesture: gestureKey) }
        case .scale:
            let factor = exp((-y + x) * 0.6 * input.speed * dt)
            if abs(factor - 1) > 1e-9 { editor.scaleSelection(by: Vec3(factor, factor, factor), gesture: gestureKey) }
        }
    }
}

/// Live stick values read by the per-frame step.
@MainActor
final class JoystickInput {
    var x = 0.0
    var y = 0.0
    var slide = 0.0
    var speed = 1.0
}

/// The stick's well: tick marks, the X / Z compass turning with the view, the knob.
private struct JoystickWell: View {
    let stick: CGSize
    let held: Bool
    let yaw: Double
    let mode: GizmoMode
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let radius = JoystickPad.radius
        ZStack {
            Circle().fill(RadialGradient(colors: [.black.opacity(0.35), .white.opacity(0.06)], center: .center, startRadius: 4, endRadius: radius))
            Circle().stroke(theme.line, lineWidth: 1)
            compass(radius: radius)
            Circle()
                .fill(theme.accent)
                .overlay(Image(systemName: mode.systemImage).font(.system(size: 14, weight: .bold)).foregroundStyle(theme.onAccent))
                .frame(width: 50, height: 50)
                .scaleEffect(held ? 1.08 : 1)
                .offset(stick)
        }
        .frame(width: radius * 2, height: radius * 2)
        .contentShape(Circle())
    }

    private func compass(radius: CGFloat) -> some View {
        let angle = yaw * .pi / 180
        let reach = radius - 14
        let xAxis = CGPoint(x: cos(angle) * reach, y: sin(angle) * reach)
        let zAxis = CGPoint(x: -sin(angle) * reach, y: cos(angle) * reach)
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for (axis, color) in [(xAxis, Color(red: 0.96, green: 0.33, blue: 0.36)), (zAxis, Color(red: 0.35, green: 0.58, blue: 1))] {
                var line = Path()
                line.move(to: center)
                line.addLine(to: CGPoint(x: center.x + axis.x, y: center.y + axis.y))
                context.stroke(line, with: .color(color.opacity(0.75)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .allowsHitTesting(false)
    }
}

/// The green vertical (lift) or spin slider.
private struct JoystickSlider: View {
    let amount: Double
    let held: Bool
    let vertical: Bool

    var body: some View {
        let length = JoystickPad.travel * 2 + 40
        let offset = CGFloat(amount) * JoystickPad.travel
        ZStack {
            Capsule().fill(JoystickPad.green.opacity(0.14))
            Capsule().stroke(JoystickPad.green.opacity(held ? 0.7 : 0.4), lineWidth: 1)
            Circle()
                .fill(JoystickPad.green)
                .overlay(Text(vertical ? "Y" : "↻").font(.system(size: 13, weight: .heavy)).foregroundStyle(.black.opacity(0.6)))
                .frame(width: 36, height: 36)
                .scaleEffect(held ? 1.1 : 1)
                .offset(x: vertical ? 0 : offset, y: vertical ? -offset : 0)
        }
        .frame(width: vertical ? 46 : length, height: vertical ? length : 46)
        .contentShape(Capsule())
    }
}
