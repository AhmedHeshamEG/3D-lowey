import Foundation

// The standard Rhubarb / Preston Blair letters.
// swiftlint:disable identifier_name

/// Mouth shapes (Rhubarb Lip Sync / Preston Blair set). `X` is rest.
public enum Viseme: String, Codable, Sendable, CaseIterable {
    /// Closed: M, B, P.
    case A
    /// Slightly open, teeth together: most consonants, EE.
    case B
    /// Open: EH, AE, AH.
    case C
    /// Wide open: AA.
    case D
    /// Rounded: AO, ER.
    case E
    /// Puckered: OO, OW, W.
    case F
    /// Lip bite: F, V.
    case G
    /// Tongue up: L.
    case H
    /// Rest (mouth closed, relaxed).
    case X

    /// How open the jaw is for this shape (drives 3D jaws and scales mouths without shape sets).
    public var jaw: Double {
        switch self {
        case .A, .X: 0
        case .B: 0.15
        case .C: 0.5
        case .D: 0.9
        case .E: 0.45
        case .F: 0.25
        case .G: 0.1
        case .H: 0.4
        }
    }

    /// −1 (narrow, puckered) … 1 (wide).
    public var width: Double {
        switch self {
        case .A, .X: 0
        case .B: 0.45
        case .C: 0.3
        case .D: 0.2
        case .E: -0.4
        case .F: -0.8
        case .G: 0.1
        case .H: 0.15
        }
    }
}

// swiftlint:enable identifier_name

/// Word → mouth shapes: the CMU Pronouncing Dictionary for English (visemes.txt, built by scripts/make_visemes.py),
/// letter-to-sound rules for unknown English words and for Italian, and a letter map for Arabic.
public final class Phonemizer: @unchecked Sendable {
    public static let shared = Phonemizer()

    private let lock = NSLock()
    private var dictionary: [Substring: Substring]?
    private var text = ""

    public init() {}

    /// Number of dictionary words (0 when the resource is missing — rules still work).
    public var dictionarySize: Int { loadedDictionary().count }

    private func loadedDictionary() -> [Substring: Substring] {
        lock.lock()
        defer { lock.unlock() }
        if let dictionary { return dictionary }
        var map: [Substring: Substring] = [:]
        if let url = Bundle.module.url(forResource: "visemes", withExtension: "txt"), let contents = try? String(contentsOf: url, encoding: .utf8) {
            text = contents
            map.reserveCapacity(130_000)
            for line in text.split(separator: "\n") {
                guard let space = line.firstIndex(of: " ") else { continue }
                map[line[..<space]] = line[line.index(after: space)...]
            }
        }
        dictionary = map
        return map
    }

    /// Mouth shapes of one word, with a duration weight each (vowels get more time).
    public func visemes(for word: String, language: String) -> [(Viseme, Double)] {
        let clean = word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
        guard !clean.isEmpty else { return [] }
        if language.hasPrefix("ar") || clean.unicodeScalars.contains(where: { (0x0600 ... 0x06FF).contains($0.value) }) {
            return Self.arabic(clean)
        }
        if language.hasPrefix("it") { return Self.italian(clean) }
        if let entry = loadedDictionary()[Substring(clean)] { return Self.decode(entry) }
        if clean.allSatisfy(\.isNumber) { return Self.englishRules(Self.spelledNumber(clean)) }
        return Self.englishRules(clean)
    }

    static func decode(_ entry: Substring) -> [(Viseme, Double)] {
        entry.compactMap { character in
            let vowel = character.isLowercase
            guard let viseme = Viseme(rawValue: character.uppercased()) else { return nil }
            return (viseme, vowel ? 1.4 : (viseme == .A ? 0.7 : 0.8))
        }
    }

    /// Rough English letter-to-sound for words the dictionary doesn't know.
    static func englishRules(_ word: String) -> [(Viseme, Double)] {
        let letters = Array(word.lowercased())
        var result: [(Viseme, Double)] = []
        var index = 0
        func vowel(_ viseme: Viseme) { result.append((viseme, 1.4)) }
        func consonant(_ viseme: Viseme) { result.append((viseme, viseme == .A ? 0.7 : 0.8)) }
        while index < letters.count {
            let c = letters[index]
            let next = index + 1 < letters.count ? letters[index + 1] : " "
            switch (c, next) {
            case ("t", "h"), ("s", "h"), ("c", "h"), ("g", "h"):
                consonant(.B)
                index += 2
                continue
            case ("p", "h"):
                consonant(.G)
                index += 2
                continue
            case ("o", "o"), ("o", "u"), ("o", "w"):
                vowel(.F)
                index += 2
                continue
            case ("e", "e"), ("e", "a"), ("i", "e"):
                vowel(.B)
                index += 2
                continue
            case ("a", "i"), ("a", "y"):
                vowel(.C)
                index += 2
                continue
            default:
                break
            }
            switch c {
            case "a": vowel(.C)
            case "e": if index < letters.count - 1 || letters.count <= 2 { vowel(.C) } // silent final e
            case "i", "y": vowel(.B)
            case "o": vowel(.E)
            case "u": vowel(.F)
            case "m", "b", "p": consonant(.A)
            case "f", "v": consonant(.G)
            case "l": consonant(.H)
            case "w": consonant(.F)
            case "r": consonant(.B)
            case "h": consonant(.C)
            default: if c.isLetter { consonant(.B) }
            }
            index += 1
        }
        return result
    }

    /// Italian is (nearly) spelled as spoken.
    static func italian(_ word: String) -> [(Viseme, Double)] {
        var result: [(Viseme, Double)] = []
        for c in word.lowercased().folding(options: .diacriticInsensitive, locale: nil) {
            switch c {
            case "a": result.append((.D, 1.4))
            case "e": result.append((.C, 1.4))
            case "i": result.append((.B, 1.3))
            case "o": result.append((.E, 1.4))
            case "u": result.append((.F, 1.4))
            case "m", "b", "p": result.append((.A, 0.7))
            case "f", "v": result.append((.G, 0.8))
            case "l": result.append((.H, 0.8))
            case "h": continue
            default: if c.isLetter { result.append((.B, 0.8)) }
            }
        }
        return result
    }

    /// Arabic letters → mouth shapes. Short vowels are rarely written, so an open vowel is assumed after a
    /// consonant that isn't followed by a long vowel (it keeps the mouth moving like speech).
    static func arabic(_ word: String) -> [(Viseme, Double)] {
        let longVowels: [Character: Viseme] = ["ا": .D, "آ": .D, "ى": .D, "و": .F, "ي": .B]
        let marks: [Character: Viseme] = ["َ": .C, "ُ": .F, "ِ": .B]
        let lips: Set<Character> = ["ب", "م"]
        var result: [(Viseme, Double)] = []
        let letters = Array(word)
        for (index, c) in letters.enumerated() {
            if let mark = marks[c] {
                result.append((mark, 1.2))
                continue
            }
            if c.unicodeScalars.allSatisfy({ (0x064B ... 0x065F).contains($0.value) }) { continue } // other diacritics
            if let vowel = longVowels[c], index > 0 {
                result.append((vowel, 1.5))
                continue
            }
            let viseme: Viseme = if lips.contains(c) {
                .A
            } else if c == "ف" {
                .G
            } else if c == "ل" {
                .H
            } else if c == "و" {
                .F
            } else {
                .B
            }
            result.append((viseme, 0.8))
            let next = index + 1 < letters.count ? letters[index + 1] : nil
            if let next, longVowels[next] == nil, marks[next] == nil, index + 1 < letters.count - 1 { result.append((.C, 0.9)) }
        }
        return result
    }

    static func spelledNumber(_ digits: String) -> String {
        let names = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return digits.compactMap { $0.wholeNumberValue.map { names[$0] } }.joined()
    }
}

/// Automatic lip sync: spoken words → mouth-shape keys (and jaw / width keys) on a character.
public enum LipSync {
    public struct Shape: Hashable, Sendable {
        public var time: Double
        public var viseme: Viseme
    }

    /// Mouth shapes over time for `words`. Words the phonemizer can't read fall back to `loudness`
    /// (per-frame 0…1 at `fps`): open when loud, closed when quiet. Pauses rest the mouth.
    public static func shapes(for words: [TimelineWord], language: String, loudness: [Double] = [], fps: Int = 30,
                              phonemizer: Phonemizer = .shared) -> [Shape] {
        var result: [Shape] = []
        for (index, word) in words.enumerated() {
            let duration = max(word.end - word.start, 0.04)
            var parts = phonemizer.visemes(for: word.text, language: language)
            if parts.isEmpty {
                parts = loudnessShapes(from: word.start, to: word.end, loudness: loudness, fps: fps)
            }
            // Don't show more than ~15 shapes a second: merge tiny phonemes into their neighbours.
            let maxShapes = max(Int(duration * 15), 1)
            if parts.count > maxShapes { parts = thin(parts, to: maxShapes) }
            let total = parts.reduce(0) { $0 + $1.1 }
            var time = word.start
            for (viseme, weight) in parts {
                if result.last?.viseme != viseme { result.append(Shape(time: time, viseme: viseme)) }
                time += duration * weight / max(total, 1e-9)
            }
            // Rest in pauses (not between words spoken together).
            let nextStart = index + 1 < words.count ? words[index + 1].start : .infinity
            if nextStart - word.end > 0.18 { result.append(Shape(time: word.end, viseme: .X)) }
        }
        return result
    }

    static func thin(_ parts: [(Viseme, Double)], to count: Int) -> [(Viseme, Double)] {
        var parts = parts
        while parts.count > count {
            let index = parts.indices.min { parts[$0].1 < parts[$1].1 } ?? 0
            let neighbour = index + 1 < parts.count ? index + 1 : index - 1
            parts[neighbour].1 += parts[index].1
            parts.remove(at: index)
        }
        return parts
    }

    /// Open/closed from the voice's loudness (the fallback for words without known sounds).
    static func loudnessShapes(from start: Double, to end: Double, loudness: [Double], fps: Int) -> [(Viseme, Double)] {
        guard !loudness.isEmpty, fps > 0 else { return [(.C, 1), (.B, 1)] }
        let first = max(Int(start * Double(fps)), 0)
        let last = min(Int(end * Double(fps)), loudness.count - 1)
        guard last >= first else { return [(.C, 1)] }
        return (first ... last).map { frame in
            let level = loudness[frame]
            let viseme: Viseme = level > 0.65 ? .D : (level > 0.35 ? .C : (level > 0.12 ? .B : .A))
            return (viseme, 1)
        }
    }

    /// Keys on `character`: `mouth` (stepped shapes) plus `jawOpen` and `mouthWide` (eased) — replacing keys of those
    /// properties inside the spoken range. One command, one undo step.
    public static func keys(_ shapes: [Shape], character: ObjectID, range: TimeRange, timeline: Timeline, ids: inout IDFactory) -> EditCommand? {
        guard !shapes.isEmpty else { return nil }
        var edits: [TrackEdit] = []
        let plan: [(PropertyKey, (Viseme) -> PropertyValue, Easing)] = [
            (.mouth, { .enumeration($0.rawValue) }, .step),
            (.jawOpen, { .float($0.jaw) }, .easeInOut),
            (.mouthWide, { .float($0.width) }, .easeInOut)
        ]
        for (property, value, easing) in plan {
            var track = timeline.track(for: character, property) ?? Track(id: ids.next(), target: character, property: property)
            track.removeKeys(in: range)
            for shape in shapes where range.contains(shape.time, tolerance: 1e-6) {
                track.setKey(Keyframe(time: shape.time, value: value(shape.viseme), easing: easing))
            }
            // Rest after the last word.
            track.setKey(Keyframe(time: range.end, value: value(.X), easing: easing))
            edits.append(TrackEdit(track))
        }
        return .batch("Lip sync", [.setTracks(edits)])
    }
}
