import HmmDesign
import LoweyCore
import SwiftUI

/// Motion: one-tap presets at the playhead (one after another for many objects), behaviours, simulations, puppet
/// joints, the object's frame rate, clearing animation.
struct MotionSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        PanelSection("Motion") {
            TileGrid(minimum: 78) {
                ForEach(AnimationPreset.allCases) { preset in
                    TileButton(title: preset.title, systemName: Self.icon(for: preset), identifier: "preset-\(preset.rawValue)") {
                        editor.applyPreset(preset)
                    }
                }
            }
            LabeledSlider(title: "Length", value: editor.presetDuration ?? 0.8, range: 0.1 ... 4,
                          format: { editor.presetDuration == nil ? "Auto" : "\(NumberFormat.short($0)) s" }) { editor.presetDuration = $0 }
            LabeledSlider(title: "Strength", value: editor.presetStrength, range: 0.2 ... 2, format: NumberFormat.percent) { editor.presetStrength = $0 }
            if editor.selection.count > 1 { stagger }
            if editor.selectionIsGenerator {
                HmmPillButton("Grow it in, one by one", systemName: "sparkles", prominent: true) { editor.growGenerator() }
            }
            BehaviorList(editor: editor)
            stepping
            AnimationViewOptions(editor: editor)
            TileGrid(minimum: 96) {
                TileButton(title: "Fall", systemName: "arrow.down.to.line") { editor.simulatePhysics(.fall) }
                TileButton(title: "Explode", systemName: "burst") { editor.simulatePhysics(.explode) }
                if editor.selection.count > 1 { TileButton(title: "Flock", systemName: "bird") { editor.simulateFlock() } }
            }
            Menu {
                ForEach(PivotPlace.allCases, id: \.self) { place in
                    Button(LocalizedStringKey(place.title)) { editor.makeJoint(place) }
                }
            } label: {
                Label("Make a puppet joint", systemImage: "figure.arms.open").font(.hmm(.body, weight: .semibold))
            }
            if editor.selectionHasAnimation {
                HmmPillButton("Clear animation", systemName: "xmark.bin", role: .destructive) { editor.clearAnimation() }
            }
        }
        .font(.hmm(.body))
    }

    private var stagger: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            Picker("One after another", selection: $editor.stagger.order) {
                ForEach(StaggerChoice.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            LabeledSlider(title: "Delay", value: editor.stagger.delay, range: 0 ... 0.5, format: { "\(NumberFormat.short($0)) s" }) {
                editor.stagger.delay = $0
            }
            LabeledSlider(title: "Random timing", value: editor.stagger.randomTiming, range: 0 ... 1, format: NumberFormat.percent) {
                editor.stagger.randomTiming = $0
            }
            LabeledSlider(title: "Random strength", value: editor.stagger.randomStrength, range: 0 ... 1, format: NumberFormat.percent) {
                editor.stagger.randomStrength = $0
            }
        }
    }

    private var stepping: some View {
        Picker("Frame rate", selection: Binding(
            get: { editor.singleSelection?[.stepping]?.stringValue.flatMap(Stepping.init(name:)) },
            set: { editor.setObjectStepping($0) }
        )) {
            Text("Project").tag(Stepping?.none)
            Text("Ones").tag(Stepping?.some(.onOnes))
            Text("Twos").tag(Stepping?.some(.onTwos))
            Text("Threes").tag(Stepping?.some(.onThrees))
            Text("Fours").tag(Stepping?.some(.onFours))
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Animated on")
    }

    static func icon(for preset: AnimationPreset) -> String {
        switch preset {
        case .popIn: "sparkle"
        case .popOut: "sparkles"
        case .grow: "arrow.up.left.and.arrow.down.right"
        case .shrink: "arrow.down.right.and.arrow.up.left"
        case .bounce: "figure.jumprope"
        case .wiggle: "water.waves"
        case .float: "cloud"
        case .spin: "arrow.clockwise"
        case .shake: "waveform"
        case .pulse: "heart"
        case .fadeIn: "circle.lefthalf.filled"
        case .fadeOut: "circle.dotted"
        case .slideIn: "arrow.right"
        case .dropIn: "arrow.down"
        case .typewriter: "character.cursor.ibeam"
        }
    }
}

/// Behaviours (always on, bake to keys).
private struct BehaviorList: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            Menu {
                Section("Motion") {
                    Button("Float", systemImage: "water.waves") { editor.addBehavior(.bob(height: 0.12, period: 3, tilt: 4)) }
                    Button("Sway in the wind", systemImage: "wind") { editor.addBehavior(.windSway(angle: 5, frequency: 0.4, direction: 30)) }
                    Button("Wobble", systemImage: "waveform.path") {
                        editor.addBehavior(.noise(position: Vec3(0.05, 0.05, 0.05), rotation: Vec3(4, 4, 4), frequency: 1.2))
                    }
                    Button("Spin", systemImage: "arrow.clockwise") { editor.addBehavior(.spin(degreesPerSecond: 90, axis: .y)) }
                    Button("Orbit the centre", systemImage: "circle.dashed") { editor.addBehavior(.orbit(
                        center: .zero,
                        around: nil,
                        period: 8,
                        faceCenter: false
                    )) }
                }
                Section("Follow a drawn path") {
                    ForEach(paths, id: \.self) { id in
                        Button(editor.baseScene.objects[id]?.name ?? "Path") {
                            editor.addBehavior(.followPath(.object(id), duration: max(editor.timeline.duration - 1, 2), loop: false, orient: true))
                        }
                    }
                }
                Section("Look at") {
                    ForEach(editor.baseScene.roots.filter { !editor.selection.contains($0) }.prefix(20).map { $0 }, id: \.self) { id in
                        Button(editor.baseScene.objects[id]?.name ?? "Object") { editor.addBehavior(.lookAt(id)) }
                    }
                }
            } label: {
                Label("Add a behaviour", systemImage: "plus.circle").font(.hmm(.body, weight: .semibold))
            }
            ForEach(editor.selection.flatMap { editor.behaviors(of: $0) }) { behavior in
                HStack(spacing: HmmSpacing.xs) {
                    Button { editor.toggleBehavior(behavior.id) } label: {
                        Image(systemName: behavior.enabled ? "checkmark.circle.fill" : "circle").foregroundStyle(behavior.enabled ? theme.accent : theme.text3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(behavior.enabled ? "Turn off \(behavior.kind.title)" : "Turn on \(behavior.kind.title)")
                    Text(behavior.kind.title).font(.hmm(.footnote, weight: .semibold))
                    Spacer()
                    Menu {
                        Button("Start at the playhead") { editor.setBehaviorTiming(behavior.id, startAtPlayhead: true) }
                        Button("End at the playhead") { editor.setBehaviorTiming(behavior.id, startAtPlayhead: false) }
                        Button("Bake to keys", systemImage: "diamond") { editor.bakeBehavior(behavior.id) }
                        Button("Remove", systemImage: "trash", role: .destructive) { editor.removeBehavior(behavior.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle").frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("\(behavior.kind.title) options")
                }
            }
        }
    }

    private var paths: [ObjectID] {
        editor.baseScene.orderedIDs().filter { id in
            guard !editor.selection.contains(id), case .drawing = editor.baseScene.objects[id]?.kind else { return false }
            return true
        }
    }
}

/// More: what the object is (model facts, build links), locks.
struct MetadataSection: View {
    let editor: EditorModel
    let object: SceneObject
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        PanelSection("About this object") {
            if case let .asset(id) = object.kind, let asset = editor.library.manifest.asset(id) {
                if let triangles = asset.triangleCount { line("\(triangles) triangles · \(asset.format.rawValue.uppercased())") }
                if asset.rig.isRigged { line("Skeleton: \(asset.rig.rawValue.capitalized)") }
                if !asset.clips.isEmpty { line("Clips: \(asset.clips.joined(separator: ", "))") }
            }
            if let prefabID = object.kind.prefabID, let prefab = editor.library.manifest.prefab(prefabID) {
                line("A copy of “\(prefab.name)” from your library (version \(prefab.version)).")
            }
            if !object.shadowDabs.isEmpty {
                HmmPillButton("Clear shadow painting", systemName: "eraser") { editor.clearShadowPaint() }
            }
            Toggle("Locked", isOn: Binding(get: { object.isLocked }, set: { _ in editor.toggleLock(object.id) }))
            Toggle("Visible", isOn: Binding(get: { object.isVisible }, set: { _ in editor.toggleVisible(object.id) }))
        }
        .font(.hmm(.body))
    }

    private func line(_ text: String) -> some View {
        Text(LocalizedStringKey(text)).font(.hmm(.footnote)).foregroundStyle(theme.text2)
    }
}
