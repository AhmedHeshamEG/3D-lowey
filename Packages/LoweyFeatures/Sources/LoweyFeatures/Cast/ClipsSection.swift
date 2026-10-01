import HmmDesign
import LoweyCore
import SwiftUI

/// Clips on a character: play one from the playhead, tune each segment, feet on the ground, look at, walk speed
/// matched to a path, crowds.
struct ClipsSection: View {
    @Bindable var editor: EditorModel
    let character: ObjectID
    @State private var crowdCount = 12.0

    var body: some View {
        PanelSection("Clips") {
            let clips = availableClips
            if clips.isEmpty {
                Hint("This model has no clips. Import clips made for the same skeleton (Mixamo, Quaternius…) and they play here.")
            } else {
                Menu {
                    ForEach(clips, id: \.self) { clip in
                        Button(title(of: clip)) { editor.addClip(clip) }
                    }
                } label: {
                    Label("Play a clip from the playhead", systemImage: "figure.walk").font(.hmm(.body, weight: .semibold))
                }
                .accessibilityIdentifier("play-clip")
            }
            if let track = editor.clipTrack(for: character) {
                ForEach(track.segments) { segment in
                    SegmentRow(editor: editor, segment: segment)
                }
                Toggle("Feet stay on the ground", isOn: Binding(get: { track.ik.feetOnGround }, set: { value in editor.setIK { $0.feetOnGround = value } }))
                Toggle("Walk in place (a path moves it)", isOn: Binding(get: { track.ik.inPlace }, set: { value in editor.setIK { $0.inPlace = value } }))
                lookAtMenu(track)
                if editor.selectedCharacter != nil {
                    HmmPillButton("Walk speed = path speed", systemName: "figure.walk.motion") { editor.matchClipSpeedToPath() }
                    HStack {
                        Slider(value: $crowdCount, in: 4 ... 60, step: 1).accessibilityLabel("Crowd size")
                        HmmPillButton("Crowd of \(Int(crowdCount))", systemName: "person.3.fill") { editor.makeCrowd(count: Int(crowdCount)) }
                    }
                }
            }
        }
        .font(.hmm(.body))
    }

    private var availableClips: [ClipRef] {
        if let (_, asset) = editor.selectedCharacter { return editor.availableClips(for: asset) }
        return editor.puppetClips()
    }

    private func title(of clip: ClipRef) -> String {
        if clip.asset == BuiltinClips.assetID || editor.baseScene.objects[character]?.kind.assetID == clip.asset { return clip.name }
        return "\(clip.name) — \(editor.library.manifest.asset(clip.asset)?.name ?? "library")"
    }

    private func lookAtMenu(_ track: ClipTrack) -> some View {
        Menu {
            Button("Nothing") { editor.setIK { $0.lookAt = nil } }
            ForEach(editor.baseScene.roots.filter { $0 != character }.prefix(20).map { $0 }, id: \.self) { id in
                Button(editor.baseScene.objects[id]?.name ?? "Object") { editor.setIK { $0.lookAt = id } }
            }
        } label: {
            Label(track.ik.lookAt.flatMap { editor.baseScene.objects[$0]?.name }.map { "Looks at \($0)" } ?? "Head looks at…", systemImage: "eyes")
                .font(.hmm(.body, weight: .semibold))
        }
    }
}

private struct SegmentRow: View {
    let editor: EditorModel
    let segment: ClipSegment
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
            HStack {
                Text(segment.clip.name).font(.hmm(.body, weight: .semibold))
                Text("\(NumberFormat.short(segment.start))–\(NumberFormat.short(segment.end)) s").font(.hmmNumbers(.caption)).foregroundStyle(theme.text2)
                Spacer()
                Toggle("Loop", isOn: Binding(get: { segment.loop }, set: { value in editor.updateSegment(segment.id) { $0.loop = value } }))
                    .toggleStyle(.button)
                HmmButton("trash", label: "Remove \(segment.clip.name)", size: 32, role: .destructive) { editor.removeSegment(segment.id) }
            }
            LabeledSlider(title: "Speed", value: segment.speed, range: 0.1 ... 3, format: { String(format: "%.2g×", $0) }, set: { value in
                editor.updateSegment(segment.id, coalesce: "speed-\(segment.id)") { $0.speed = value }
            }, done: editor.endGesture)
            LabeledSlider(title: "Blend", value: segment.blend, range: 0 ... 1.5, format: { "\(NumberFormat.short($0)) s" }, set: { value in
                editor.updateSegment(segment.id, coalesce: "blend-\(segment.id)") { $0.blend = value }
            }, done: editor.endGesture)
        }
        .padding(HmmSpacing.xs)
        .background(RoundedRectangle(cornerRadius: HmmRadius.control).fill(theme.surface2.opacity(0.7)))
    }
}
