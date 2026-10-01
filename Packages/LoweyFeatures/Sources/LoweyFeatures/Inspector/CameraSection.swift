import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// A selected camera: Frame shot, cuts and transitions, the lens, one-tap moves, framing for every shape, the iPad as
/// the camera.
struct CameraSection: View {
    @Bindable var editor: EditorModel
    let camera: ObjectID
    @State private var shotType: ShotType = .medium
    @State private var composition: Composition = .center
    @State private var moveDuration: Double?
    @State private var moveStrength = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            PanelSection("Shot") {
                HStack(spacing: HmmSpacing.xs) {
                    HmmPillButton("Cut here", systemName: "scissors") { editor.cutToCamera(camera) }
                    HmmPillButton("Director view", systemName: "video", prominent: !editor.directorView) {
                        editor.selectCamera(camera)
                        editor.setDirectorView(true)
                    }
                }
                Picker("Framing", selection: $editor.deliveryFraming) {
                    ForEach(Framing.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Thirds", isOn: $editor.showsThirds)
                Toggle("Safe areas", isOn: $editor.showsSafeAreas)
            }
            frameShot
            lens
            moves
            TransitionSection(editor: editor)
            PanelSection("iPad as camera") {
                HmmPillButton(editor.virtualCameraActive ? "Stop" : "Use the iPad as the camera", systemName: "iphone.gen3.radiowaves.left.and.right",
                              prominent: !editor.virtualCameraActive) {
                    if editor.virtualCameraActive {
                        editor.stopVirtualCamera()
                    } else {
                        editor.startVirtualCamera()
                    }
                }
                .accessibilityIdentifier("virtual-camera")
                if editor.virtualCameraActive {
                    LabeledSlider(title: "Scale (1 m walked = \(NumberFormat.short(editor.virtualCameraScale)) m)", value: editor.virtualCameraScale,
                                  range: 0.2 ... 30) { editor.virtualCameraScale = $0 }
                    Hint("Record in Perform: every move of the iPad becomes camera keys (one undo step).")
                }
            }
        }
        .font(.hmm(.body))
    }

    /// The Frame shot solver: select the subject too, pick a shot and a composition.
    private var frameShot: some View {
        PanelSection("Frame shot") {
            Picker("Shot", selection: $shotType) {
                ForEach(ShotType.allCases) { Text($0.title).tag($0) }
            }
            Picker("Composition", selection: $composition) {
                ForEach(Composition.allCases) { Text($0.title).tag($0) }
            }
            HmmPillButton("Frame it", systemName: "camera.viewfinder", prominent: true) { editor.frameShot(shotType, composition: composition) }
                .disabled(!editor.selection.contains { $0 != camera })
                .accessibilityIdentifier("frame-shot")
            Hint("Select the camera and the subject (two subjects for a two-shot or over-the-shoulder).")
        }
    }

    private var lens: some View {
        let lens = editor.lens(of: camera)
        return PanelSection("Lens") {
            LabeledSlider(title: "Focal length", value: lens?.focalLength ?? 35, range: 12 ... 200, format: { "\(Int($0)) mm" },
                          set: { editor.setFocalLength($0, gesture: "focal") }, done: editor.endGesture)
            LabeledSlider(title: "Focus", value: lens?.focusDistance ?? 5, range: 0.2 ... 60, format: { "\(NumberFormat.short($0)) m" },
                          set: { editor.setCameraProperty(.focusDistance, $0, gesture: "focus") }, done: editor.endGesture)
            LabeledSlider(title: "Aperture", value: lens?.aperture ?? 0, range: 0 ... 22, format: { $0 < 0.9 ? "Off" : "f/\(NumberFormat.short($0))" },
                          set: { editor.setCameraProperty(.aperture, $0 < 0.9 ? 0 : $0, gesture: "aperture") }, done: editor.endGesture)
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("Focus on selection", systemName: "scope") { editor.focus(onSelection: false) }
                HmmPillButton("Focus pull", systemName: "camera.metering.center.weighted") { editor.focus(onSelection: true) }
            }
            .disabled(editor.selection.allSatisfy { $0 == camera })
            LabeledSlider(title: "9:16 zoom", value: lens?.portraitZoom ?? 1, range: 0.5 ... 2, format: { String(format: "%.2g×", $0) },
                          set: { editor.setCameraProperty(.portraitZoom, $0, gesture: "pzoom") }, done: editor.endGesture)
            LabeledSlider(title: "9:16 pan", value: lens?.portraitShift ?? 0, range: -1 ... 1, format: NumberFormat.percent,
                          set: { editor.setCameraProperty(.portraitShift, $0, gesture: "pshift") }, done: editor.endGesture)
        }
    }

    private var moves: some View {
        PanelSection("Moves from the playhead") {
            TileGrid(minimum: 80) {
                ForEach(CameraMove.allCases) { move in
                    TileButton(title: move.title, systemName: Self.icon(for: move), identifier: "move-\(move.rawValue)") {
                        editor.applyCameraMove(move, duration: moveDuration ?? move.defaultDuration, strength: moveStrength)
                    }
                }
            }
            LabeledSlider(
                title: "Length",
                value: moveDuration ?? 2,
                range: 0.1 ... 8,
                format: { moveDuration == nil ? "Auto" : "\(NumberFormat.short($0)) s" }
            ) {
                moveDuration = $0
            }
            LabeledSlider(title: "Strength", value: moveStrength, range: 0.2 ... 2, format: NumberFormat.percent) { moveStrength = $0 }
            if editor.selection.contains(where: { $0 != camera }) {
                HmmPillButton("Follow the selection", systemName: "scope") { editor.followSelection(with: camera) }
            }
        }
    }

    static func icon(for move: CameraMove) -> String {
        switch move {
        case .pushIn: "arrow.down.forward.and.arrow.up.backward"
        case .pullOut: "arrow.up.backward.and.arrow.down.forward"
        case .punchIn: "plus.magnifyingglass"
        case .snapZoom: "scope"
        case .orbit: "rotate.3d"
        case .dolly: "arrow.forward"
        case .truck: "arrow.left.and.right"
        case .crane: "arrow.up"
        case .whipPan: "wind"
        case .shake: "waveform.path"
        case .reveal: "eye"
        }
    }
}

/// How the cut at the playhead hands over, and the match cut.
struct TransitionSection: View {
    let editor: EditorModel

    var body: some View {
        PanelSection("Transition") {
            if let cut = editor.cutAtPlayhead {
                let current = cut.transition?.kind ?? .cut
                Text("Cut to \(editor.baseScene.objects[cut.camera]?.name ?? "camera") at \(TimeFormat.clock(cut.time))").font(.hmm(
                    .footnote,
                    weight: .semibold
                ))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HmmSpacing.xs) {
                        ForEach(TransitionSpec.Kind.allCases) { kind in
                            ChoiceChip(title: kind.title, isOn: kind == current) {
                                editor.setTransition(kind, duration: cut.transition?.duration ?? 0.6, forCutAt: cut.time)
                            }
                        }
                    }
                }
                if let transition = cut.transition {
                    LabeledSlider(title: "Length", value: transition.duration, range: 0.1 ... 3, format: { "\(NumberFormat.short($0)) s" }) { value in
                        editor.setTransition(transition.kind, duration: value, forCutAt: cut.time)
                    }
                }
                HmmPillButton("Match cut on the selection", systemName: "rectangle.2.swap") { editor.matchCut() }
            } else {
                Hint("Put the playhead on a cut (Cut here) to choose how the shots hand over.")
            }
        }
    }
}
