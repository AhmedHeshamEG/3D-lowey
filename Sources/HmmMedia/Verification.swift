import Foundation

/// What a written media file actually contains.
public struct MediaFacts: Hashable, Sendable, Codable {
    public var duration: Double
    public var frameCount: Int
    public var width: Int
    public var height: Int
    public var hasAudio: Bool
    public var hasAlpha: Bool

    public init(duration: Double, frameCount: Int, width: Int, height: Int, hasAudio: Bool, hasAlpha: Bool = false) {
        self.duration = duration
        self.frameCount = frameCount
        self.width = width
        self.height = height
        self.hasAudio = hasAudio
        self.hasAlpha = hasAlpha
    }
}

/// What an export was supposed to contain.
public struct ExportExpectation: Hashable, Sendable {
    public var duration: Double
    public var frameCount: Int
    public var width: Int
    public var height: Int
    public var audio: Bool
    public var alpha: Bool

    public init(duration: Double, frameCount: Int, width: Int, height: Int, audio: Bool, alpha: Bool = false) {
        self.duration = duration
        self.frameCount = frameCount
        self.width = width
        self.height = height
        self.audio = audio
        self.alpha = alpha
    }
}

/// Checks a finished export against what was asked for. An export is only "done" when this finds nothing.
public enum ExportVerification {
    /// Human sentences, one per problem (empty = the file is right).
    public static func problems(_ facts: MediaFacts, expected: ExportExpectation) -> [String] {
        var problems: [String] = []
        let frameTime = expected.frameCount > 0 ? expected.duration / Double(expected.frameCount) : 0.04
        if abs(facts.duration - expected.duration) > max(frameTime * 1.5, 0.05) {
            problems.append(String(format: "It is %.2f s long instead of %.2f s.", facts.duration, expected.duration))
        }
        if abs(facts.frameCount - expected.frameCount) > 1 {
            problems.append("It has \(facts.frameCount) frames instead of \(expected.frameCount).")
        }
        if facts.width != expected.width || facts.height != expected.height {
            problems.append("It is \(facts.width)×\(facts.height) instead of \(expected.width)×\(expected.height).")
        }
        if expected.audio, !facts.hasAudio {
            problems.append("The sound is missing.")
        }
        if expected.alpha, !facts.hasAlpha {
            problems.append("The transparency is missing.")
        }
        return problems
    }
}
