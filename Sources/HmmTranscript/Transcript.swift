import Foundation

/// One spoken word with its time in the audio file.
public struct TranscriptWord: Codable, Hashable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double
    /// 0…1, when the recogniser reports it.
    public var confidence: Double?
    /// Speaker label, when known ("A", "B" or a name).
    public var speaker: String?

    public init(text: String, start: Double, end: Double, confidence: Double? = nil, speaker: String? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
        self.speaker = speaker
    }

    public var duration: Double { end - start }

    /// Lower-cased text without surrounding punctuation (for matching and alignment).
    public var normalized: String { TranscriptText.normalize(text) }
}

/// Word timings of one recording: the one transcript model shared by every hmm. app.
public struct Transcript: Codable, Hashable, Sendable {
    public var words: [TranscriptWord]
    /// BCP-47 ("en-US", "ar-EG", "it-IT").
    public var language: String

    public init(words: [TranscriptWord], language: String) {
        self.words = words
        self.language = language
    }

    public var text: String { words.map(\.text).joined(separator: " ") }
    public var duration: Double { words.last?.end ?? 0 }

    /// The word being spoken at `time` (or the last one that ended within `lookback` seconds).
    public func word(at time: Double, lookback: Double = 0) -> TranscriptWord? {
        words.last { $0.start <= time + 1e-9 && $0.end + lookback >= time }
    }

    /// Indices of every occurrence of `phrase` (consecutive words, case- and punctuation-insensitive).
    public func find(_ phrase: String) -> [ClosedRange<Int>] {
        TranscriptText.find(phrase, in: words.map(\.normalized))
    }
}

/// Text helpers shared by transcripts and scripts.
public enum TranscriptText {
    public static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
    }

    /// Splits text into words (whitespace-separated, punctuation kept on the word).
    public static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Consecutive matches of `phrase` in already-normalised words.
    public static func find(_ phrase: String, in normalizedWords: [String]) -> [ClosedRange<Int>] {
        let wanted = tokens(phrase).map(normalize).filter { !$0.isEmpty }
        guard !wanted.isEmpty, normalizedWords.count >= wanted.count else { return [] }
        var matches: [ClosedRange<Int>] = []
        for first in 0 ... normalizedWords.count - wanted.count
            where (0 ..< wanted.count).allSatisfy({ normalizedWords[first + $0] == wanted[$0] }) {
            matches.append(first ... first + wanted.count - 1)
        }
        return matches
    }

    /// Splits recogniser text covering `start…end` into words, sharing the time by length.
    public static func words(from text: String, start: Double, end: Double, confidence: Double? = nil) -> [TranscriptWord] {
        TranscriptEditing.split(TranscriptWord(text: "", start: start, end: end), into: tokens(text)).map {
            var word = $0
            word.confidence = confidence
            return word
        }
    }
}

/// Fixing a transcript by hand while keeping its timings (the recogniser heard "enema" for "Enigma").
public enum TranscriptEditing {
    /// Replaces word `index` with `text`; several words share the original span by length, empty text removes it.
    public static func replace(_ words: [TranscriptWord], word index: Int, with text: String) -> [TranscriptWord] {
        guard words.indices.contains(index) else { return words }
        var copy = words
        copy.replaceSubrange(index ... index, with: split(words[index], into: TranscriptText.tokens(text)))
        return copy
    }

    /// Replaces words `range` with `text`, spreading the new words over the old span.
    public static func replace(_ words: [TranscriptWord], range: ClosedRange<Int>, with text: String) -> [TranscriptWord] {
        guard words.indices.contains(range.lowerBound), words.indices.contains(range.upperBound) else { return words }
        var copy = words
        let span = TranscriptWord(text: "", start: words[range.lowerBound].start, end: words[range.upperBound].end)
        copy.replaceSubrange(range, with: split(span, into: TranscriptText.tokens(text)))
        return copy
    }

    /// Joins words `range` into one ("New" "York" → "New York").
    public static func merge(_ words: [TranscriptWord], range: ClosedRange<Int>) -> [TranscriptWord] {
        guard range.count > 1, words.indices.contains(range.lowerBound), words.indices.contains(range.upperBound) else { return words }
        var copy = words
        let slice = words[range]
        let merged = TranscriptWord(text: slice.map(\.text).joined(separator: " "), start: words[range.lowerBound].start,
                                    end: words[range.upperBound].end, confidence: slice.compactMap(\.confidence).min(),
                                    speaker: words[range.lowerBound].speaker)
        copy.replaceSubrange(range, with: [merged])
        return copy
    }

    /// Moves a word's edges; neighbours that touched it (or would overlap) follow, so words stay joined.
    public static func retime(_ words: [TranscriptWord], word index: Int, start: Double? = nil, end: Double? = nil) -> [TranscriptWord] {
        guard words.indices.contains(index) else { return words }
        var copy = words
        let old = copy[index]
        var word = old
        let lowerLimit = index > 0 ? copy[index - 1].start : 0
        let upperLimit = index + 1 < copy.count ? copy[index + 1].end : .infinity
        if let start { word.start = min(max(start, lowerLimit), word.end) }
        if let end { word.end = max(min(end, upperLimit), word.start) }
        copy[index] = word
        if index > 0, copy[index - 1].end > word.start || abs(copy[index - 1].end - old.start) < 1e-6 {
            copy[index - 1].end = word.start
        }
        if index + 1 < copy.count, copy[index + 1].start < word.end || abs(copy[index + 1].start - old.end) < 1e-6 {
            copy[index + 1].start = word.end
        }
        return copy
    }

    /// Splits one word's span into `parts`, by length.
    public static func split(_ word: TranscriptWord, into parts: [String]) -> [TranscriptWord] {
        guard !parts.isEmpty else { return [] }
        let total = Double(parts.reduce(0) { $0 + max($1.count, 1) })
        var cursor = word.start
        return parts.enumerated().map { index, part in
            let share = word.duration * Double(max(part.count, 1)) / total
            let end = index == parts.count - 1 ? word.end : cursor + share
            defer { cursor = end }
            return TranscriptWord(text: part, start: cursor, end: end, speaker: word.speaker)
        }
    }
}
