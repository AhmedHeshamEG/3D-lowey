@testable import LoweyCore
import XCTest

final class AudioTests: XCTestCase {
    private func voiceover() -> AudioClip {
        AudioClip(id: "vo", role: .voiceover, name: "Voiceover", file: "vo.m4a", start: 2, offset: 1, duration: 4, sourceDuration: 10)
    }

    func testClipTimesGainFadesAndEnvelope() {
        var clip = voiceover()
        XCTAssertEqual(clip.end, 6)
        XCTAssertEqual(clip.fileTime(at: 3), 2)
        XCTAssertNil(clip.fileTime(at: 1))
        XCTAssertEqual(clip.timelineTime(forFileTime: 1), 2)
        XCTAssertNil(clip.timelineTime(forFileTime: 0.5), "trimmed away")
        XCTAssertEqual(clip.gain(at: 1), 0)
        XCTAssertEqual(clip.gain(at: 3), 1)
        clip.fadeIn = 1
        clip.fadeOut = 2
        clip.volume = 0.8
        XCTAssertEqual(clip.gain(at: 2.5), 0.4, accuracy: 1e-9)
        XCTAssertEqual(clip.gain(at: 5), 0.4, accuracy: 1e-9)
        clip.envelope = [EnvelopePoint(time: 1, gain: 1), EnvelopePoint(time: 2, gain: 0.5)]
        XCTAssertEqual(clip.envelopeGain(at: 0), 1)
        XCTAssertEqual(clip.envelopeGain(at: 1.5), 0.75, accuracy: 1e-9)
        XCTAssertEqual(clip.envelopeGain(at: 3), 0.5)
        clip.muted = true
        XCTAssertEqual(clip.gain(at: 3), 0)
        // Trimming keeps what is heard in place.
        let trimmed = voiceover().trimmed(to: TimeRange(start: 3, end: 5))
        XCTAssertEqual(trimmed.start, 3)
        XCTAssertEqual(trimmed.offset, 2)
        XCTAssertEqual(trimmed.duration, 2)
        XCTAssertEqual(trimmed.fileTime(at: 4), voiceover().fileTime(at: 4))
    }

    func testWordsLandOnTheTimelineAndSnap() {
        var timeline = Timeline()
        timeline.audio = [voiceover()]
        timeline.transcripts = [Transcript(clip: "vo", language: "en-US", words: [
            TranscriptWord(text: "Trimmed", start: 0.2, end: 0.6),
            TranscriptWord(text: "Encrypted", start: 1.0, end: 1.6),
            TranscriptWord(text: "with", start: 1.6, end: 1.8),
            TranscriptWord(text: "Enigma.", start: 1.9, end: 2.5)
        ])]
        let words = timeline.words
        XCTAssertEqual(words.map(\.text), ["Encrypted", "with", "Enigma."], "a trimmed-away word isn't heard")
        XCTAssertEqual(words[0].start, 2, accuracy: 1e-9)
        XCTAssertEqual(words[2].normalized, "enigma")
        XCTAssertEqual(WordSnap.snap(2.95, to: words, tolerance: 0.1) ?? -1, 2.9, accuracy: 1e-9)
        XCTAssertNil(WordSnap.snap(4, to: words, tolerance: 0.1))
        XCTAssertEqual(WordSnap.word(at: 3.0, in: words)?.text, "Enigma.")
        XCTAssertEqual(WordSnap.find("ENIGMA", in: words), [2 ... 2])
        XCTAssertEqual(WordSnap.find("with enigma", in: words), [1 ... 2])
        XCTAssertEqual(WordSnap.find("nothing", in: words), [])
        XCTAssertEqual(timeline.contentEnd, 6)
        XCTAssertEqual(timeline.audioEnd, 6)
    }

    func testTranscriptCorrectionsKeepTimings() {
        let transcript = Transcript(clip: "vo", language: "en-US", words: [
            TranscriptWord(text: "an", start: 0, end: 0.2),
            TranscriptWord(text: "enema", start: 0.2, end: 1.0),
            TranscriptWord(text: "machine", start: 1.0, end: 1.5)
        ])
        let fixed = TranscriptEditing.replace(transcript, word: 1, with: "Enigma")
        XCTAssertEqual(fixed.words[1], TranscriptWord(text: "Enigma", start: 0.2, end: 1.0))
        let split = TranscriptEditing.replace(transcript, word: 1, with: "an eni")
        XCTAssertEqual(split.words.count, 4)
        XCTAssertEqual(split.words[1].start, 0.2, accuracy: 1e-9)
        XCTAssertEqual(split.words[1].end, 0.2 + 0.8 * 2 / 5, accuracy: 1e-9)
        XCTAssertEqual(split.words[2].end, 1.0, accuracy: 1e-9)
        XCTAssertEqual(TranscriptEditing.replace(transcript, word: 1, with: "").words.map(\.text), ["an", "machine"])
        let phrase = TranscriptEditing.replace(transcript, words: 0 ... 1, with: "the Enigma")
        XCTAssertEqual(phrase.words.map(\.text), ["the", "Enigma", "machine"])
        XCTAssertEqual(phrase.words[1].end, 1.0, accuracy: 1e-9)
        let merged = TranscriptEditing.merge(transcript, words: 1 ... 2)
        XCTAssertEqual(merged.words.last, TranscriptWord(text: "enema machine", start: 0.2, end: 1.5))
        let retimed = TranscriptEditing.retime(transcript, word: 1, start: 0.3, end: 1.2)
        XCTAssertEqual(retimed.words[0].end, 0.3)
        XCTAssertEqual(retimed.words[2].start, 1.2)
        XCTAssertEqual(TranscriptEditing.retime(transcript, word: 1, start: -5).words[1].start, 0)
        XCTAssertEqual(TranscriptEditing.replace(transcript, word: 9, with: "x"), transcript)
        let fromRun = TranscriptEditing.words(from: " New York ", start: 1, end: 2, confidence: 0.9)
        XCTAssertEqual(fromRun.map(\.text), ["New", "York"])
        XCTAssertEqual(fromRun[1].end, 2)
        XCTAssertEqual(fromRun[0].confidence, 0.9)
    }

    func testMixerAppliesGainTrimAndSoftClip() {
        let rate = 100.0
        let tone = PCMAudio(sampleRate: rate, channels: [[Float](repeating: 0.5, count: 1000)])
        var clip = AudioClip(id: "a", role: .music, name: "Tone", file: "tone.wav", start: 1, offset: 0, duration: 2, sourceDuration: 10)
        clip.fadeIn = 1
        let mix = AudioMixer.mix([clip], sources: ["tone.wav": tone], range: TimeRange(start: 0, end: 4), sampleRate: rate)
        XCTAssertEqual(mix.count, 800)
        XCTAssertEqual(mix[0], 0, "before the clip")
        XCTAssertEqual(mix[150 * 2], 0.25, accuracy: 0.01, "half-way through the fade in")
        XCTAssertEqual(mix[150 * 2 + 1], mix[150 * 2], "mono plays on both sides")
        XCTAssertEqual(mix[250 * 2], 0.5, accuracy: 1e-6)
        XCTAssertEqual(mix[350 * 2], 0, "after the clip")
        // Two loud clips on top of each other are limited, not clipped.
        var loud = clip
        loud.fadeIn = 0
        loud.volume = 2
        let piled = AudioMixer.mix([loud, loud], sources: ["tone.wav": tone], range: TimeRange(start: 1, end: 2), sampleRate: rate)
        XCTAssertTrue(piled.allSatisfy { $0 < 1 && $0 > 0.9 })
        XCTAssertEqual(AudioMixer.softClip(-0.5), -0.5)
        // Wrong sample rate or missing source is skipped.
        XCTAssertTrue(AudioMixer.mix([clip], sources: [:], range: TimeRange(start: 0, end: 1), sampleRate: rate).allSatisfy { $0 == 0 })
    }

    func testPeaksAndLoudness() {
        let samples: [Float] = [0, 0.5, -1, 0.25, 0, 0]
        XCTAssertEqual(AudioAnalysis.peaks(samples, bucket: 2), [0.5, 1, 0])
        XCTAssertEqual(AudioAnalysis.peaks([], bucket: 2), [])
        var quietThenLoud = [Float](repeating: 0.1, count: 10)
        quietThenLoud += [Float](repeating: 0.8, count: 10)
        let loudness = AudioAnalysis.loudness(PCMAudio(sampleRate: 20, channels: [quietThenLoud, quietThenLoud]), fps: 2)
        XCTAssertEqual(loudness.count, 2)
        XCTAssertEqual(loudness[1], 1)
        XCTAssertEqual(loudness[0], 0.125, accuracy: 1e-6)
    }

    func testWAVRoundTrip() throws {
        let samples: [Float] = [0, 0.5, -0.5, 1, -1, 0.25]
        let data = WAV.data(samples, channels: 2, sampleRate: 48000)
        XCTAssertEqual(data.count, 44 + 12)
        let back = try XCTUnwrap(WAV.read(data))
        XCTAssertEqual(back.sampleRate, 48000)
        XCTAssertEqual(back.channels.count, 2)
        XCTAssertEqual(back.channels[0], [0, -0.5, -1].map { Float(Int16(($0 * 32767).rounded())) / 32767 })
        XCTAssertEqual(back.channels[1][0], 0.5, accuracy: 1e-4)
        XCTAssertNil(WAV.read(Data("nope".utf8)))
    }

    func testAudioSurvivesSaveAndOldFilesStillOpen() throws {
        var timeline = Timeline()
        timeline.audio = [voiceover()]
        timeline.transcripts = [Transcript(clip: "vo", language: "ar-SA", words: [TranscriptWord(text: "إنيجما", start: 1, end: 2, confidence: 0.5)])]
        let data = try LoweyJSON.encode(timeline)
        XCTAssertEqual(try LoweyJSON.decode(Timeline.self, from: data), timeline)
        let bare = try LoweyJSON.decode(Timeline.self, from: Data("{}".utf8))
        XCTAssertTrue(bare.audio.isEmpty && bare.transcripts.isEmpty)
        var document = makeDocument()
        let command = EditCommand.setTimeline(timeline)
        document = try assertReverts(command, on: document)
        XCTAssertEqual(document.scene.timeline.words.first?.text, "إنيجما")
    }
}
