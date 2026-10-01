import Foundation
import HmmTranscript
import LoweyCore

/// Word timings from a recording, on the iPad (Apple's speech recogniser through hmm-kit; the engine is chosen per
/// language at run time).
enum SpeechTranscription {
    static let engines: [any TranscriptionEngine] = [SpeechAnalyzerEngine()]

    /// Languages offered in the transcript menu, best first.
    static func languages() async -> [String] {
        await TranscriptionEngineSelector.languages(among: engines)
    }

    /// The words of `url` in file time.
    static func words(in url: URL, language: String, status: @escaping TranscriptionStatus) async throws -> [LoweyCore.TranscriptWord] {
        guard let engine = await TranscriptionEngineSelector.engine(for: language, among: engines) else {
            throw TranscriptionError.unsupported(language: language)
        }
        let transcript = try await engine.transcribe(url, language: language, status: status)
        return transcript.words.map { LoweyCore.TranscriptWord(text: $0.text, start: $0.start, end: $0.end, confidence: $0.confidence) }
    }
}
