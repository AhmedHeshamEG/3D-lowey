import LoweyCore
import LoweyRender
import SwiftUI

/// Hosts the RealityKit stage and its gesture coordinator.
struct StageContainer: UIViewRepresentable {
    let editor: EditorModel

    func makeCoordinator() -> Holder { Holder() }

    func makeUIView(context: Context) -> StageView {
        let stage = StageView(renderer: editor.renderer)
        stage.accessibilityIdentifier = "stage"
        editor.attach(stage)
        context.coordinator.coordinator = StageCoordinator(editor: editor, stage: stage)
        return stage
    }

    func updateUIView(_: StageView, context: Context) {
        // Touch routing depends on the tool (Pencil draws only in Draw mode).
        _ = editor.tool
        _ = editor.mode
        _ = editor.draw.pencilOnly
        context.coordinator.coordinator?.updateTouchTypes()
    }

    final class Holder {
        var coordinator: StageCoordinator?
    }
}

/// Screen-space overlays drawn above the stage: lasso, scatter area, snapshot framing.
struct StageOverlay: View {
    let editor: EditorModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if editor.lassoPoints.count > 1 {
                    Path { path in
                        path.addLines(editor.lassoPoints)
                        path.closeSubpath()
                    }
                    .fill(Theme.accent.opacity(0.12))
                    Path { path in path.addLines(editor.lassoPoints) }
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                }
                if let preview = editor.scatterPreview {
                    Circle()
                        .fill(Theme.accent.opacity(0.12))
                        .overlay(Circle().stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
                        .frame(width: preview.radius * 2, height: preview.radius * 2 * 0.55)
                        .position(preview.center)
                    Text("\(editor.scatter.count)")
                        .font(.system(size: 15, weight: .bold))
                        .padding(6)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .position(preview.center)
                }
                if editor.mode == .export {
                    FramingGuide(framing: editor.snapshotFraming, size: geometry.size)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Darkens everything outside the export frame and draws title-safe lines.
struct FramingGuide: View {
    let framing: Framing
    let size: CGSize

    var body: some View {
        let frame = rect()
        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(frame)
            }
            .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
            Rectangle()
                .stroke(.white.opacity(0.85), lineWidth: 1.5)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
            Rectangle()
                .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .frame(width: frame.width * 0.9, height: frame.height * 0.9)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    private func rect() -> CGRect {
        framing.guideRect(in: size)
    }
}
