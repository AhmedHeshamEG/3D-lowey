import HmmDesign
import LoweyCore
import SwiftUI

/// The on-screen flight sticks: left moves (up = forward), right looks, the slider between lifts. Record (Perform)
/// and Done sit on top. A game controller does the same with real sticks.
struct FlyPad: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(spacing: HmmSpacing.xs) {
            HStack(spacing: HmmSpacing.xs) {
                let recording = editor.performPhase == .recording
                HmmPillButton(recording ? "Stop" : "Record", systemName: recording ? "stop.fill" : "record.circle", prominent: !recording) {
                    if editor.performPhase == .recording {
                        editor.finishPerform()
                    } else {
                        editor.armPerform()
                    }
                }
                .accessibilityIdentifier("fly-record")
                HmmButton("xmark", label: "Done flying", size: 36) { editor.stopFlying() }
            }
            HStack(alignment: .center, spacing: HmmSpacing.m) {
                FlyStick(label: "Move") { vector in
                    editor.flyer.pad.strafe = vector.x
                    editor.flyer.pad.forward = -vector.y
                }
                FlyLift { amount in editor.flyer.pad.lift = amount }
                FlyStick(label: "Look") { vector in
                    editor.flyer.pad.pan = vector.x
                    editor.flyer.pad.tilt = -vector.y
                }
            }
        }
        .padding(HmmSpacing.s)
        .hmmPanelBackground(cornerRadius: 36)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fly-pad")
    }
}

/// One stick: a well and a knob; reports −1…1 on both axes (y down), springs back when let go.
private struct FlyStick: View {
    let label: String
    let changed: (SIMD2<Double>) -> Void
    @State private var offset = CGSize.zero
    @Environment(\.hmmTheme) private var theme
    static let radius: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().fill(theme.surface2.opacity(0.9)).overlay(Circle().stroke(theme.line, lineWidth: 1))
            Text(LocalizedStringKey(label)).font(.hmm(.caption, weight: .semibold)).foregroundStyle(theme.text2).offset(y: Self.radius + 10)
            Circle()
                .fill(theme.text.opacity(0.9))
                .frame(width: 40, height: 40)
                .offset(offset)
        }
        .frame(width: Self.radius * 2, height: Self.radius * 2)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                var translation = value.translation
                let length = hypot(translation.width, translation.height)
                if length > Self.radius {
                    translation = CGSize(width: translation.width / length * Self.radius, height: translation.height / length * Self.radius)
                }
                offset = translation
                changed(SIMD2(JoystickPad.response(Double(translation.width / Self.radius)),
                              JoystickPad.response(Double(translation.height / Self.radius))))
            }
            .onEnded { _ in
                withHmmAnimation(.snappy) { offset = .zero }
                changed(.zero)
            })
        .accessibilityLabel(label)
    }
}

/// The lift slider: up rises, down sinks; springs back to level.
private struct FlyLift: View {
    let changed: (Double) -> Void
    @State private var amount = 0.0
    @Environment(\.hmmTheme) private var theme
    static let travel: CGFloat = 44

    var body: some View {
        ZStack {
            Capsule().fill(theme.surface2.opacity(0.9)).frame(width: 30, height: Self.travel * 2 + 30)
            Capsule().fill(theme.text.opacity(0.9)).frame(width: 26, height: 26).offset(y: -CGFloat(amount) * Self.travel)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                amount = Double(max(-1, min(1, -value.translation.height / Self.travel)))
                changed(JoystickPad.response(amount))
            }
            .onEnded { _ in
                withHmmAnimation(.snappy) { amount = 0 }
                changed(0)
            })
        .accessibilityLabel("Up and down")
    }
}
