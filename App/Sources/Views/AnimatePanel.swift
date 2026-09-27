import LoweyCore
import LoweyRender
import SwiftUI

/// Animate mode, right panel: one-tap presets (with stagger for many objects), behaviours,
/// characters and clips, simulations, scripts. Few decisions, each a big result.
struct AnimatePanel: View {
    @Bindable var editor: EditorModel

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Animate", systemImage: "timeline.selection").font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    IconButton(systemName: "curlybraces", label: "Scripts", size: 38) { editor.openScript(nil) }
                }
                if editor.selection.isEmpty {
                    Text("Select something to animate. Tip: select many things to animate them all at once, one after another.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text(selectionTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    presets
                    if editor.selection.count > 1 { staggerSection }
                    if editor.selectionIsGenerator {
                        PillButton(title: "Grow it in (one by one)", systemName: "sparkles", prominent: true) { editor.growGenerator() }
                    }
                    if let character = editor.selectedCharacter { CharacterSection(editor: editor, object: character.object, asset: character.asset) }
                    behaviorSection
                    motionSection
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .panelStyle()
    }

    private var selectionTitle: String {
        if let single = editor.singleSelection { return single.name }
        return "\(editor.selection.count) objects"
    }

    // MARK: Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "One tap (at the playhead)")
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AnimationPreset.allCases) { preset in
                    Button {
                        editor.applyPreset(preset)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: Self.icon(for: preset)).font(.system(size: 18))
                            Text(preset.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(Theme.text)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("preset-\(preset.rawValue)")
                }
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(editor.presetDuration.map { "Length \(NumberFormat.short($0)) s" } ?? "Length: auto")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    Slider(value: Binding(get: { editor.presetDuration ?? 0.8 }, set: { editor.presetDuration = $0 }), in: 0.1 ... 4)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Strength \(Int(editor.presetStrength * 100))%").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    Slider(value: $editor.presetStrength, in: 0.2 ... 2)
                }
            }
            if editor.presetDuration != nil {
                Button("Back to each preset's own length") { editor.presetDuration = nil }.font(.system(size: 12, weight: .semibold))
            }
        }
    }

    private var staggerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "One after another")
            Picker("Order", selection: $editor.stagger.order) {
                ForEach(StaggerChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.menu)
            slider("Delay \(NumberFormat.short(editor.stagger.delay)) s", value: $editor.stagger.delay, range: 0 ... 0.5)
            slider("Random timing \(Int(editor.stagger.randomTiming * 100))%", value: $editor.stagger.randomTiming, range: 0 ... 1)
            slider("Random strength \(Int(editor.stagger.randomStrength * 100))%", value: $editor.stagger.randomStrength, range: 0 ... 1)
        }
    }

    // MARK: Behaviours

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Behaviours (always on, bake to keys)")
            Menu {
                Section("Motion") {
                    Button("Float (bob on water)", systemImage: "water.waves") { editor.addBehavior(.bob(height: 0.12, period: 3, tilt: 4)) }
                    Button("Sway in the wind", systemImage: "wind") { editor.addBehavior(.windSway(angle: 5, frequency: 0.4, direction: 30)) }
                    Button("Wobble", systemImage: "waveform.path") {
                        editor.addBehavior(.noise(position: Vec3(0.05, 0.05, 0.05), rotation: Vec3(4, 4, 4), frequency: 1.2))
                    }
                    Button("Spin", systemImage: "arrow.clockwise") { editor.addBehavior(.spin(degreesPerSecond: 90, axis: .y)) }
                    Button("Orbit around the centre", systemImage: "circle.dashed") {
                        editor.addBehavior(.orbit(center: .zero, around: nil, period: 8, faceCenter: false))
                    }
                }
                if !pathChoices.isEmpty {
                    Section("Follow a drawn path") {
                        ForEach(pathChoices, id: \.self) { id in
                            Button(editor.baseScene.objects[id]?.name ?? "Path") {
                                editor.addBehavior(.followPath(.object(id), duration: max(editor.timeline.duration - 1, 2), loop: false, orient: true))
                            }
                        }
                    }
                }
                if !targetChoices.isEmpty {
                    Section("Look at") {
                        ForEach(targetChoices, id: \.self) { id in
                            Button(editor.baseScene.objects[id]?.name ?? "Object") { editor.addBehavior(.lookAt(id)) }
                        }
                    }
                }
            } label: {
                Label("Add behaviour", systemImage: "plus.circle").pillLabel()
            }
            ForEach(currentBehaviors) { behavior in
                HStack(spacing: 8) {
                    Button {
                        editor.toggleBehavior(behavior.id)
                    } label: {
                        Image(systemName: behavior.enabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(behavior.enabled ? Theme.accent : Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    Text(behavior.kind.title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Menu {
                        Button("Start at playhead") { editor.setBehaviorStart(behavior.id, toPlayhead: true) }
                        Button("End at playhead") { editor.setBehaviorStart(behavior.id, toPlayhead: false) }
                        Button("Bake to keys", systemImage: "diamond") { editor.bakeBehavior(behavior.id) }
                        Button("Remove", systemImage: "trash", role: .destructive) { editor.removeBehavior(behavior.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 18))
                    }
                }
            }
        }
    }

    private var currentBehaviors: [Behavior] {
        editor.selection.flatMap { editor.behaviors(of: $0) }
    }

    /// Drawn strokes that can be paths.
    private var pathChoices: [ObjectID] {
        editor.baseScene.orderedIDs().filter { id in
            guard !editor.selection.contains(id), let object = editor.baseScene.objects[id], case .drawing = object.kind else { return false }
            return true
        }
    }

    private var targetChoices: [ObjectID] {
        editor.baseScene.roots.filter { !editor.selection.contains($0) }.prefix(20).map { $0 }
    }

    // MARK: Motion helpers

    private var motionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Motion")
            HStack {
                Text("Stepping").foregroundStyle(Theme.secondaryText).font(.system(size: 13))
                Picker("Stepping", selection: Binding(
                    get: { editor.singleSelection?[.stepping]?.stringValue.flatMap(Stepping.init(name:)) },
                    set: { editor.setObjectStepping($0) }
                )) {
                    Text("Project").tag(Stepping?.none)
                    Text("Ones").tag(Stepping?.some(.onOnes))
                    Text("Twos").tag(Stepping?.some(.onTwos))
                    Text("Threes").tag(Stepping?.some(.onThrees))
                }
                .pickerStyle(.segmented)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                Menu {
                    ForEach(EditorModel.PivotPlace.allCases, id: \.self) { place in
                        Button(place.title) { editor.makeJoint(place) }
                    }
                } label: {
                    Label("Puppet joint", systemImage: "figure.arms.open").pillLabel()
                }
                PillButton(title: "Fall", systemName: "arrow.down.to.line") { editor.simulatePhysics(.fall) }
                PillButton(title: "Explode", systemName: "burst") { editor.simulatePhysics(.explode) }
                if editor.selection.count > 1 {
                    PillButton(title: "Flock", systemName: "bird") { editor.simulateFlock() }
                }
                if editor.selectionHasAnimation {
                    PillButton(title: "Clear", systemName: "xmark.bin", destructive: true) { editor.clearAnimation() }
                }
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            Slider(value: value, in: range)
        }
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

/// Rigged characters: clips (own and retargeted), speed/loop/crossfade, path walking, IK, crowds.
struct CharacterSection: View {
    @Bindable var editor: EditorModel
    let object: SceneObject
    let asset: LibraryAsset
    @State private var crowdCount = 12.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Character · \(asset.rig.rawValue.capitalized)")
            let clips = editor.availableClips(for: asset)
            if clips.isEmpty {
                Text("This model has no animation clips. Import clips made for the same skeleton (Mixamo, Quaternius…) and they'll play here.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            } else {
                Menu {
                    ForEach(clips, id: \.self) { clip in
                        Button(clip.asset == asset.id ? clip.name : "\(clip.name) — from \(editor.library.manifest.asset(clip.asset)?.name ?? "library")") {
                            editor.addClip(clip)
                        }
                    }
                } label: {
                    Label("Play a clip from the playhead", systemImage: "figure.walk").pillLabel()
                }
                .accessibilityIdentifier("play-clip")
            }
            if let track = editor.clipTrack(for: object.id) {
                ForEach(track.segments) { segment in
                    SegmentRow(editor: editor, segment: segment)
                }
                PillButton(title: "Walk speed = path speed", systemName: "figure.walk.motion") { editor.matchClipSpeedToPath() }
                Toggle("Feet stay on the ground", isOn: Binding(get: { track.ik.feetOnGround }, set: { value in editor.setIK { $0.feetOnGround = value } }))
                    .font(.system(size: 13))
                Menu {
                    Button("Nothing") { editor.setIK { $0.lookAt = nil } }
                    ForEach(editor.baseScene.roots.filter { $0 != object.id }.prefix(20).map { $0 }, id: \.self) { id in
                        Button(editor.baseScene.objects[id]?.name ?? "Object") { editor.setIK { $0.lookAt = id } }
                    }
                } label: {
                    Label(track.ik.lookAt.flatMap { editor.baseScene.objects[$0]?.name }.map { "Looks at \($0)" } ?? "Head looks at…",
                          systemImage: "eyes").pillLabel()
                }
                HStack {
                    Slider(value: $crowdCount, in: 4 ... 60, step: 1)
                    PillButton(title: "Crowd of \(Int(crowdCount))", systemName: "person.3.fill") { editor.makeCrowd(count: Int(crowdCount)) }
                }
            }
        }
    }
}

private struct SegmentRow: View {
    @Bindable var editor: EditorModel
    let segment: ClipSegment
    @State private var speed = 1.0
    @State private var blend = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(segment.clip.name).font(.system(size: 13, weight: .semibold))
                Text("\(NumberFormat.short(segment.start))–\(NumberFormat.short(segment.end)) s")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                Spacer()
                Toggle("Loop", isOn: Binding(get: { segment.loop }, set: { value in editor.updateSegment(segment.id) { $0.loop = value } }))
                    .toggleStyle(.button).font(.system(size: 12))
                Button(role: .destructive) {
                    editor.removeSegment(segment.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text("Speed \(NumberFormat.short(speed))×").font(.system(size: 11)).foregroundStyle(Theme.secondaryText).frame(width: 74, alignment: .leading)
                Slider(value: $speed, in: 0.1 ... 3) { editing in
                    if !editing { editor.updateSegment(segment.id) { $0.speed = speed } }
                }
            }
            HStack {
                Text("Blend \(NumberFormat.short(blend)) s").font(.system(size: 11)).foregroundStyle(Theme.secondaryText).frame(width: 74, alignment: .leading)
                Slider(value: $blend, in: 0 ... 1.5) { editing in
                    if !editing { editor.updateSegment(segment.id) { $0.blend = blend } }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised))
        .onAppear {
            speed = segment.speed
            blend = segment.blend
        }
    }
}
