import Foundation

/// One subtitle cue.
public struct SubtitleCue: Hashable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum SubtitleError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)

    public var description: String {
        switch self {
        case let .unreadable(reason): "Couldn't read the subtitles: \(reason)"
        }
    }
}

/// SRT, WebVTT and JSON, in and out.
public enum Subtitles {
    /// Groups words into cues of at most `maxCharacters`, breaking early at sentence ends and at pauses longer
    /// than `pause` seconds, never longer than `maxDuration`.
    public static func cues(from words: [TranscriptWord], maxCharacters: Int = 42, maxDuration: Double = 6,
                            pause: Double = 0.7) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var current: [TranscriptWord] = []
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            cues.append(SubtitleCue(start: first.start, end: last.end, text: current.map(\.text).joined(separator: " ")))
            current.removeAll()
        }
        for word in words {
            if let last = current.last, let first = current.first {
                let length = current.map(\.text.count).reduce(0, +) + current.count + word.text.count
                let sentenceEnded = last.text.last.map { ".!?…".contains($0) } ?? false
                if length > maxCharacters || word.end - first.start > maxDuration || word.start - last.end > pause || sentenceEnded {
                    flush()
                }
            }
            current.append(word)
        }
        flush()
        return cues
    }

    // MARK: SRT

    public static func srt(_ cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start, separator: ",")) --> \(timestamp(cue.end, separator: ","))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    public static func parseSRT(_ text: String) throws -> [SubtitleCue] {
        try parseBlocks(text.replacingOccurrences(of: "\r\n", with: "\n"), skipHeader: false)
    }

    // MARK: WebVTT

    public static func vtt(_ cues: [SubtitleCue]) -> String {
        "WEBVTT\n\n" + cues.map { cue in
            "\(timestamp(cue.start, separator: ".")) --> \(timestamp(cue.end, separator: "."))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    public static func parseVTT(_ text: String) throws -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("WEBVTT") else { throw SubtitleError.unreadable("missing WEBVTT header") }
        return try parseBlocks(normalized, skipHeader: true)
    }

    // MARK: JSON

    public static func json(_ transcript: Transcript) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(transcript)
    }

    public static func parseJSON(_ data: Data) throws -> Transcript {
        do {
            return try JSONDecoder().decode(Transcript.self, from: data)
        } catch {
            throw SubtitleError.unreadable("not a transcript JSON file")
        }
    }

    /// Words from cues: each cue's time is shared by its words in proportion to their length.
    public static func words(from cues: [SubtitleCue]) -> [TranscriptWord] {
        cues.flatMap { TranscriptText.words(from: $0.text, start: $0.start, end: $0.end) }
    }

    // MARK: Helpers

    /// `HH:MM:SS,mmm` (SRT) or `HH:MM:SS.mmm` (VTT).
    public static func timestamp(_ seconds: Double, separator: Character) -> String {
        let totalMilliseconds = Int((max(seconds, 0) * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = totalMilliseconds / 60000 % 60
        let secs = totalMilliseconds / 1000 % 60
        let millis = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d\(separator)%03d", hours, minutes, secs, millis)
    }

    /// Parses `HH:MM:SS,mmm`, `HH:MM:SS.mmm` or `MM:SS.mmm`.
    public static func seconds(_ stamp: String) -> Double? {
        let parts = stamp.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2 ... 3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count else { return nil }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }

    private static func parseBlocks(_ text: String, skipHeader: Bool) throws -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = text.components(separatedBy: "\n\n")
        for (index, block) in blocks.enumerated() {
            if skipHeader, index == 0 { continue }
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let sides = lines[timingIndex].components(separatedBy: "-->")
            let endField = sides.count == 2 ? sides[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) : nil
            guard let startText = sides.first, let endText = endField, let start = seconds(startText), let end = seconds(endText) else {
                throw SubtitleError.unreadable("bad timing line “\(lines[timingIndex])”")
            }
            let body = lines[(timingIndex + 1)...].joined(separator: " ")
            cues.append(SubtitleCue(start: start, end: max(end, start), text: body))
        }
        return cues
    }
}
