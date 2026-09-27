import LoweyCore
import LoweyRender
import SwiftUI

/// On-screen joystick ("editing feels like gaming"): the stick moves the selection across the
/// ground relative to the camera, the slider raises/lowers it. In rotate/scale gizmo modes the
/// stick turns / resizes instead. One gesture = one undo step.
struct JoystickPad: View {
    @Bindable var editor: EditorModel
    @State private var stick = CGSize.zero
    @State private var lift: Double = 0
    @State private var gestureKey = UUID().uuidString
    @State private var ticker = FrameTicker()
    /// Live stick values read by the per-frame step (a reference, so the ticker sees updates).
    @State private var input = JoystickInput()

    private let radius: CGFloat = 58

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            ZStack {
                Circle().fill(Theme.raised).frame(width: radius * 2, height: radius * 2)
                Circle().stroke(Theme.panelStroke, lineWidth: 1).frame(width: radius * 2, height: radius * 2)
                Image(systemName: centerIcon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .offset(y: -radius + 14)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 50, height: 50)
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
                        if stick == .zero { begin() }
                        stick = translation
                        input.x = Double(translation.width / radius)
                        input.y = Double(translation.height / radius)
                    }
                    .onEnded { _ in
                        stick = .zero
                        input.x = 0
                        input.y = 0
                        end()
                    }
            )
            .accessibilityLabel("Joystick")

            if editor.gizmoMode == .move {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.secondaryText)
                    ZStack {
                        Capsule().fill(Theme.raised).frame(width: 44, height: radius * 2 - 30)
                        Circle().fill(Theme.text).frame(width: 34, height: 34).offset(y: CGFloat(-lift) * (radius - 30))
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if lift == 0 { begin() }
                                lift = Double(max(-1, min(1, -value.translation.height / (radius - 30))))
                                if lift == 0 { lift = 0.0001 }
                                input.lift = lift
                            }
                            .onEnded { _ in
                                lift = 0
                                input.lift = 0
                                end()
                            }
                    )
                    Image(systemName: "arrow.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.secondaryText)
                }
                .accessibilityLabel("Up and down")
            }
        }
        .padding(12)
        .panelStyle(cornerRadius: 40)
        .onDisappear { ticker.stop() }
    }

    private var centerIcon: String {
        switch editor.gizmoMode {
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .rotate: "arrow.triangle.2.circlepath"
        case .scale: "arrow.up.left.and.arrow.down.right"
        }
    }

    private func begin() {
        gestureKey = UUID().uuidString
        ticker.start { step() }
    }

    private func end() {
        guard stick == .zero, lift == 0 else { return }
        ticker.stop()
        switch editor.gizmoMode {
        case .rotate: editor.snapRotation(gesture: gestureKey)
        default: editor.finishTransform(gesture: gestureKey)
        }
    }

    /// Runs every frame while the stick is held. Speed scales with camera distance.
    private func step() {
        guard let stage = editor.stage else { return }
        let dt = 1.0 / 60.0
        let x = input.x
        let y = input.y
        let lift = input.lift
        // Ease the stick response (fine control near the centre).
        let curve: (Double) -> Double = { $0 * abs($0) }
        switch editor.gizmoMode {
        case .move:
            let speed = max(stage.viewpoint.distance * 0.5, 0.4)
            let yaw = stage.viewpoint.yaw * .pi / 180
            let right = Vec3(cos(yaw), 0, -sin(yaw))
            let forward = Vec3(-sin(yaw), 0, -cos(yaw))
            var delta = (right * curve(x) + forward * -curve(y)) * speed * dt
            delta.y = curve(lift) * speed * 0.6 * dt
            if delta.lengthSquared > 1e-12 { editor.translateSelection(by: delta, gesture: gestureKey) }
        case .rotate:
            let angle = -curve(x) * 2.5 * dt
            if abs(angle) > 1e-9 { editor.rotateSelection(by: angle, axis: .y, gesture: gestureKey) }
            let tilt = curve(y) * 2.5 * dt
            if abs(tilt) > 1e-9 { editor.rotateSelection(by: tilt, axis: .x, gesture: gestureKey) }
        case .scale:
            let factor = exp(-curve(y) * 1.4 * dt + curve(x) * 1.4 * dt)
            if abs(factor - 1) > 1e-9 { editor.scaleSelection(by: Vec3(factor, factor, factor), gesture: gestureKey) }
        }
    }
}

@MainActor
final class JoystickInput {
    var x = 0.0
    var y = 0.0
    var lift = 0.0
}

/// Calls a closure every display frame while running.
@MainActor
final class FrameTicker {
    private var link: CADisplayLink?
    private var body: (() -> Void)?

    func start(_ body: @escaping () -> Void) {
        stop()
        self.body = body
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        body = nil
    }

    @objc private func tick() {
        body?()
    }
}
