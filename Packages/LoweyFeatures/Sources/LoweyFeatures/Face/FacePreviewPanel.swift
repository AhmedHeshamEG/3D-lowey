import HmmDesign
import SwiftUI

/// While you perform with your face: what the tracker sees (dots on the face, lines on the arms), Set rest pose, stop.
/// Drag it anywhere.
struct FacePreviewPanel: View {
    let editor: EditorModel
    let monitor: FaceMonitor
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            ZStack {
                if let picture = monitor.picture {
                    Image(decorative: picture, scale: 1).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.black.opacity(0.6))
                    Image(systemName: "camera").font(.system(size: 22)).foregroundStyle(theme.text2)
                }
                Canvas { context, size in
                    for (a, b) in monitor.bones {
                        var path = Path()
                        path.move(to: CGPoint(x: a.x * size.width, y: a.y * size.height))
                        path.addLine(to: CGPoint(x: b.x * size.width, y: b.y * size.height))
                        context.stroke(path, with: .color(theme.accent.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    for dot in monitor.dots {
                        context.fill(Path(ellipseIn: CGRect(x: dot.x * size.width - 1.5, y: dot.y * size.height - 1.5, width: 3, height: 3)),
                                     with: .color(.green.opacity(0.9)))
                    }
                }
            }
            .frame(width: 208, height: 156)
            .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
            .overlay(alignment: .topLeading) {
                Label(monitor.faceFound ? monitor.source : "No face", systemImage: monitor.faceFound ? "face.smiling" : "face.dashed")
                    .font(.hmm(.caption, weight: .semibold))
                    .padding(.horizontal, HmmSpacing.xs)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .foregroundStyle(monitor.faceFound ? .white : .yellow)
                    .padding(6)
            }
            .overlay(alignment: .bottom) {
                HStack {
                    meter(monitor.leftHand)
                    Spacer()
                    meter(monitor.rightHand)
                }
                .padding(HmmSpacing.xs)
            }
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("Set rest pose", systemName: "scope") { editor.setRestPose() }
                    .accessibilityIdentifier("set-rest-pose")
                Spacer(minLength: 0)
                HmmButton("xmark", label: "Stop face", size: 36) { editor.stopFaceCapture() }
            }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground()
        .offset(x: offset.width + drag.width, y: offset.height + drag.height)
        .gesture(DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
            })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 76)
        .padding(.leading, 72)
        .accessibilityIdentifier("face-preview")
    }

    /// How raised a tracked hand is.
    private func meter(_ value: Double) -> some View {
        Capsule()
            .fill(Color.black.opacity(0.5))
            .frame(width: 6, height: 30)
            .overlay(alignment: .bottom) { Capsule().fill(theme.accent).frame(width: 6, height: max(30 * value, 3)) }
    }
}
