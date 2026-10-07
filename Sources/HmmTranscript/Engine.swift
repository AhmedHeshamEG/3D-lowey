import Foundation

/// Which recogniser produced a transcript.
public enum TranscriptionEngineKind: String, Codable, Sendable, CaseIterable {
    /// Apple SpeechAnalyzer / SpeechTranscriber: on device, no download beyond the system's language model.
    case speechAnalyzer
    /// WhisperKit (Core ML Whisper): the optional "Accurate" model, downloaded on demand.
    case whisper

    public var displayName: String {
        switch self {
        case .speechAnalyzer: "On-device (Apple)"
        case .whisper: "Accurate (Whisper)"
        }
    }
}

public enum TranscriptionError: Error, Equatable, CustomStringConvertible {
    case unavailable
    case unsupported(language: String)
    case unreadableAudio
    case noSpeech
    case modelMissing

    public var description: String {
        switch self {
        case .unavailable: "Speech recognition isn't available on this device."
        case let .unsupported(language): "On-device transcription doesn't support \(language) yet."
        case .unreadableAudio: "Couldn't read that audio."
        case .noSpeech: "No speech was found in that recording."
        case .modelMissing: "The Accurate model isn't downloaded yet."
        }
    }
}

/// Progress reports while transcribing ("Downloading the English model…", "Listening…").
public typealias TranscriptionStatus = @Sendable (String) -> Void

/// A speech recogniser. Every engine returns the same `Transcript`, in file time.
public protocol TranscriptionEngine: Sendable {
    var kind: TranscriptionEngineKind { get }
    /// Whether this engine can transcribe `language` (BCP-47) on this device right now.
    func supports(language: String) async -> Bool
    /// Languages it offers, best first.
    func supportedLanguages() async -> [String]
    func transcribe(_ url: URL, language: String, status: @escaping TranscriptionStatus) async throws -> Transcript
}

/// Picks the engine for a language: Apple's on-device recogniser when it supports the language (checked at run
/// time, never assumed), otherwise the next engine that does (Whisper, when the app ships it).
public enum TranscriptionEngineSelector {
    public static func engine(for language: String, among engines: [any TranscriptionEngine],
                              preferring preferred: TranscriptionEngineKind? = nil) async -> (any TranscriptionEngine)? {
        if let preferred, let engine = engines.first(where: { $0.kind == preferred }), await engine.supports(language: language) {
            return engine
        }
        for engine in engines where await engine.supports(language: language) {
            return engine
        }
        return nil
    }

    /// Hesham's languages first, then everything else any engine supports.
    public static let preferredLanguages = ["en-US", "ar-SA", "it-IT", "en-GB", "ar-EG"]

    public static func languages(among engines: [any TranscriptionEngine]) async -> [String] {
        var all: [String] = []
        for engine in engines {
            for language in await engine.supportedLanguages() where !all.contains(language) {
                all.append(language)
            }
        }
        let first = preferredLanguages.filter { all.contains($0) }
        return first + all.filter { !first.contains($0) }.sorted()
    }
}
