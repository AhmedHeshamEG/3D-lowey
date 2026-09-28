import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// One audio clip in the timeline: a waveform you can slide in time; tap for its options.
struct AudioRow: View {
    @Bindable var editor: EditorModel
    let clip: AudioClip
    let width: CGFloat
    let x: (Double) -> CGFloat
    let pps: Double
    @State private var drag: Double?

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: Self.icon(clip.role))
                    .font(.system(size: 11))
                    .foregroundStyle(Self.color(clip.role))
                Text(clip.name)
                    .font(.system(size: 12, weight: editor.selectedAudio == clip.id ? .bold : .medium))
                    .foregroundStyle(clip.muted ? Theme.secondaryText : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .frame(width: TimelineDrawer.labelWidth)
            .contentShape(Rectangle())
            .onTapGesture { editor.selectedAudio = clip.id }
            lane
        }
        .background(editor.selectedAudio == clip.id ? Self.color(clip.role).opacity(0.08) : Color.clear)
    }

    private var lane: some View {
        let peaks = editor.waveforms[clip.file] ?? []
        let offset = drag ?? 0
        return Canvas { context, size in
            let start = x(clip.start + offset)
            let end = x(clip.end + offset)
            let rect = CGRect(x: start, y: 2, width: max(end - start, 2), height: size.height - 4)
            guard rect.maxX > 0, rect.minX < size.width else { return }
            let color = Self.color(clip.role)
            context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(color.opacity(clip.muted ? 0.08 : 0.22)))
            if editor.selectedAudio == clip.id {
                context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(color), lineWidth: 1.5)
            }
            // Waveform: 100 peaks per second of the file, drawn per pixel column, scaled by the clip's gain.
            if !peaks.isEmpty {
                var wave = Path()
                let mid = rect.midY
                let half = rect.height / 2 - 2
                var px = max(rect.minX, 0)
                while px < min(rect.maxX, size.width) {
                    let time = clip.start + offset + Double(px - start) / pps
                    if let fileTime = clip.fileTime(at: time - offset) {
                        let index = Int(fileTime * 100)
                        let peak = peaks.indices.contains(index) ? CGFloat(peaks[index]) : 0
                        let gain = CGFloat(min(clip.gain(at: time - offset), 1.5))
                        let h = max(peak * gain * half, 0.5)
                        wave.move(to: CGPoint(x: px, y: mid - h))
                        wave.addLine(to: CGPoint(x: px, y: mid + h))
                    }
                    px += 2
                }
                context.stroke(wave, with: .color(color.opacity(clip.muted ? 0.3 : 0.85)), lineWidth: 1.2)
            }
            // Fades as slopes.
            if clip.fadeIn > 0 {
                var fade = Path()
                fade.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                fade.addLine(to: CGPoint(x: rect.minX + CGFloat(clip.fadeIn * pps), y: rect.minY))
                context.stroke(fade, with: .color(.white.opacity(0.5)), lineWidth: 1)
            }
            if clip.fadeOut > 0 {
                var fade = Path()
                fade.move(to: CGPoint(x: rect.maxX - CGFloat(clip.fadeOut * pps), y: rect.minY))
                fade.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                context.stroke(fade, with: .color(.white.opacity(0.5)), lineWidth: 1)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard isOnClip(value.startLocation.x) else { return }
                    drag = max(Double(value.translation.width) / pps, -clip.start)
                }
                .onEnded { _ in
                    if let drag { editor.moveAudioClip(clip.id, by: drag) }
                    drag = nil
                }
        )
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            if isOnClip(value.location.x) { editor.selectedAudio = clip.id }
            editor.setTime(max(0, clip.start + Double(value.location.x - x(clip.start)) / pps))
        })
        .onAppear { editor.loadWaveform(clip.file) }
        .accessibilityIdentifier("audio-clip-\(clip.name)")
    }

    private func isOnClip(_ px: CGFloat) -> Bool { px >= x(clip.start) - 4 && px <= x(clip.end) + 4 }

    static func icon(_ role: AudioRole) -> String {
        switch role {
        case .voiceover: "mic.fill"
        case .sfx: "speaker.wave.2.fill"
        case .music: "music.note"
        }
    }

    static func color(_ role: AudioRole) -> Color {
        switch role {
        case .voiceover: Color(red: 0.45, green: 0.85, blue: 0.65)
        case .sfx: Color(red: 0.95, green: 0.6, blue: 0.35)
        case .music: Color(red: 0.6, green: 0.55, blue: 1)
        }
    }
}

/// Import, record, and edit sounds; transcribe the voiceover.
struct AudioSheet: View {
    @Bindable var editor: EditorModel
    @State private var importRole: AudioRole?
    @State private var languages: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Audio & words").font(.system(size: 22, weight: .bold, design: .rounded))
                    Spacer()
                    PillButton(title: "Done", prominent: true) { dismiss() }
                }
                SectionHeader(title: "Add")
                HStack(spacing: 8) {
                    PillButton(title: editor.isRecordingVoice ? "Stop recording" : "Record voiceover",
                               systemName: editor.isRecordingVoice ? "stop.fill" : "mic.fill", prominent: editor.isRecordingVoice) {
                        editor.toggleVoiceRecording()
                        if !editor.isRecordingVoice { dismiss() }
                    }
                    .accessibilityIdentifier("record-voiceover")
                    ForEach(AudioRole.allCases) { role in
                        PillButton(title: "Import \(role.title.lowercased())", systemName: AudioRow.icon(role)) { importRole = role }
                    }
                }
                Text("Recording starts the timeline from the playhead, so you can narrate over your animation. Imported sounds land at the playhead.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                Toggle("Snap keys, cuts and the playhead to spoken words", isOn: $editor.snapToWords)
                    .font(.system(size: 14, weight: .semibold))
                if let id = editor.selectedAudio, let clip = editor.audioClip(id) {
                    clipControls(clip)
                } else if !editor.audioClips.isEmpty {
                    Text("Tap a sound in the timeline to edit it.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(22)
        }
        .fileImporter(isPresented: Binding(get: { importRole != nil }, set: { if !$0 { importRole = nil } }),
                      allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result, let role = importRole { editor.importAudio(urls, role: role) }
            importRole = nil
        }
        .task { languages = await SpeechService.supportedLanguages() }
    }

    @ViewBuilder
    private func clipControls(_ clip: AudioClip) -> some View {
        SectionHeader(title: clip.name)
        Picker("Kind", selection: Binding(get: { clip.role }, set: { role in editor.updateAudioClip(clip.id) { $0.role = role } })) {
            ForEach(AudioRole.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        labeledSlider("Volume", value: clip.volume, range: 0 ... 2, format: "\(Int(clip.volume * 100))%") { value in
            editor.updateAudioClip(clip.id, label: "Volume", coalesce: "volume-\(clip.id)") { $0.volume = value }
        }
        labeledSlider("Fade in", value: clip.fadeIn, range: 0 ... 5, format: "\(NumberFormat.short(clip.fadeIn)) s") { value in
            editor.updateAudioClip(clip.id, label: "Fade in", coalesce: "fadein-\(clip.id)") { $0.fadeIn = min(value, $0.duration) }
        }
        labeledSlider("Fade out", value: clip.fadeOut, range: 0 ... 5, format: "\(NumberFormat.short(clip.fadeOut)) s") { value in
            editor.updateAudioClip(clip.id, label: "Fade out", coalesce: "fadeout-\(clip.id)") { $0.fadeOut = min(value, $0.duration) }
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PillButton(title: clip.muted ? "Unmute" : "Mute", systemName: clip.muted ? "speaker.wave.2" : "speaker.slash") {
                    editor.updateAudioClip(clip.id, label: clip.muted ? "Unmute" : "Mute") { $0.muted.toggle() }
                }
                PillButton(title: "Starts here", systemName: "arrow.right.to.line") { editor.trimAudioClip(clip.id, startHere: true) }
                PillButton(title: "Ends here", systemName: "arrow.left.to.line") { editor.trimAudioClip(clip.id, startHere: false) }
                PillButton(title: "Split", systemName: "scissors") { editor.splitAudioClip(clip.id) }
                if clip.role == .music {
                    PillButton(title: "Duck under voice", systemName: "arrow.down.right.and.arrow.up.left") { editor.duckMusicUnderVoice(clip.id) }
                    if !clip.envelope.isEmpty {
                        PillButton(title: "No ducking") { editor.updateAudioClip(clip.id, label: "No ducking") { $0.envelope = [] } }
                    }
                }
                PillButton(title: "Delete", systemName: "trash", destructive: true) { editor.deleteAudioClip(clip.id) }
            }
        }
        SectionHeader(title: "Words")
        HStack(spacing: 8) {
            Menu {
                ForEach(languages, id: \.self) { code in
                    Button(Locale.current.localizedString(forIdentifier: code) ?? code) { editor.transcriptLanguage = code }
                }
            } label: {
                Label(Locale.current.localizedString(forIdentifier: editor.transcriptLanguage) ?? editor.transcriptLanguage, systemImage: "globe")
                    .pillLabel()
            }
            PillButton(title: editor.timeline.transcript(for: clip.id) == nil ? "Transcribe" : "Transcribe again",
                       systemName: "text.bubble", prominent: editor.timeline.transcript(for: clip.id) == nil) {
                editor.transcribe(clip.id)
            }
            .disabled(editor.transcribing != nil)
            .accessibilityIdentifier("transcribe")
            if editor.timeline.transcript(for: clip.id) != nil {
                PillButton(title: "Open transcript", systemName: "text.quote") {
                    editor.showAudio = false
                    editor.showTranscript = true
                }
            }
        }
        if let status = editor.transcribing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(status).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
        }
        Text("Word timing runs on the iPad (Apple speech, no internet after the one-time language download).")
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondaryText)
    }

    private func labeledSlider(_ title: String, value: Double, range: ClosedRange<Double>, format: String,
                               set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold)).frame(width: 80, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range) { editing in
                if !editing { editor.endGesture() }
            }
            Text(format).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.secondaryText).frame(width: 60)
        }
    }
}

/// The transcript: tap a word to jump there; pick a phrase (tap its first word, then its last) and attach
/// an animation, a camera move, a cut or a marker to it — or fix the words without losing their timing.
struct TranscriptPanel: View {
    @Bindable var editor: EditorModel
    @State private var anchor: Int?
    @State private var fixing = false
    @State private var fixText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let words = editor.words
        let current = WordSnap.word(at: editor.time, in: words)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcript").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                IconButton(systemName: editor.isPlaying ? "pause.fill" : "play.fill", label: editor.isPlaying ? "Pause" : "Play", size: 40) {
                    editor.togglePlay()
                }
                PillButton(title: "Done", prominent: true) { dismiss() }
            }
            if words.isEmpty {
                Text("Transcribe a voiceover (the waveform button in the timeline) and its words appear here.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text(anchor == nil ? "Tap a word to jump there. Long-press a word, then tap another, to pick a phrase." :
                    "Now tap the last word of the phrase.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                ScrollViewReader { proxy in
                    ScrollView {
                        FlowLayout(spacing: 4) {
                            ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                                wordChip(word, index: index, isCurrent: word.id == current?.id)
                                    .id(word.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: current?.id) { _, id in
                        if editor.isPlaying, let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
                if editor.wordSelection != nil { phraseActions }
            }
        }
        .padding(22)
        .alert("Fix words", isPresented: $fixing) {
            TextField("What was said", text: $fixText)
            Button("Save") { if let range = editor.wordSelection { editor.correctWords(range, to: fixText) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The new words keep the timing of the old ones.")
        }
    }

    private func wordChip(_ word: TimelineWord, index: Int, isCurrent: Bool) -> some View {
        let selected = editor.wordSelection?.contains(index) ?? false
        return Text(word.text)
            .font(.system(size: 17, weight: isCurrent ? .bold : .regular))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .foregroundStyle(selected ? Color.black : Theme.text)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accent : (isCurrent ? Theme.raisedStrong : Color.clear)))
            .contentShape(Rectangle())
            .onTapGesture {
                if let first = anchor {
                    editor.wordSelection = min(first, index) ... max(first, index)
                    anchor = nil
                    Haptics.select()
                } else {
                    editor.wordSelection = index ... index
                    editor.jump(to: word)
                }
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                anchor = index
                editor.wordSelection = index ... index
                Haptics.select()
            }
            .accessibilityLabel(word.text)
    }

    private var phraseActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("“\(editor.selectedWordText)”").font(.system(size: 14, weight: .semibold)).lineLimit(2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !editor.selection.isEmpty {
                        Menu {
                            ForEach(AnimationPreset.allCases, id: \.self) { preset in
                                Button(preset.title) { editor.attachToWords { $0.applyPreset(preset) } }
                            }
                        } label: {
                            Label("Animate selection here", systemImage: "sparkles").pillLabel()
                        }
                    }
                    Menu {
                        ForEach(CameraMove.allCases, id: \.self) { move in
                            Button(move.title) { editor.attachToWords { $0.applyCameraMove(move, duration: $0.presetDuration ?? 1, strength: 1) } }
                        }
                    } label: {
                        Label("Camera move here", systemImage: "video").pillLabel()
                    }
                    if !editor.baseScene.cameras.isEmpty {
                        Menu {
                            ForEach(editor.baseScene.cameras, id: \.self) { id in
                                Button(editor.baseScene.objects[id]?.name ?? "Camera") { editor.attachToWords { $0.cutToCamera(id) } }
                            }
                        } label: {
                            Label("Cut here to…", systemImage: "scissors").pillLabel()
                        }
                    }
                    PillButton(title: "Marker", systemName: "flag") { editor.addMarkersForSelectedWords() }
                    PillButton(title: "Loop this", systemName: "repeat") {
                        if let range = editor.selectedWordRange { editor.updateTimeline("Loop") { $0.loop = range } }
                    }
                    PillButton(title: "Fix words", systemName: "pencil") {
                        fixText = editor.selectedWordText
                        fixing = true
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.raised))
    }
}

/// Wrapping layout for word chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += line + spacing
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += line + spacing
                line = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
