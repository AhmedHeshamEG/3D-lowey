import Foundation

/// How captions look. Few decisions: a style, a position, and whether the spoken word lights up.
public struct CaptionSettings: Codable, Hashable, Sendable {
    public enum Style: String, Codable, Sendable, CaseIterable, Identifiable {
        /// Big bold words, the spoken word highlighted (short-form video look).
        case punchy
        /// Plain subtitles on a soft box.
        case subtitle
        /// Words on rounded pills.
        case pill
        /// Outlined text, no box.
        case outline

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .punchy: "Punchy"
            case .subtitle: "Subtitle"
            case .pill: "Pill"
            case .outline: "Outline"
            }
        }
    }

    public enum Position: String, Codable, Sendable, CaseIterable, Identifiable {
        case bottom, middle, top

        public var id: String { rawValue }
    }

    public var enabled: Bool
    /// Draw the captions into exported videos (otherwise only the .srt is written).
    public var burnIn: Bool
    public var style: Style
    public var position: Position
    /// Text height as a fraction of the frame's short side.
    public var size: Double
    public var color: RGBA
    public var highlight: RGBA
    public var uppercase: Bool
    /// The word being spoken is highlighted.
    public var karaoke: Bool
    /// Characters per line for 16:9 (9:16 uses about 60 %).
    public var maxCharacters: Int
    public var maxLines: Int

    public init(
        enabled: Bool = true, burnIn: Bool = true, style: Style = .punchy, position: Position = .bottom, size: Double = 0.075,
        color: RGBA = RGBA(1, 1, 1), highlight: RGBA = RGBA(1, 0.78, 0.2), uppercase: Bool = false, karaoke: Bool = true,
        maxCharacters: Int = 32, maxLines: Int = 2
    ) {
        self.enabled = enabled
        self.burnIn = burnIn
        self.style = style
        self.position = position
        self.size = size
        self.color = color
        self.highlight = highlight
        self.uppercase = uppercase
        self.karaoke = karaoke
        self.maxCharacters = maxCharacters
        self.maxLines = maxLines
    }
}

/// One caption on screen: lines of words, shown from `start` to `end`.
public struct CaptionPage: Hashable, Sendable {
    public var lines: [[TimelineWord]]
    public var start: Double
    public var end: Double

    public var words: [TimelineWord] { lines.flatMap(\.self) }
    public var text: String { lines.map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n") }
}

/// Splits spoken words into caption pages and writes subtitle files.
public enum Captions {
    /// Pages for `words`. Pages break at sentence ends, long pauses and when the lines are full;
    /// each page stays up until the next begins (or briefly after its last word).
    public static func pages(_ words: [TimelineWord], maxCharacters: Int, maxLines: Int, pause: Double = 0.6) -> [CaptionPage] {
        var pages: [CaptionPage] = []
        var lines: [[TimelineWord]] = [[]]
        func flush() {
            let filled = lines.filter { !$0.isEmpty }
            guard let first = filled.first?.first, let last = filled.last?.last else { return }
            pages.append(CaptionPage(lines: filled, start: first.start, end: last.end))
            lines = [[]]
        }
        for word in words {
            if let previous = lines.last?.last ?? lines.dropLast().last?.last {
                let gap = word.start - previous.end
                let sentenceEnd = previous.text.last.map { ".!?؟".contains($0) } ?? false
                if gap > pause || sentenceEnd { flush() }
            }
            let current = lines[lines.count - 1]
            let length = current.map(\.text.count).reduce(0, +) + current.count + word.text.count
            if !current.isEmpty, length > maxCharacters {
                if lines.count >= maxLines { flush() } else { lines.append([]) }
            }
            lines[lines.count - 1].append(word)
        }
        flush()
        // Linger a moment after the last word (never into the next page), so captions don't flicker.
        for index in pages.indices {
            let next = index + 1 < pages.count ? pages[index + 1].start : .infinity
            pages[index].end = max(pages[index].end, min(pages[index].end + 0.35, next))
        }
        return pages
    }

    /// The page on screen at `time` and the index (within the page) of the word being spoken.
    public static func page(at time: Double, in pages: [CaptionPage]) -> (page: CaptionPage, word: Int?)? {
        guard let page = pages.last(where: { $0.start <= time + 1e-9 && time < $0.end }) else { return nil }
        let word = page.words.lastIndex { $0.start <= time + 1e-9 }
        return (page, word)
    }

    /// SubRip subtitles (.srt).
    public static func srt(_ pages: [CaptionPage]) -> String {
        pages.enumerated().map { index, page in
            "\(index + 1)\n\(timestamp(page.start, separator: ",")) --> \(timestamp(page.end, separator: ","))\n\(page.text)\n"
        }.joined(separator: "\n")
    }

    /// WebVTT subtitles (.vtt).
    public static func vtt(_ pages: [CaptionPage]) -> String {
        "WEBVTT\n\n" + pages.map { page in
            "\(timestamp(page.start, separator: ".")) --> \(timestamp(page.end, separator: "."))\n\(page.text)\n"
        }.joined(separator: "\n")
    }

    static func timestamp(_ time: Double, separator: String) -> String {
        let totalMilliseconds = Int((max(time, 0) * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = totalMilliseconds / 60000 % 60
        let seconds = totalMilliseconds / 1000 % 60
        let milliseconds = totalMilliseconds % 1000
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(width - text.count, 0)) + text
        }
        return "\(pad(hours, 2)):\(pad(minutes, 2)):\(pad(seconds, 2))\(separator)\(pad(milliseconds, 3))"
    }
}
