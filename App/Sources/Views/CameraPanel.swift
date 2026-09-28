import LoweyCore
import LoweyRender
import SwiftUI

/// Camera mode: cameras and cuts, one-tap moves, lens and focus, framing for 16:9 and 9:16,
/// and the iPad itself as the camera.
struct CameraPanel: View {
    @Bindable var editor: EditorModel
    @State private var moveDuration: Double?
    @State private var moveStrength = 1.0
    @State private var focal = 35.0
    @State private var focus = 5.0
    @State private var aperture = 0.0
    @State private var portraitZoom = 1.0
    @State private var portraitShift = 0.0

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Camera", systemImage: "video").font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    Toggle(isOn: Binding(get: { editor.lookThrough }, set: { editor.setLookThrough($0) })) {
                        Label("Look through", systemImage: "eye")
                    }
                    .toggleStyle(.button)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityIdentifier("look-through")
                }
                cameraList
                TransitionSection(editor: editor)
                if let camera = editor.editedCamera {
                    moves
                    lens(camera)
                    framing(camera)
                    virtualCamera
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .panelStyle()
        .onAppear(perform: loadLens)
        .onChange(of: editor.editedCamera) { _, _ in loadLens() }
        .onChange(of: editor.time) { _, _ in if !editor.isPlaying { loadLens() } }
    }

    private func loadLens() {
        guard let id = editor.editedCamera, let lens = editor.lens(of: id) else { return }
        focal = lens.focalLength
        focus = lens.focusDistance
        aperture = lens.aperture
        portraitZoom = lens.portraitZoom
        portraitShift = lens.portraitShift
    }

    // MARK: Cameras & cuts

    private var cameraList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Cameras")
            ForEach(editor.cameras, id: \.self) { id in
                HStack {
                    Button {
                        editor.selectCamera(id)
                    } label: {
                        HStack {
                            Image(systemName: id == editor.shotCamera ? "video.fill" : "video")
                                .foregroundStyle(id == editor.shotCamera ? Theme.accent : Theme.secondaryText)
                            Text(editor.baseScene.objects[id]?.name ?? "Camera").font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    PillButton(title: "Cut here", systemName: "scissors") { editor.cutToCamera(id) }
                }
                .padding(.vertical, 2)
            }
            PillButton(title: editor.cameras.isEmpty ? "Save camera from view" : "New camera from view", systemName: "video.badge.plus",
                       prominent: editor.cameras.isEmpty) { editor.newCameraFromView() }
            Text("“Cut here” switches to that camera from the playhead on. Look through to aim: drag to pan and tilt, two fingers to move, pinch to dolly.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Moves

    private var moves: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Moves (from the playhead)")
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CameraMove.allCases) { move in
                    Button {
                        editor.applyCameraMove(move, duration: moveDuration ?? move.defaultDuration, strength: moveStrength)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: Self.icon(for: move)).font(.system(size: 18))
                            Text(move.title).font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(Theme.text)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("move-\(move.rawValue)")
                }
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(moveDuration.map { "Length \(NumberFormat.short($0)) s" } ?? "Length: auto")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    Slider(value: Binding(get: { moveDuration ?? 2 }, set: { moveDuration = $0 }), in: 0.1 ... 8)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Strength \(Int(moveStrength * 100))%").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    Slider(value: $moveStrength, in: 0.2 ... 2)
                }
            }
            if let camera = editor.editedCamera, editor.selection.contains(where: { $0 != camera }) {
                PillButton(title: "Follow the selection", systemName: "scope") { editor.followSelection(with: camera) }
            }
        }
    }

    // MARK: Lens

    private func lens(_ camera: ObjectID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Lens")
            valueSlider("Focal length \(Int(focal)) mm", value: $focal, range: 12 ... 200) { editor.setFocalLength(focal) }
            valueSlider("Focus \(NumberFormat.short(focus)) m", value: $focus, range: 0.2 ... 60) { editor.setCameraProperty(.focusDistance, focus) }
            valueSlider(aperture <= 0.01 ? "Depth of field: off" : "Aperture f/\(NumberFormat.short(aperture))", value: $aperture, range: 0 ... 22) {
                editor.setCameraProperty(.aperture, aperture < 0.9 ? 0 : aperture)
            }
            HStack {
                PillButton(title: "Focus on selection", systemName: "scope") { editor.focus(onSelection: false) }
                PillButton(title: "Focus pull", systemName: "camera.metering.center.weighted") { editor.focus(onSelection: true) }
            }
            .disabled(editor.selection.allSatisfy { $0 == camera })
        }
    }

    // MARK: Framing

    private func framing(_: ObjectID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Framing")
            Picker("Framing", selection: $editor.cameraFraming) {
                ForEach(Framing.allCases) { framing in
                    Text(framing.rawValue).tag(framing)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: editor.cameraFraming) { _, _ in editor.updateLookThrough() }
            Toggle("Safe zones", isOn: $editor.showSafeZones).font(.system(size: 13))
            Text("The 9:16 version of this shot:").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            valueSlider("9:16 zoom \(NumberFormat.short(portraitZoom))×", value: $portraitZoom, range: 0.5 ... 2) {
                editor.setCameraProperty(.portraitZoom, portraitZoom)
            }
            valueSlider("9:16 pan \(Int(portraitShift * 100))%", value: $portraitShift, range: -1 ... 1) {
                editor.setCameraProperty(.portraitShift, portraitShift)
            }
        }
    }

    // MARK: Virtual camera

    private var virtualCamera: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "iPad as camera")
            PillButton(title: editor.virtualCameraActive ? "Stop" : "Use the iPad as the camera", systemName: "iphone.gen3.radiowaves.left.and.right",
                       prominent: !editor.virtualCameraActive) {
                if editor.virtualCameraActive {
                    editor.stopVirtualCamera()
                } else {
                    editor.startVirtualCamera()
                }
            }
            .accessibilityIdentifier("virtual-camera")
            if editor.virtualCameraActive {
                valueSlider("Scale \(NumberFormat.short(editor.virtualCameraScale))× (1 m of walking = \(NumberFormat.short(editor.virtualCameraScale)) m)",
                            value: $editor.virtualCameraScale, range: 0.2 ... 30) {}
                PillButton(title: editor.performPhase == .recording ? "Stop recording" : "Record the move", systemName: "record.circle",
                           prominent: true) {
                    if editor.performPhase == .recording {
                        editor.pause()
                    } else {
                        editor.armPerform()
                    }
                }
                Text("Recording plays the timeline; every move of the iPad becomes camera keys (one undo step).")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, commit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            Slider(value: value, in: range) { editing in
                if !editing { commit() }
            }
        }
    }

    static func icon(for move: CameraMove) -> String {
        switch move {
        case .pushIn: "arrow.down.forward.and.arrow.up.backward"
        case .pullOut: "arrow.up.backward.and.arrow.down.forward"
        case .punchIn: "plus.magnifyingglass"
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
