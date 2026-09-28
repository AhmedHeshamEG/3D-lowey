import AVFoundation
import Foundation
import LoweyCore
import Speech

/// Word timing with Apple's on-device SpeechAnalyzer + SpeechTranscriber (iPadOS 26). No Whisper,
/// no network except the one-time download of the language model, which the system manages.
enum SpeechService {
    enum Failure: Error, CustomStringConvertible {
        case unavailable
        case unsupported(String)
        case unreadable
        case noSpeech

        var description: String {
            switch self {
            case .unavailable: "Speech recognition isn't available on this device"
            case let .unsupported(language): "On-device transcription doesn't support \(language) yet"
            case .unreadable: "Couldn't read that audio"
            case .noSpeech: "No speech was found in that clip"
            }
        }
    }

    /// Languages offered first (Hesham's), then everything else the system supports.
    static let preferred = ["en-US", "ar-SA", "it-IT", "en-GB", "ar-EG"]

    static func supportedLanguages() async -> [String] {
        let supported = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
        let first = preferred.filter { supported.contains($0) }
        return first + supported.filter { !first.contains($0) }.sorted()
    }

    /// Words of the file at `url`, in file time. `status` reports steps ("Downloading the English model…").
    static func transcribe(_ url: URL, language: String, status: @escaping @Sendable (String) -> Void) async throws -> [TranscriptWord] {
        guard SpeechTranscriber.isAvailable else { throw Failure.unavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw Failure.unsupported(Locale.current.localizedString(forIdentifier: language) ?? language)
        }
        let transcriber = SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            status("Downloading the \(Locale.current.localizedString(forIdentifier: language) ?? language) speech model…")
            try await request.downloadAndInstall()
        }
        status("Listening…")
        // Convert to the analyzer's best format first (sample rate, channels), so any file works.
        let input = try await convertForAnalysis(url, modules: [transcriber])
        defer { if input != url { try? FileManager.default.removeItem(at: input) } }
        let file = try AVAudioFile(forReading: input)
        let collector = Task { () throws -> [TranscriptWord] in
            var words: [TranscriptWord] = []
            for try await result in transcriber.results where result.isFinal {
                for run in result.text.runs {
                    guard let range = run.audioTimeRange else { continue }
                    let text = String(result.text[run.range].characters)
                    words += TranscriptEditing.words(from: text, start: range.start.seconds, end: range.end.seconds,
                                                     confidence: run.transcriptionConfidence)
                }
            }
            return words
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let words = try await collector.value
        guard !words.isEmpty else { throw Failure.noSpeech }
        return words.sorted { $0.start < $1.start }
    }

    /// Writes the audio in the analyzer's best available format (rate and channels) to a temporary file.
    private static func convertForAnalysis(_ url: URL, modules: [any SpeechModule]) async throws -> URL {
        guard let source = try? AVAudioFile(forReading: url) else { throw Failure.unreadable }
        let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
        let rate = best?.sampleRate ?? 16000
        let fileSettings = best?.settings ?? [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1]
        if let best, source.fileFormat.sampleRate == best.sampleRate, source.fileFormat.channelCount == best.channelCount,
           source.fileFormat.commonFormat == best.commonFormat {
            return url
        }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false) else {
            throw Failure.unreadable
        }
        let mono = try AudioDecoder.decode(url, sampleRate: rate).mono
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("lowey-speech-\(UUID().uuidString).caf")
        var settings = fileSettings
        settings[AVNumberOfChannelsKey] = 1
        let file = try AVAudioFile(forWriting: output, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 65536
        var offset = 0
        while offset < mono.count {
            let count = min(chunk, mono.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { break }
            buffer.frameLength = AVAudioFrameCount(count)
            mono.withUnsafeBufferPointer { samples in
                buffer.floatChannelData![0].update(from: samples.baseAddress! + offset, count: count)
            }
            try file.write(from: buffer)
            offset += count
        }
        return output
    }
}
