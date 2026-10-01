import Foundation

/// What an audio clip is for. Roles only change defaults (colour, lane, ducking), never behaviour.
public enum AudioRole: String, Codable, Sendable, CaseIterable, Identifiable {
    case voiceover, sfx, music

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .voiceover: "Voiceover"
        case .sfx: "Sound effects"
        case .music: "Music"
        }
    }
}

/// A point of a clip's volume envelope: at `time` seconds after the clip starts, the gain is `gain`.
public struct EnvelopePoint: Codable, Hashable, Sendable {
    public var time: Double
    public var gain: Double

    public init(time: Double, gain: Double) {
        self.time = time
        self.gain = gain
    }
}

/// A piece of an audio file placed on the timeline. The file lives in the project's `audio/` folder.
public struct AudioClip: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var role: AudioRole
    public var name: String
    /// File name inside the project's `audio/` folder.
    public var file: String
    /// Timeline time where the clip starts playing.
    public var start: Double
    /// Seconds into the file where playback starts (trim in).
    public var offset: Double
    /// How long it plays (trim out).
    public var duration: Double
    /// Length of the whole file.
    public var sourceDuration: Double
    /// Linear gain (1 = as recorded).
    public var volume: Double
    public var fadeIn: Double
    public var fadeOut: Double
    /// Optional volume automation on top of `volume` (times relative to the clip start, sorted).
    public var envelope: [EnvelopePoint]
    public var muted: Bool

    public init(
        id: String, role: AudioRole, name: String, file: String, start: Double = 0, offset: Double = 0,
        duration: Double, sourceDuration: Double? = nil, volume: Double = 1, fadeIn: Double = 0, fadeOut: Double = 0,
        envelope: [EnvelopePoint] = [], muted: Bool = false
    ) {
        self.id = id
        self.role = role
        self.name = name
        self.file = file
        self.start = start
        self.offset = offset
        self.duration = duration
        self.sourceDuration = sourceDuration ?? offset + duration
        self.volume = volume
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.envelope = envelope.sorted { $0.time < $1.time }
        self.muted = muted
    }

    public var end: Double { start + duration }

    /// File time heard at timeline `time` (nil outside the clip).
    public func fileTime(at time: Double) -> Double? {
        guard time >= start - 1e-9, time <= end + 1e-9 else { return nil }
        return offset + (time - start)
    }

    /// Timeline time at which file time `fileTime` is heard (nil when trimmed away).
    public func timelineTime(forFileTime fileTime: Double) -> Double? {
        guard fileTime >= offset - 1e-9, fileTime <= offset + duration + 1e-9 else { return nil }
        return start + (fileTime - offset)
    }

    /// Gain at timeline `time`: volume × fades × envelope; 0 outside the clip or when muted.
    public func gain(at time: Double) -> Double {
        guard !muted, time >= start, time <= end else { return 0 }
        let local = time - start
        var gain = volume
        if fadeIn > 0, local < fadeIn { gain *= local / fadeIn }
        if fadeOut > 0, duration - local < fadeOut { gain *= max(duration - local, 0) / fadeOut }
        return gain * envelopeGain(at: local)
    }

    /// Envelope value at `local` seconds (1 without points; linear between points, held at the ends).
    public func envelopeGain(at local: Double) -> Double {
        guard let first = envelope.first, let last = envelope.last else { return 1 }
        if local <= first.time { return first.gain }
        if local >= last.time { return last.gain }
        for index in 1 ..< envelope.count where envelope[index].time >= local {
            let a = envelope[index - 1]
            let b = envelope[index]
            let span = b.time - a.time
            return span > 0 ? a.gain + (b.gain - a.gain) * (local - a.time) / span : b.gain
        }
        return last.gain
    }

    /// Trims so the clip plays `range` of the timeline (keeps what's heard in place).
    public func trimmed(to range: TimeRange) -> AudioClip {
        var copy = self
        let newStart = max(range.start, start - offset)
        let newEnd = min(range.end, start - offset + sourceDuration)
        copy.offset = offset + (newStart - start)
        copy.start = newStart
        copy.duration = max(newEnd - newStart, 0)
        return copy
    }
}

// MARK: Transcript

/// One recognised word, in *file* time of the clip it belongs to.
public struct TranscriptWord: Codable, Hashable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double
    /// 0…1 when the recogniser reports it.
    public var confidence: Double?

    public init(text: String, start: Double, end: Double, confidence: Double? = nil) {
        self.text = text
        self.start = start
        self.end = max(end, start)
        self.confidence = confidence
    }

    public var duration: Double { end - start }
}

/// Words of one audio clip (usually the voiceover), from on-device speech recognition.
public struct Transcript: Codable, Hashable, Sendable {
    /// The `AudioClip.id` the words belong to.
    public var clip: String
    /// BCP-47 language code the words were recognised in ("en-US", "ar-SA", "it-IT").
    public var language: String
    public var words: [TranscriptWord]

    public init(clip: String, language: String, words: [TranscriptWord]) {
        self.clip = clip
        self.language = language
        self.words = words.sorted { $0.start < $1.start }
    }

    public var text: String { words.map(\.text).joined(separator: " ") }
}

/// A word placed on the timeline (what markers, snapping, captions and lip sync use).
public struct TimelineWord: Hashable, Sendable, Identifiable {
    public var clip: String
    /// Index in the transcript's `words`.
    public var index: Int
    public var text: String
    public var start: Double
    public var end: Double

    public init(clip: String, index: Int, text: String, start: Double, end: Double) {
        self.clip = clip
        self.index = index
        self.text = text
        self.start = start
        self.end = end
    }

    public var id: String { "\(clip)#\(index)" }
    public var duration: Double { end - start }

    /// Lower-cased text without surrounding punctuation (for matching "punch on 'Enigma'").
    public var normalized: String { TimelineWord.normalize(text) }

    public static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
    }
}

public extension Timeline {
    /// Every transcribed word that is heard, in timeline time, sorted.
    var words: [TimelineWord] {
        var result: [TimelineWord] = []
        for transcript in transcripts {
            guard let clip = audio.first(where: { $0.id == transcript.clip }), !clip.muted else { continue }
            for (index, word) in transcript.words.enumerated() {
                guard let start = clip.timelineTime(forFileTime: word.start) else { continue }
                let end = clip.timelineTime(forFileTime: word.end) ?? clip.end
                result.append(TimelineWord(clip: clip.id, index: index, text: word.text, start: start, end: max(end, start)))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    func transcript(for clip: String) -> Transcript? { transcripts.first { $0.clip == clip } }

    /// End of the last audio clip.
    var audioEnd: Double { audio.map(\.end).max() ?? 0 }
}

/// Snapping anything (keys, cuts, presets, overlays) to spoken words.
public enum WordSnap {
    /// The word start (or end, when closer) nearest to `time` within `tolerance` seconds.
    public static func snap(_ time: Double, to words: [TimelineWord], tolerance: Double) -> Double? {
        var best: Double?
        var bestDistance = tolerance
        for word in words {
            for candidate in [word.start, word.end] where abs(candidate - time) <= bestDistance {
                best = candidate
                bestDistance = abs(candidate - time)
            }
        }
        return best
    }

    /// The word being spoken at `time` (or the last one before it within `lookback` seconds).
    public static func word(at time: Double, in words: [TimelineWord], lookback: Double = 0) -> TimelineWord? {
        words.last { $0.start <= time + 1e-9 && $0.end + lookback >= time }
    }

    /// Words whose text matches `phrase` (case- and punctuation-insensitive), as the first word of each match.
    /// Multi-word phrases must match consecutive words.
    public static func find(_ phrase: String, in words: [TimelineWord]) -> [ClosedRange<Int>] {
        let wanted = phrase.split(whereSeparator: \.isWhitespace).map { TimelineWord.normalize(String($0)) }.filter { !$0.isEmpty }
        guard !wanted.isEmpty, words.count >= wanted.count else { return [] }
        var matches: [ClosedRange<Int>] = []
        for first in 0 ... words.count - wanted.count
            where (0 ..< wanted.count).allSatisfy({ words[first + $0].normalized == wanted[$0] }) {
            matches.append(first ... first + wanted.count - 1)
        }
        return matches
    }
}

/// Editing a transcript by hand while keeping its timings (the recogniser misheard "Enigma" as "enema").
public enum TranscriptEditing {
    /// Replaces word `index` with `text`. Several words split the original span in proportion to their
    /// length; an empty text removes the word.
    public static func replace(_ transcript: Transcript, word index: Int, with text: String) -> Transcript {
        guard transcript.words.indices.contains(index) else { return transcript }
        var copy = transcript
        let original = transcript.words[index]
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        copy.words.replaceSubrange(index ... index, with: split(original, into: parts))
        return copy
    }

    /// Replaces words `range` with `text`, spreading the new words over the old span.
    public static func replace(_ transcript: Transcript, words range: ClosedRange<Int>, with text: String) -> Transcript {
        guard transcript.words.indices.contains(range.lowerBound), transcript.words.indices.contains(range.upperBound) else { return transcript }
        var copy = transcript
        let first = transcript.words[range.lowerBound]
        let last = transcript.words[range.upperBound]
        let span = TranscriptWord(text: "", start: first.start, end: last.end, confidence: nil)
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        copy.words.replaceSubrange(range, with: split(span, into: parts))
        return copy
    }

    /// Joins words `range` into one word spanning them all ("New" "York" → "New York").
    public static func merge(_ transcript: Transcript, words range: ClosedRange<Int>) -> Transcript {
        guard range.count > 1, transcript.words.indices.contains(range.lowerBound), transcript.words.indices.contains(range.upperBound) else {
            return transcript
        }
        var copy = transcript
        let slice = transcript.words[range]
        guard let first = slice.first, let last = slice.last else { return transcript }
        let merged = TranscriptWord(text: slice.map(\.text).joined(separator: " "), start: first.start, end: last.end,
                                    confidence: slice.compactMap(\.confidence).min())
        copy.words.replaceSubrange(range, with: [merged])
        return copy
    }

    /// Moves a word's edges. Neighbours that touched it (or would overlap) follow, so words stay joined.
    public static func retime(_ transcript: Transcript, word index: Int, start: Double? = nil, end: Double? = nil) -> Transcript {
        guard transcript.words.indices.contains(index) else { return transcript }
        var copy = transcript
        let old = copy.words[index]
        var word = old
        let lowerLimit = index > 0 ? copy.words[index - 1].start : 0
        let upperLimit = index + 1 < copy.words.count ? copy.words[index + 1].end : .infinity
        if let start { word.start = min(max(start, lowerLimit), word.end) }
        if let end { word.end = max(min(end, upperLimit), word.start) }
        copy.words[index] = word
        if index > 0 {
            let previous = copy.words[index - 1]
            if previous.end > word.start || abs(previous.end - old.start) < 1e-6 { copy.words[index - 1].end = word.start }
        }
        if index + 1 < copy.words.count {
            let next = copy.words[index + 1]
            if next.start < word.end || abs(next.start - old.end) < 1e-6 { copy.words[index + 1].start = word.end }
        }
        return copy
    }

    static func split(_ word: TranscriptWord, into parts: [String]) -> [TranscriptWord] {
        guard !parts.isEmpty else { return [] }
        let total = Double(parts.reduce(0) { $0 + max($1.count, 1) })
        var cursor = word.start
        return parts.enumerated().map { index, part in
            let share = word.duration * Double(max(part.count, 1)) / total
            let end = index == parts.count - 1 ? word.end : cursor + share
            defer { cursor = end }
            return TranscriptWord(text: part, start: cursor, end: end, confidence: nil)
        }
    }

    /// Splits recogniser text that covers `range` into words, sharing the time by length.
    /// (A recogniser run can hold several words or leading spaces.)
    public static func words(from text: String, start: Double, end: Double, confidence: Double? = nil) -> [TranscriptWord] {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        return split(TranscriptWord(text: "", start: start, end: end, confidence: confidence), into: parts).map {
            var word = $0
            word.confidence = confidence
            return word
        }
    }
}
