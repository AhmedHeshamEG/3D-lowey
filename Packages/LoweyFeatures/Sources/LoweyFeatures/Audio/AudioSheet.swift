import HmmDesign
import LoweyCore
import SwiftUI

/// Sound & words: record or import, edit the selected clip, transcribe, captions.
struct AudioSheet: View {
    @Bindable var editor: EditorModel
    @State private var importRole: AudioRole?
    @State private var languages: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HmmSheet("Sound & words") {
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton(editor.isRecordingVoice ? "Stop recording" : "Record voiceover", systemName: editor.isRecordingVoice ? "stop.fill" : "mic.fill",
                              prominent: true) {
                    editor.toggleVoiceRecording()
                    if !editor.isRecordingVoice { dismiss() }
                }
                .accessibilityIdentifier("record-voiceover")
                ForEach(AudioRole.allCases) { role in
                    HmmPillButton("Import \(role.title.lowercased())", systemName: role.systemImage) { importRole = role }
                }
            }
            Hint("Recording plays the timeline from the playhead, so you narrate over the animation. Imported sounds land at the playhead.")
            PanelSection("Sound effects") {
                FlowChips(items: Foley.allCases.map { sound in (sound.rawValue, sound.title) }, isOn: { _ in false }) { key in
                    if let sound = Foley(rawValue: key) { editor.addFoley(sound, hitting: editor.snapToWords ? editor.wordSnapped(editor.time) : nil) }
                }
                Hint("Its hit lands on the playhead (on the nearest word with snapping on). In the transcript, pick a word: Sound here.")
            }
            Toggle("Snap keys, cuts and the playhead to spoken words", isOn: $editor.snapToWords).font(.hmm(.body, weight: .semibold))
            if let id = editor.selectedAudio, let clip = editor.audioClip(id) {
                ClipControls(editor: editor, clip: clip, languages: languages)
            } else if !editor.audioClips.isEmpty {
                Hint("Tap a sound in the timeline to edit it.")
            }
            CaptionsSection(editor: editor)
        }
        .fileImporter(isPresented: Binding(get: { importRole != nil }, set: { if !$0 { importRole = nil } }), allowedContentTypes: [.audio],
                      allowsMultipleSelection: true) { result in
            if case let .success(urls) = result, let role = importRole { editor.importAudio(urls, role: role) }
            importRole = nil
        }
        .task { languages = await SpeechTranscription.languages() }
    }
}

private struct ClipControls: View {
    let editor: EditorModel
    let clip: AudioClip
    let languages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HmmSectionHeader(clip.name)
            Picker("Kind", selection: Binding(get: { clip.role }, set: { role in editor.updateAudioClip(clip.id) { $0.role = role } })) {
                ForEach(AudioRole.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
            slider("Volume", clip.volume, 0 ... 2, NumberFormat.percent) { value, clip in clip.volume = value }
            slider("Fade in", clip.fadeIn, 0 ... 5, { "\(NumberFormat.short($0)) s" }) { value, clip in clip.fadeIn = min(value, clip.duration) }
            slider("Fade out", clip.fadeOut, 0 ... 5, { "\(NumberFormat.short($0)) s" }) { value, clip in clip.fadeOut = min(value, clip.duration) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.xs) {
                    HmmPillButton(clip.muted ? "Unmute" : "Mute", systemName: clip.muted ? "speaker.wave.2" : "speaker.slash") {
                        editor.updateAudioClip(clip.id, label: clip.muted ? "Unmute" : "Mute") { $0.muted.toggle() }
                    }
                    HmmPillButton("Starts here", systemName: "arrow.right.to.line") { editor.trimAudioClip(clip.id, startHere: true) }
                    HmmPillButton("Ends here", systemName: "arrow.left.to.line") { editor.trimAudioClip(clip.id, startHere: false) }
                    HmmPillButton("Split", systemName: "scissors") { editor.splitAudioClip(clip.id) }
                    if clip.role == .music {
                        HmmPillButton("Duck under the voice", systemName: "arrow.down.right.and.arrow.up.left") { editor.duckMusicUnderVoice(clip.id) }
                        if !clip.envelope.isEmpty { HmmPillButton("No ducking") { editor.updateAudioClip(clip.id, label: "No ducking") { $0.envelope = [] } } }
                    }
                    HmmPillButton("Delete", systemName: "trash", role: .destructive) { editor.deleteAudioClip(clip.id) }
                }
            }
            words
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HmmSectionHeader("Words")
            HStack(spacing: HmmSpacing.xs) {
                Menu {
                    ForEach(languages, id: \.self) { code in
                        Button(Locale.current.localizedString(forIdentifier: code) ?? code) { editor.transcriptLanguage = code }
                    }
                } label: {
                    Label(Locale.current.localizedString(forIdentifier: editor.transcriptLanguage) ?? editor.transcriptLanguage, systemImage: "globe")
                        .font(.hmm(.body, weight: .semibold))
                }
                HmmPillButton(editor.timeline.transcript(for: clip.id) == nil ? "Transcribe" : "Transcribe again", systemName: "text.bubble",
                              prominent: editor.timeline.transcript(for: clip.id) == nil) { editor.transcribe(clip.id) }
                    .disabled(editor.transcribing != nil)
                    .accessibilityIdentifier("transcribe")
                if editor.timeline.transcript(for: clip.id) != nil {
                    HmmPillButton("Open the transcript", systemName: "text.quote") { editor.sheet = .transcript }
                }
            }
            if let status = editor.transcribing {
                HStack(spacing: HmmSpacing.xs) {
                    ProgressView().controlSize(.small)
                    Text(LocalizedStringKey(status)).font(.hmm(.footnote))
                }
            }
            Hint("Word timing runs on the iPad (Apple's speech recogniser; the language downloads once).")
        }
    }

    private func slider(_ title: String, _ value: Double, _ range: ClosedRange<Double>, _ format: @escaping (Double) -> String,
                        _ change: @escaping (Double, inout AudioClip) -> Void) -> some View {
        LabeledSlider(title: title, value: value, range: range, format: format, set: { newValue in
            editor.updateAudioClip(clip.id, label: title, coalesce: "\(title)-\(clip.id)") { change(newValue, &$0) }
        }, done: editor.endGesture)
    }
}

/// Captions from the voiceover's words: style, place, size, the spoken word lit, burnt into the video.
private struct CaptionsSection: View {
    let editor: EditorModel

    var body: some View {
        let settings = editor.captions
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HmmSectionHeader("Captions")
            Toggle("Captions from the voiceover", isOn: Binding(get: { settings?.enabled ?? false }, set: { on in editor.updateCaptions { $0.enabled = on } }))
                .font(.hmm(.body, weight: .semibold))
                .accessibilityIdentifier("captions-toggle")
            if let settings, settings.enabled {
                Picker("Style", selection: Binding(get: { settings.style }, set: { style in editor.updateCaptions { $0.style = style } })) {
                    ForEach(CaptionSettings.Style.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Where", selection: Binding(get: { settings.position }, set: { position in editor.updateCaptions { $0.position = position } })) {
                    ForEach(CaptionSettings.Position.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledSlider(title: "Size", value: settings.size, range: 0.03 ... 0.14, format: NumberFormat.percent, set: { value in
                    editor.updateCaptions(coalesce: "caption-size") { $0.size = value }
                }, done: editor.endGesture)
                Toggle("Light up the spoken word", isOn: Binding(get: { settings.karaoke }, set: { value in editor.updateCaptions { $0.karaoke = value } }))
                Toggle("Capitals", isOn: Binding(get: { settings.uppercase }, set: { value in editor.updateCaptions { $0.uppercase = value } }))
                Toggle("Burn into the video", isOn: Binding(get: { settings.burnIn }, set: { value in editor.updateCaptions { $0.burnIn = value } }))
                if editor.words.isEmpty { Hint("Transcribe the voiceover and the captions appear.") }
            }
        }
        .font(.hmm(.body))
    }
}
