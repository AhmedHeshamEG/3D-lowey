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
    @State private var atStickRim = false
    @State private var gestureKey = UUID().uuidString
    @State private var ticker = FrameTicker()
    /// Live values read by the per-frame step (a reference, so the ticker sees updates).
    @State private var input = JoystickInput()
    /// The speed setting (scene menu → Joystick speed); 1 = normal.
    @AppStorage(AppSettings.joystickSpeed) private var speedSetting = 1.0

    private let radius: CGFloat = 60
    private let travel: CGFloat = 30

    // The gizmo's axis colours.
    private static let red = Color(red: 0.96, green: 0.33, blue: 0.36)
    private static let green = Color(red: 0.45, green: 0.86, blue: 0.4)
    private static let blue = Color(red: 0.35, green: 0.58, blue: 1)

    var body: some View {
        VStack(spacing: 8) {
            header
            HStack(alignment: .center, spacing: 14) {
                stickView
                if editor.gizmoMode != .scale {
                    slider
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .panelStyle(cornerRadius: 36)
        .animation(.spring(duration: 0.3, bounce: 0.25), value: editor.gizmoMode)
        .onDisappear { ticker.stop() }
    }

    /// What the pad does now, and the speed when it isn't normal.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: centerIcon).font(.system(size: 10, weight: .bold))
            Text(modeTitle).font(.system(size: 11, weight: .heavy)).tracking(1.2)
            if abs(speedSetting - 1) > 0.01 {
                Text(String(format: "%.2g×", speedSetting))
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.raisedStrong))
            }
        }
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity)
    }

    private var modeTitle: String {
        switch editor.gizmoMode {
        case .move: "MOVE"
        case .rotate: "TURN"
        case .scale: "SIZE"
        }
    }

    /// How hard the stick is pushed, 0…1.
    private var push: CGFloat {
        min(hypot(stick.width, stick.height) / radius, 1)
    }

    private var stickView: some View {
        ZStack {
            // The well: darker in the middle, a lit rim, tick marks every 30°.
            Circle()
                .fill(RadialGradient(colors: [Color.black.opacity(0.35), Color.white.opacity(0.06)], center: .center,
                                     startRadius: 4, endRadius: radius))
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
            ticks
            compass
            if stickHeld, push > 0.06 {
                pushIndicator
            }
            knob
        }
        .frame(width: radius * 2, height: radius * 2)
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
                        Haptics.tap()
                        begin()
                    }
                    // A soft tick when you reach full speed.
                    let atRim = length >= radius * 0.98
                    if atRim, !atStickRim { Haptics.select() }
                    atStickRim = atRim
                    stick = translation
                    input.x = Double(translation.width / radius)
                    input.y = Double(translation.height / radius)
                }
                .onEnded { _ in
                    stickHeld = false
                    atStickRim = false
                    withAnimation(.spring(duration: 0.3, bounce: 0.45)) { stick = .zero }
                    input.x = 0
                    input.y = 0
                    end()
                }
        )
        .accessibilityLabel(stickLabel)
    }

    private var ticks: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for index in 0 ..< 12 {
                let angle = Double(index) / 12 * 2 * .pi
                let outer = radius - 3
                let inner = radius - (index % 3 == 0 ? 9 : 6)
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                tick.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                context.stroke(tick, with: .color(.white.opacity(0.18)), lineWidth: 1.2)
            }
            // The soft centre (dead zone).
            context.stroke(Path(ellipseIn: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)),
                           with: .color(.white.opacity(0.1)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    /// The rim lights up where you push (brighter the harder), with a line from the centre to the knob.
    private var pushIndicator: some View {
        let heading = Angle(radians: atan2(Double(stick.height), Double(stick.width)))
        return ZStack {
            Circle()
                .trim(from: 0, to: 0.16)
                .stroke(Theme.accent.opacity(0.35 + 0.6 * push), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(heading - .degrees(0.16 * 180))
                .padding(2)
            Path { path in
                path.move(to: CGPoint(x: radius, y: radius))
                path.addLine(to: CGPoint(x: radius + stick.width, y: radius + stick.height))
            }
            .stroke(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        .frame(width: radius * 2, height: radius * 2)
        .allowsHitTesting(false)
    }

    private var knob: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.83, blue: 0.5), Theme.accent, Color(red: 0.93, green: 0.58, blue: 0.16)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1).padding(1))
            .overlay(
                // A glossy highlight.
                Ellipse().fill(Color.white.opacity(0.35)).frame(width: 26, height: 12).offset(y: -13).blur(radius: 2)
            )
            .overlay(Image(systemName: centerIcon).font(.system(size: 15, weight: .bold)).foregroundStyle(.black.opacity(0.7)))
            .frame(width: 52, height: 52)
            .scaleEffect(stickHeld ? 1.08 : 1)
            .shadow(color: .black.opacity(0.45), radius: stickHeld ? 10 : 6, y: stickHeld ? 5 : 3)
            .shadow(color: Theme.accent.opacity(stickHeld ? 0.5 * push : 0), radius: 12)
            .offset(stick)
            .animation(.spring(duration: 0.2), value: stickHeld)
            .allowsHitTesting(false)
    }

    /// The green vertical control: up / down to lift (Move), left / right to spin (Rotate).
    private var slider: some View {
        let vertical = editor.gizmoMode == .move
        let length = travel * 2 + 40
        let thickness: CGFloat = 46
        let amount = CGFloat(slide) * travel
        return ZStack {
            Capsule().fill(Self.green.opacity(0.14))
            Capsule().stroke(Self.green.opacity(slideHeld ? 0.7 : 0.4), lineWidth: 1)
            // Centre notch and the two directions.
            Capsule().fill(Self.green.opacity(0.5)).frame(width: vertical ? 16 : 2, height: vertical ? 2 : 16)
            Image(systemName: vertical ? "chevron.up" : "chevron.right")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Self.green.opacity(0.6))
                .offset(x: vertical ? 0 : length / 2 - 12, y: vertical ? -length / 2 + 12 : 0)
            Image(systemName: vertical ? "chevron.down" : "chevron.left")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Self.green.opacity(0.6))
                .offset(x: vertical ? 0 : -length / 2 + 12, y: vertical ? length / 2 - 12 : 0)
            // How far it's pushed: a green fill from the centre.
            Capsule()
                .fill(Self.green.opacity(0.4))
                .frame(width: vertical ? 8 : abs(amount), height: vertical ? abs(amount) : 8)
                .offset(x: vertical ? 0 : amount / 2, y: vertical ? -amount / 2 : 0)
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.65, green: 0.95, blue: 0.6), Self.green], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1).padding(1))
                .overlay {
                    if vertical {
                        Text("Y").font(.system(size: 13, weight: .heavy)).foregroundStyle(.black.opacity(0.6))
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black.opacity(0.6))
                    }
                }
                .frame(width: 36, height: 36)
                .scaleEffect(slideHeld ? 1.1 : 1)
                .shadow(color: .black.opacity(0.4), radius: slideHeld ? 7 : 4, y: 2)
                .offset(x: vertical ? 0 : amount, y: vertical ? -amount : 0)
                .animation(.spring(duration: 0.2), value: slideHeld)
        }
        .frame(width: vertical ? thickness : length, height: vertical ? length : thickness)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !slideHeld {
                        slideHeld = true
                        Haptics.tap()
                        begin()
                    }
                    let moved = vertical ? -value.translation.height : value.translation.width
                    slide = Double(max(-1, min(1, moved / travel)))
                    input.slide = slide
                }
                .onEnded { _ in
                    slideHeld = false
                    withAnimation(.spring(duration: 0.3, bounce: 0.45)) { slide = 0 }
                    input.slide = 0
                    end()
                }
        )
        .accessibilityLabel(vertical ? "Up and down (Y)" : "Spin (around Y)")
    }

    /// Where the red X and blue Z axes point on screen from the current view (what the stick follows). It turns with
    /// the view as you orbit.
    private var compass: some View {
        let yaw = editor.viewYaw * .pi / 180
        let reach = radius - 14
        let xAxis = CGPoint(x: cos(yaw) * reach, y: sin(yaw) * reach)
        let zAxis = CGPoint(x: -sin(yaw) * reach, y: cos(yaw) * reach)
        return ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for (axis, color) in [(xAxis, Self.red), (zAxis, Self.blue)] {
                    var line = Path()
                    line.move(to: CGPoint(x: center.x - axis.x, y: center.y - axis.y))
                    line.addLine(to: center)
                    context.stroke(line, with: .color(color.opacity(0.22)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4]))
                    var positive = Path()
                    positive.move(to: center)
                    positive.addLine(to: CGPoint(x: center.x + axis.x, y: center.y + axis.y))
                    context.stroke(positive, with: .color(color.opacity(0.75)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
            // The axis names at the positive ends.
            axisBadge("X", color: Self.red).offset(x: xAxis.x, y: xAxis.y)
            axisBadge("Z", color: Self.blue).offset(x: zAxis.x, y: zAxis.y)
        }
        .frame(width: radius * 2, height: radius * 2)
        .allowsHitTesting(false)
    }

    private func axisBadge(_ name: String, color: Color) -> some View {
        Text(name)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.black.opacity(0.75))
            .frame(width: 15, height: 15)
            .background(Circle().fill(color))
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
