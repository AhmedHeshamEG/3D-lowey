import LoweyCore
import Observation
import SwiftUI

/// What the face preview shows (Character Animator's Camera & Microphone panel): the camera, the tracking dots and
/// bones, whether a face is found. Separate from the editor so a camera frame redraws only this little panel.
@Observable
@MainActor
final class FaceMonitor {
    var picture: CGImage?
    var dots: [CGPoint] = []
    var bones: [(CGPoint, CGPoint)] = []
    var faceFound = false
    /// Hands the tracker sees (0…1 how raised), for the little meters.
    var leftHand: Double = 0
    var rightHand: Double = 0
    var source = "Camera"

    func clear() {
        picture = nil
        dots = []
        bones = []
        faceFound = false
        leftHand = 0
        rightHand = 0
    }
}

/// A small floating camera preview over the stage while you perform with your face: the picture, green dots on the
/// face, lines on the shoulders and arms, Set rest pose, and stop.
struct FacePreviewPanel: View {
    let editor: EditorModel
    let monitor: FaceMonitor
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let picture = monitor.picture {
                    Image(decorative: picture, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(Color.black.opacity(0.6))
                    Image(systemName: "camera").font(.system(size: 22)).foregroundStyle(Theme.secondaryText)
                }
                Canvas { context, size in
                    for (a, b) in monitor.bones {
                        var path = Path()
                        path.move(to: CGPoint(x: a.x * size.width, y: a.y * size.height))
                        path.addLine(to: CGPoint(x: b.x * size.width, y: b.y * size.height))
                        context.stroke(path, with: .color(Theme.accent.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    for dot in monitor.dots {
                        let rect = CGRect(x: dot.x * size.width - 1.5, y: dot.y * size.height - 1.5, width: 3, height: 3)
                        context.fill(Path(ellipseIn: rect), with: .color(Color.green.opacity(0.9)))
                    }
                }
            }
            .frame(width: 208, height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topLeading) {
                Label(monitor.faceFound ? monitor.source : "No face", systemImage: monitor.faceFound ? "face.smiling" : "face.dashed")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .foregroundStyle(monitor.faceFound ? Color.white : Color.yellow)
                    .padding(6)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 6) {
                    HandMeter(value: monitor.leftHand)
                    Spacer()
                    HandMeter(value: monitor.rightHand)
                }
                .padding(8)
            }
            HStack(spacing: 6) {
                Button {
                    Haptics.success()
                    editor.setRestPose()
                } label: {
                    Label("Set rest pose", systemImage: "scope")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(Theme.raised))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("set-rest-pose")
                Spacer(minLength: 0)
                IconButton(systemName: "xmark", label: "Stop face", size: 34) { editor.stopFaceCapture() }
            }
            .foregroundStyle(Theme.text)
        }
        .padding(10)
        .panelStyle(cornerRadius: 22)
        .offset(x: offset.width + drag.width, y: offset.height + drag.height)
        .gesture(
            DragGesture()
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                }
        )
        .accessibilityIdentifier("face-preview")
    }
}

/// How raised a tracked hand is (a small vertical bar).
private struct HandMeter: View {
    let value: Double

    var body: some View {
        Capsule()
            .fill(Color.black.opacity(0.5))
            .frame(width: 6, height: 30)
            .overlay(alignment: .bottom) {
                Capsule().fill(Theme.accent).frame(width: 6, height: max(30 * value, 3))
            }
    }
}
