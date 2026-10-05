import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// Screen-space marks above the stage: the lasso loop, the scatter area, the Pencil's hover preview and dashed frames
/// around selected overlays (they have no 3D outline). The Director view's framing guides are drawn by the renderer.
struct StageOverlayView: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        ZStack {
            if editor.lassoPoints.count > 1 {
                Path { path in
                    path.addLines(editor.lassoPoints)
                    path.closeSubpath()
                }
                .fill(theme.accent.opacity(0.12))
                Path { path in path.addLines(editor.lassoPoints) }
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            }
            if let preview = editor.scatterPreview {
                Ellipse()
                    .fill(theme.accent.opacity(0.12))
                    .overlay(Ellipse().stroke(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
                    .frame(width: preview.radius * 2, height: preview.radius * 2 * 0.55)
                    .position(preview.center)
                Text("\(editor.scatter.count)")
                    .font(.hmmNumbers(.body, weight: .semibold))
                    .padding(HmmSpacing.xs)
                    .hmmGlass(in: Capsule(), interactive: false)
                    .position(preview.center)
            }
            OverlaySelectionFrames(editor: editor)
            MotionPathMarks(editor: editor)
            IKHandleMarks(editor: editor)
            PickedStrokes(editor: editor)
            FlipbookOnionSkin(editor: editor)
        }
        .allowsHitTesting(false)
    }
}

/// Dashed frames around selected overlays.
private struct OverlaySelectionFrames: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        // Redraws when the scene or playhead changes (placements read unobserved state).
        let revision = editor.displayRevision
        let selected = Set(editor.selection)
        let rect = editor.frameRect
        let placements = selected.isEmpty || revision < 0 ? [] : editor.stageOverlayPlacements().filter { selected.contains($0.id) }
        ForEach(placements, id: \.id) { placement in
            let box = OverlayRenderer.boxSize(placement, frame: rect.size)
            RoundedRectangle(cornerRadius: HmmRadius.control, style: .continuous)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .frame(width: box.width + 16, height: box.height + 16)
                .rotationEffect(.radians(-placement.angle))
                .position(x: rect.minX + CGFloat(placement.center.x), y: rect.minY + CGFloat(placement.center.y))
        }
    }
}

/// Picked ink strokes, traced in the accent colour.
private struct PickedStrokes: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        // Redraws when the scene, the camera or the picked strokes change.
        let revision = editor.displayRevision + Int(editor.viewYaw)
        let paths = editor.tool == .ink && !editor.inkStrokes.isEmpty && revision >= 0 ? editor.selectedStrokePaths() : []
        ForEach(paths.indices, id: \.self) { index in
            Path { path in path.addLines(paths[index]) }
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.35), radius: 1)
        }
    }
}

/// The flipbook drawings around the one at the playhead: earlier ones red, later ones green, fading with distance.
private struct FlipbookOnionSkin: View {
    let editor: EditorModel

    var body: some View {
        let revision = editor.displayRevision + Int(editor.viewYaw)
        let skins = revision >= 0 ? editor.flipbookOnionSkin() : []
        ForEach(skins.indices, id: \.self) { index in
            let skin = skins[index]
            Path { path in
                for outline in skin.outlines {
                    path.addLines(outline)
                    path.closeSubpath()
                }
            }
            .fill(skin.before ? Color(red: 1, green: 0.32, blue: 0.3) : Color(red: 0.3, green: 0.85, blue: 0.45))
            .opacity(0.45 * skin.fade)
        }
    }
}

/// The selection's motion path: the arc it travels, a dot per position key (the one at the playhead filled).
private struct MotionPathMarks: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    /// Redrawn when the scene or the camera changes; hidden while playing.
    private var currentPath: (points: [CGPoint], dots: [(time: Double, point: CGPoint)]) {
        let revision = editor.displayRevision + Int(editor.viewYaw)
        guard revision >= 0, !editor.isPlaying else { return ([], []) }
        return editor.motionPathOnScreen()
    }

    var body: some View {
        let path = currentPath
        if path.points.count > 1 {
            Path { line in line.addLines(path.points) }
                .stroke(theme.accent.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [2, 5]))
                .shadow(color: .black.opacity(0.3), radius: 1)
            ForEach(path.dots.indices, id: \.self) { index in
                let dot = path.dots[index]
                let current = abs(dot.time - editor.time) < 0.5 / Double(editor.timeline.fps)
                Circle()
                    .fill(current ? theme.accent : theme.background)
                    .overlay(Circle().stroke(theme.accent, lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .position(dot.point)
            }
        }
    }
}

/// A character's hands and feet you can drag (Keyframe and Perform modes).
private struct IKHandleMarks: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let revision = editor.displayRevision + Int(editor.viewYaw)
        let handles = revision >= 0 ? editor.ikHandlesOnScreen() : []
        ForEach(handles, id: \.handle.id) { item in
            Circle()
                .stroke(theme.accent, lineWidth: 2.5)
                .background(Circle().fill(theme.accent.opacity(0.18)))
                .frame(width: 26, height: 26)
                .position(item.point)
                .accessibilityLabel(item.handle.name)
        }
    }
}
