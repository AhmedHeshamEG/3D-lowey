import Foundation

/// One script word matched (or not) to a spoken word.
public struct AlignedWord: Hashable, Sendable {
    /// Index in the script's words.
    public var scriptIndex: Int?
    /// Index in the transcript's words.
    public var spokenIndex: Int?
    /// 0 = identical, 1 = nothing alike.
    public var cost: Double

    public init(scriptIndex: Int?, spokenIndex: Int?, cost: Double) {
        self.scriptIndex = scriptIndex
        self.spokenIndex = spokenIndex
        self.cost = cost
    }

    public var isMatch: Bool { scriptIndex != nil && spokenIndex != nil }
}

/// Script-to-transcript alignment: word-level Needleman–Wunsch where a substitution costs the normalised edit
/// distance between the two words (so "Enigma" ≈ "enigmas", while "the" ≠ "machine"). Retake uses it to find which
/// line of the script a take covers; 3D-lowey uses it to put the script's spelling on the Words lane.
public enum ScriptAlignment {
    /// Cost of skipping a script word or a spoken word.
    public static let gapCost = 0.6

    public static func align(script: [String], spoken: [String]) -> [AlignedWord] {
        let a = script.map(TranscriptText.normalize)
        let b = spoken.map(TranscriptText.normalize)
        let rows = a.count + 1
        let columns = b.count + 1
        var score = [Double](repeating: 0, count: rows * columns)
        var move = [UInt8](repeating: 0, count: rows * columns) // 0 diag, 1 up (skip script), 2 left (skip spoken)
        for i in 1 ..< rows {
            score[i * columns] = Double(i) * gapCost
            move[i * columns] = 1
        }
        for j in 1 ..< columns {
            score[j] = Double(j) * gapCost
            move[j] = 2
        }
        if rows > 1, columns > 1 {
            for i in 1 ..< rows {
                for j in 1 ..< columns {
                    let diagonal = score[(i - 1) * columns + j - 1] + wordCost(a[i - 1], b[j - 1])
                    let up = score[(i - 1) * columns + j] + gapCost
                    let left = score[i * columns + j - 1] + gapCost
                    if diagonal <= up, diagonal <= left {
                        score[i * columns + j] = diagonal
                        move[i * columns + j] = 0
                    } else if up <= left {
                        score[i * columns + j] = up
                        move[i * columns + j] = 1
                    } else {
                        score[i * columns + j] = left
                        move[i * columns + j] = 2
                    }
                }
            }
        }
        return backtrack(move, columns: columns, a: a, b: b)
    }

    /// Walks the move table back from the bottom-right corner.
    private static func backtrack(_ move: [UInt8], columns: Int, a: [String], b: [String]) -> [AlignedWord] {
        var result: [AlignedWord] = []
        var i = a.count
        var j = b.count
        while i > 0 || j > 0 {
            switch move[i * columns + j] {
            case 0 where i > 0 && j > 0:
                result.append(AlignedWord(scriptIndex: i - 1, spokenIndex: j - 1, cost: wordCost(a[i - 1], b[j - 1])))
                i -= 1
                j -= 1
            case 1 where i > 0:
                result.append(AlignedWord(scriptIndex: i - 1, spokenIndex: nil, cost: gapCost))
                i -= 1
            default:
                result.append(AlignedWord(scriptIndex: nil, spokenIndex: j - 1, cost: gapCost))
                j -= 1
            }
        }
        return result.reversed()
    }

    /// Normalised Levenshtein distance (0…1).
    public static func wordCost(_ a: String, _ b: String) -> Double {
        if a == b { return 0 }
        let x = Array(a)
        let y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 1 }
        var previous = Array(0 ... y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1 ... x.count {
            current[0] = i
            for j in 1 ... y.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return Double(previous[y.count]) / Double(max(x.count, y.count))
    }

    /// Puts the script's spelling onto the spoken words it matches (costs below `threshold`), keeping every timing.
    public static func applyScriptSpelling(_ transcript: Transcript, script: String, threshold: Double = 0.5) -> Transcript {
        let scriptWords = TranscriptText.tokens(script)
        var copy = transcript
        for pair in align(script: scriptWords, spoken: transcript.words.map(\.text))
            where pair.cost < threshold {
            guard let scriptIndex = pair.scriptIndex, let spokenIndex = pair.spokenIndex else { continue }
            copy.words[spokenIndex].text = scriptWords[scriptIndex]
        }
        return copy
    }
}
