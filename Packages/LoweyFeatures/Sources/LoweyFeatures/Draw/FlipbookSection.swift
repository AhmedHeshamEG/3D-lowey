import HmmDesign
import LoweyCore
import SwiftUI

/// Draw ▸ Flipbook: frame-by-frame drawing over the shot. Pick or start a track, draw into the drawing at the
/// playhead, step through drawings and their holds, add a ready-made drawn effect.
struct FlipbookSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HStack(spacing: HmmSpacing.xs) {
                ForEach(FlipbookSettings.Mode.allCases) { mode in
                    ChoiceChip(title: mode.title, systemName: mode.systemImage, isOn: editor.flipbook.mode == mode) { editor.flipbook.mode = mode }
                        .accessibilityIdentifier("flipbook-\(mode.rawValue)")
                }
            }
            PanelSection("Tracks") {
                FlowChips(items: trackChoices, isOn: { $0 == editor.flipbook.track }) { key in
                    if key == "new" { editor.startNewFlipbook() } else { editor.flipbook.track = key }
                }
                .accessibilityIdentifier("flipbook-tracks")
                Hint(trackHint)
            }
            if let track = editor.activeFlipbook {
                trackOptions(track)
                drawings(track)
            }
            PanelSection("Drawn effects") {
                FlowChips(items: FlipbookFX.allCases.map { ($0.rawValue, $0.title) }, isOn: { _ in false }) { key in
                    if let fx = FlipbookFX(rawValue: key) { editor.addFlipbookEffect(fx) }
                }
                Hint("On the selected object, else on the camera, starting at the playhead.")
            }
            Hint("Width and opacity are the sidebar's sliders.")
        }
        .font(.hmm(.body))
    }

    private var trackChoices: [(String, String)] {
        var choices: [(String, String)] = editor.flipbookTracks.map { track in (track.id, track.name) }
        choices.append(("new", "New track"))
        return choices
    }

    private func drawingTitle(_ track: FlipbookTrack) -> String {
        let current = editor.activeFlipbookFrame.map { String($0 + 1) } ?? "–"
        return "Drawing \(current) of \(track.frames.count)"
    }

    private var trackHint: String {
        if editor.activeFlipbook == nil {
            return editor.defaultFlipbookAnchor == .camera ? "Your first stroke starts a flipbook on the camera."
                : "Your first stroke starts a flipbook that follows “\(editor.singleSelection?.name ?? "")”."
        }
        return "Strokes go into the drawing at the playhead; past the last drawing they start a new one."
    }

    private func trackOptions(_ track: FlipbookTrack) -> some View {
        PanelSection("Track") {
            FlowChips(items: anchorChoices(track), isOn: { $0 == (track.anchor.object?.raw ?? "camera") }) { key in
                editor.anchorFlipbook(to: key == "camera" ? .camera : .object(ObjectID(raw: key)))
            }
            Picker("Blend", selection: Binding(get: { track.blend }, set: { blend in editor.updateFlipbook("Blend") { $0.blend = blend } })) {
                ForEach(FlipbookBlend.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledSlider(title: "Track opacity", value: track.opacity, range: 0 ... 1, format: { "\(Int(($0 * 100).rounded())) %" },
                          set: { value in editor.updateFlipbook("Opacity", coalesceKey: "flipbook-opacity") { $0.opacity = value } },
                          done: { editor.endGesture() })
            Toggle("Loop", isOn: Binding(get: { track.loops }, set: { loops in
                editor.updateFlipbook("Loop") { $0.loops = loops }
            }))
            Toggle("Onion skin", isOn: $editor.flipbook.onionSkin)
            HmmPillButton("Delete track", systemName: "trash", role: .destructive) { editor.deleteFlipbook() }
        }
    }

    private func anchorChoices(_ track: FlipbookTrack) -> [(String, String)] {
        var choices = [("camera", "Camera")]
        if let anchored = track.anchor.object, let object = editor.scene.objects[anchored] {
            choices.append((anchored.raw, object.name))
        }
        if let selected = editor.singleSelection, selected.id != track.anchor.object, selected.kind != .camera, !selected.kind.isOverlay {
            choices.append((selected.id.raw, "Follow “\(selected.name)”"))
        }
        return choices
    }

    private func drawings(_ track: FlipbookTrack) -> some View {
        PanelSection(drawingTitle(track)) {
            HStack(spacing: HmmSpacing.xs) {
                HmmButton("plus.rectangle.on.rectangle", label: "New drawing after this", size: 40) { editor.addFlipbookDrawing() }
                HmmButton("square.on.square", label: "Duplicate drawing", size: 40) { editor.duplicateFlipbookDrawing() }
                HmmButton("trash", label: "Delete drawing", size: 40, role: .destructive) { editor.deleteFlipbookDrawing() }
                Spacer(minLength: 0)
                HmmButton("minus", label: "Shorter hold", size: 40) { editor.changeFlipbookHold(by: -1) }
                Text(holdText(track)).font(.hmmNumbers(.footnote, weight: .semibold)).frame(minWidth: 36)
                HmmButton("plus", label: "Longer hold", size: 40) { editor.changeFlipbookHold(by: 1) }
            }
            .disabled(editor.activeFlipbookFrame == nil)
            Stepper("New drawings hold \(editor.flipbook.hold) frames", value: $editor.flipbook.hold, in: 1 ... 8)
        }
    }

    private func holdText(_ track: FlipbookTrack) -> String {
        guard let index = editor.activeFlipbookFrame, track.frames.indices.contains(index) else { return "–" }
        return "×\(track.frames[index].hold)"
    }
}

/// The flipbook's quick options at the bottom of the stage.
struct FlipbookOptionsBar: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(FlipbookSettings.Mode.allCases) { mode in
                ChoiceChip(title: mode.title, systemName: mode.systemImage, isOn: editor.flipbook.mode == mode) { editor.flipbook.mode = mode }
            }
            HmmButton("plus.rectangle.on.rectangle", label: "New drawing", size: 36) { editor.addFlipbookDrawing() }
                .disabled(editor.activeFlipbook == nil)
            HmmButton("circle.dotted.circle", label: "Onion skin", isOn: editor.flipbook.onionSkin, size: 36) { editor.flipbook.onionSkin.toggle() }
            HmmButton("xmark", label: "Done drawing", size: 36) { editor.tool = .select }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground()
    }
}
