import HmmDesign
import LoweyCore
import SwiftUI

/// The Motion row (CONTEXT §4.1): six looping motions, one tap each. The thing starts moving on the stage straight
/// away; a second tap stops it. One slider sets how fast, and Make keyframes turns what's running into keys.
struct MotionRow: View {
    let editor: EditorModel

    var body: some View {
        PanelSection("Move it") {
            TileGrid(minimum: 84) {
                ForEach(LoopMotion.allCases) { motion in
                    if motion == .followPath { followTile } else { tile(motion) }
                }
            }
            if !editor.loopMotions.isEmpty {
                LabeledSlider(title: "Speed", value: editor.loopMotionSpeed, range: LoopMotion.speedRange,
                              format: { String(format: "%.2g×", $0) }, set: { editor.setLoopMotionSpeed($0) }, done: { editor.endGesture() })
                    .accessibilityIdentifier("motion-speed")
                HmmPillButton("Make keyframes", systemName: "diamond") { editor.makeLoopMotionKeyframes() }
                    .accessibilityIdentifier("motion-keyframes")
            }
        }
    }

    private func tile(_ motion: LoopMotion, path: ObjectID? = nil) -> some View {
        TileButton(title: motion.title, systemName: Self.icon(for: motion), identifier: "motion-\(motion.rawValue)",
                   isOn: editor.hasLoopMotion(motion)) {
            editor.toggleLoopMotion(motion, path: path)
        }
    }

    /// Follow a path: one drawn line is followed at a tap; with several, the tap asks which.
    @ViewBuilder private var followTile: some View {
        let paths = editor.followablePaths
        if paths.count > 1, !editor.hasLoopMotion(.followPath) {
            Menu {
                ForEach(paths, id: \.self) { id in
                    Button(editor.baseScene.objects[id]?.name ?? "Path") { editor.toggleLoopMotion(.followPath, path: id) }
                }
            } label: {
                TileLabel(title: LoopMotion.followPath.title, systemName: Self.icon(for: .followPath))
            }
            .accessibilityIdentifier("motion-followPath")
        } else {
            tile(.followPath, path: paths.first)
        }
    }

    static func icon(for motion: LoopMotion) -> String {
        switch motion {
        case .spin: "arrow.clockwise"
        case .float: "cloud"
        case .bounce: "arrow.up.and.down"
        case .wiggle: "water.waves"
        case .swing: "metronome"
        case .followPath: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}
