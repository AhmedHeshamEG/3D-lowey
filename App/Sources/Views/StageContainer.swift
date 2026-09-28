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
                    FramingGuide(framing: editor.snapshotFraming, size: geometry.size, safeZones: false)
                } else if editor.mode == .camera, editor.lookThrough, editor.shotCamera != nil {
                    FramingGuide(framing: editor.cameraFraming, size: geometry.size, safeZones: editor.showSafeZones)
                }
                OverlaySelection(editor: editor)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Dashed frames around selected overlays (they have no 3D selection box).
struct OverlaySelection: View {
    let editor: EditorModel

    var body: some View {
        _ = editor.scene.id
        let selected = Set(editor.selection)
        let rect = editor.frameRect
        let placements = selected.isEmpty ? [] : editor.stageOverlayPlacements().filter { selected.contains($0.id) }
        ForEach(placements, id: \.id) { placement in
            let box = OverlayRenderer.boxSize(placement, frame: rect.size)
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .frame(width: box.width + 16, height: box.height + 16)
                .rotationEffect(.radians(-placement.angle))
                .position(x: rect.minX + CGFloat(placement.center.x), y: rect.minY + CGFloat(placement.center.y))
        }
    }
}

/// Darkens everything outside the export frame and draws title-safe lines.
struct FramingGuide: View {
    let framing: Framing
    let size: CGSize
    var safeZones = true

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
            if safeZones {
                // Title safe (80 %) and thirds.
                Rectangle()
                    .stroke(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
                    .frame(width: frame.width * 0.8, height: frame.height * 0.8)
                    .position(x: frame.midX, y: frame.midY)
                Path { path in
                    for fraction in [1.0 / 3, 2.0 / 3] {
                        path.move(to: CGPoint(x: frame.minX + frame.width * fraction, y: frame.minY))
                        path.addLine(to: CGPoint(x: frame.minX + frame.width * fraction, y: frame.maxY))
                        path.move(to: CGPoint(x: frame.minX, y: frame.minY + frame.height * fraction))
                        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + frame.height * fraction))
                    }
                }
                .stroke(.white.opacity(0.15), lineWidth: 1)
            }
            Text(framing.rawValue)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .position(x: frame.minX + 22, y: frame.minY + 12)
        }
    }

    private func rect() -> CGRect {
        framing.guideRect(in: size)
    }
}
