import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Sound: voiceover, effects and music clips, recording over the animation, trimming and ducking, waveforms, word
/// timing and attaching things to spoken words.
extension EditorModel {
    var audioFolder: URL { projectURL.appendingPathComponent(ProjectLayout.audioFolder) }
    var audioClips: [AudioClip] { timeline.audio }
    var words: [TimelineWord] { timeline.words }

    func audioClip(_ id: String) -> AudioClip? { timeline.audio.first { $0.id == id } }

    // MARK: Import & record

    /// Copies audio files into the project and places them at the playhead (a first voiceover at 0).
    func importAudio(_ urls: [URL], role: AudioRole) {
        Task {
            var added: [AudioClip] = []
            for url in urls {
                if let clip = copyAudio(url, role: role, startingAt: role == .voiceover && timeline.audio.isEmpty ? 0 : time) { added.append(clip) }
            }
            guard !added.isEmpty else { return }
            addAudioClips(added, label: added.count == 1 ? "Add \(added[0].name)" : "Add \(added.count) sounds")
        }
    }

    private func copyAudio(_ url: URL, role: AudioRole, startingAt start: Double) -> AudioClip? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let name = uniqueAudioName(url.deletingPathExtension().lastPathComponent, ext: url.pathExtension)
            try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
            let target = audioFolder.appendingPathComponent(name)
            try FileManager.default.copyItem(at: url, to: target)
            guard let duration = AudioDecoder.duration(of: target), duration > 0 else {
                app.show("\(url.lastPathComponent) isn't audio \(AppIdentity.displayName) can read", kind: .error)
                return nil
            }
            return AudioClip(id: UUID().uuidString.lowercased(), role: role, name: url.deletingPathExtension().lastPathComponent, file: name,
                             start: start, duration: duration, sourceDuration: duration, volume: role == .music ? 0.5 : 1,
                             fadeIn: role == .music ? 1 : 0, fadeOut: role == .music ? 1.5 : 0)
        } catch {
            app.show("Couldn't import \(url.lastPathComponent): \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    func addAudioClips(_ clips: [AudioClip], label: String) {
        updateTimeline(label) { timeline in
            timeline.audio += clips
            timeline.duration = max(timeline.duration, (clips.map(\.end).max() ?? 0).rounded(.up))
        }
        selectedAudio = clips.last?.id
        for clip in clips {
            loadWaveform(clip.file)
        }
        HmmHaptics.play(.commit)
    }

    private func uniqueAudioName(_ base: String, ext: String) -> String {
        let clean = ProjectStore.sanitize(base.isEmpty ? "Audio" : base)
        let suffix = ext.isEmpty ? "m4a" : ext
        var name = "\(clean).\(suffix)"
        var counter = 2
        while FileManager.default.fileExists(atPath: audioFolder.appendingPathComponent(name).path) {
            name = "\(clean) \(counter).\(suffix)"
            counter += 1
        }
        return name
    }

    /// Record a voiceover while the timeline plays (narrate over the animation). Tap again to stop.
    func toggleVoiceRecording() {
        if isRecordingVoice {
            stopVoiceRecording()
            return
        }
        Task {
            guard await VoiceRecorder.requestPermission() else {
                app.show("Allow the microphone in Settings to record a voiceover", kind: .error)
                return
            }
            do {
                pause()
                let name = uniqueAudioName("Voiceover", ext: "m4a").replacingOccurrences(of: ".m4a", with: "")
                _ = try voiceRecorder.start(in: audioFolder, name: name)
                recordingStart = time
                isRecordingVoice = true
                play(withAudio: false)
                HmmHaptics.play(.commit)
            } catch {
                app.show("Couldn't record: \(error)", kind: .error)
            }
        }
    }

    func stopVoiceRecording() {
        guard isRecordingVoice else { return }
        isRecordingVoice = false
        pause()
        guard let (url, duration) = voiceRecorder.stop(), duration > 0.2 else {
            app.show("That recording was too short")
            return
        }
        let clip = AudioClip(id: UUID().uuidString.lowercased(), role: .voiceover, name: "Voiceover", file: url.lastPathComponent,
                             start: recordingStart, duration: duration, sourceDuration: duration)
        addAudioClips([clip], label: "Record voiceover")
        app.show("Voiceover recorded. Transcribe it to get word timings")
    }

    // MARK: Editing clips

    func updateAudioClip(_ id: String, label: String = "Edit sound", coalesce: String? = nil, _ change: (inout AudioClip) -> Void) {
        guard let index = timeline.audio.firstIndex(where: { $0.id == id }) else { return }
        updateTimeline(label, coalesce: coalesce) { change(&$0.audio[index]) }
    }

    func moveAudioClip(_ id: String, by delta: Double) {
        guard let clip = audioClip(id) else { return }
        var start = max(0, clip.start + delta)
        if snapToWords, clip.role != .voiceover, let snapped = WordSnap.snap(start, to: words, tolerance: 0.15) { start = snapped }
        let snappedStart = timeline.snapped(start)
        updateAudioClip(id, label: "Move sound") { $0.start = snappedStart }
    }

    func trimAudioClip(_ id: String, startHere: Bool) {
        guard let clip = audioClip(id), clip.start < time, clip.end > time else {
            app.show("Put the playhead inside the clip first")
            return
        }
        let range = startHere ? TimeRange(start: time, end: clip.end) : TimeRange(start: clip.start, end: time)
        updateAudioClip(id, label: "Trim sound") { $0 = $0.trimmed(to: range) }
    }

    /// Splits a clip at the playhead (the second part keeps its words).
    func splitAudioClip(_ id: String) {
        guard let clip = audioClip(id), clip.start < time - 0.05, clip.end > time + 0.05 else {
            app.show("Put the playhead inside the clip first")
            return
        }
        var first = clip.trimmed(to: TimeRange(start: clip.start, end: time))
        first.fadeOut = 0
        var second = clip.trimmed(to: TimeRange(start: time, end: clip.end))
        second.id = UUID().uuidString.lowercased()
        second.fadeIn = 0
        updateTimeline("Split sound") { timeline in
            guard let index = timeline.audio.firstIndex(where: { $0.id == id }) else { return }
            timeline.audio[index] = first
            timeline.audio.insert(second, at: index + 1)
            if var transcript = timeline.transcript(for: id) {
                transcript.clip = second.id
                timeline.transcripts.append(transcript)
            }
        }
    }

    func deleteAudioClip(_ id: String) {
        updateTimeline("Delete sound") { timeline in
            timeline.audio.removeAll { $0.id == id }
            timeline.transcripts.removeAll { $0.clip == id }
        }
        if selectedAudio == id { selectedAudio = nil }
    }

    /// Music ducks under the voice: an envelope that dips wherever words are spoken.
    func duckMusicUnderVoice(_ id: String, level: Double = 0.35) {
        guard let clip = audioClip(id) else { return }
        var points: [EnvelopePoint] = []
        for range in mergedSpeech(padding: 0.25) where range.end > clip.start && range.start < clip.end {
            let a = range.start - clip.start
            let b = range.end - clip.start
            points += [EnvelopePoint(time: max(a - 0.3, 0), gain: 1), EnvelopePoint(time: max(a, 0), gain: level),
                       EnvelopePoint(time: b, gain: level), EnvelopePoint(time: b + 0.4, gain: 1)]
        }
        guard !points.isEmpty else {
            app.show("Transcribe the voiceover first, so the music knows when you speak")
            return
        }
        updateAudioClip(id, label: "Duck music") { $0.envelope = points }
    }

    /// Speech as time ranges (words closer than `padding` joined).
    private func mergedSpeech(padding: Double) -> [TimeRange] {
        var ranges: [TimeRange] = []
        for word in words {
            if let last = ranges.last, word.start - last.end <= padding {
                ranges[ranges.count - 1] = TimeRange(start: last.start, end: max(last.end, word.end))
            } else {
                ranges.append(TimeRange(start: word.start, end: word.end))
            }
        }
        return ranges
    }

    // MARK: Waveforms

    func loadWaveform(_ file: String) {
        guard waveforms[file] == nil else { return }
        let url = audioFolder.appendingPathComponent(file)
        waveforms[file] = []
        Task.detached(priority: .utility) { [weak self] in
            guard let pcm = try? AudioDecoder.decode(url, sampleRate: 8000) else { return }
            let peaks = AudioAnalysis.peaks(pcm.mono, bucket: 80)
            await MainActor.run { self?.waveforms[file] = peaks }
        }
    }

    func loadWaveforms() {
        for clip in timeline.audio {
            loadWaveform(clip.file)
        }
    }

    /// Decoded audio at the export rate, cached (mixdown, lip-sync loudness).
    func decoded(_ file: String) -> PCMAudio? {
        if let cached = decodedAudio[file] { return cached }
        guard let pcm = try? AudioDecoder.decode(audioFolder.appendingPathComponent(file)) else { return nil }
        decodedAudio[file] = pcm
        return pcm
    }

    // MARK: Transcription

    func transcribe(_ id: String) {
        guard let clip = audioClip(id), transcribing == nil else { return }
        let url = audioFolder.appendingPathComponent(clip.file)
        let language = transcriptLanguage
        transcribing = "Preparing…"
        Task {
            do {
                let words = try await SpeechTranscription.words(in: url, language: language) { message in
                    Task { @MainActor in self.transcribing = message }
                }
                updateTimeline("Transcribe") { timeline in
                    timeline.transcripts.removeAll { $0.clip == id }
                    timeline.transcripts.append(Transcript(clip: id, language: language, words: words))
                }
                transcribing = nil
                sheet = .transcript
                HmmHaptics.play(.commit)
                app.show("\(words.count) words. They're on the timeline now")
            } catch {
                transcribing = nil
                app.show("Transcription failed: \(error)", kind: .error)
            }
        }
    }

    /// Fixes a misheard word (or phrase) without losing its timing.
    func correctWords(_ range: ClosedRange<Int>, to text: String) {
        let all = words
        guard all.indices.contains(range.lowerBound), all.indices.contains(range.upperBound) else { return }
        let clip = all[range.lowerBound].clip
        guard all[range.upperBound].clip == clip else {
            app.show("Fix one clip's words at a time")
            return
        }
        let first = all[range.lowerBound].index
        let last = all[range.upperBound].index
        updateTimeline("Fix words") { timeline in
            guard let index = timeline.transcripts.firstIndex(where: { $0.clip == clip }) else { return }
            timeline.transcripts[index] = TranscriptEditing.replace(timeline.transcripts[index], words: first ... last, with: text)
        }
        wordSelection = nil
    }

    // MARK: Words on the timeline

    func jump(to word: TimelineWord) {
        pause()
        setTime(word.start)
        audioPlayback.scrub(timeline.audio, at: word.start)
    }

    /// A time snapped to the nearest word edge within a few frames (when word snapping is on).
    func wordSnapped(_ time: Double, tolerance: Double? = nil) -> Double {
        guard snapToWords else { return time }
        return WordSnap.snap(time, to: words, tolerance: tolerance ?? 4 / Double(max(timeline.fps, 1))) ?? time
    }

    var selectedWordRange: TimeRange? {
        guard let range = wordSelection, words.indices.contains(range.lowerBound), words.indices.contains(range.upperBound) else { return nil }
        return TimeRange(start: words[range.lowerBound].start, end: words[range.upperBound].end)
    }

    var selectedWordText: String {
        guard let range = wordSelection, words.indices.contains(range.lowerBound), words.indices.contains(range.upperBound) else { return "" }
        return words[range].map(\.text).joined(separator: " ")
    }

    /// Attach to words: runs an action with the playhead on the selected words (a preset, a camera move, a cut…),
    /// timed to the phrase when it has a length.
    func attachToWords(_ action: (EditorModel) -> Void) {
        guard let range = selectedWordRange else { return }
        pause()
        let previous = presetDuration
        presetDuration = max(range.duration, 6 / Double(max(timeline.fps, 1)))
        setTime(range.start, snap: false)
        action(self)
        presetDuration = previous
    }

    func addMarkersForSelectedWords() {
        guard let range = wordSelection else { return }
        let all = words
        for index in range where all.indices.contains(index) {
            setTime(all[index].start, snap: false)
            addMarker(named: TimelineWord.normalize(all[index].text))
        }
    }
}
