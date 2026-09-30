#if canImport(Speech) && canImport(AVFoundation)
    import AVFoundation
    import Foundation
    import Speech

    /// Apple's on-device recogniser (SpeechAnalyzer + SpeechTranscriber, iPadOS/iOS/macOS 26). The only download is
    /// the system's own language model, managed by `AssetInventory`.
    public struct SpeechAnalyzerEngine: TranscriptionEngine {
        public let kind = TranscriptionEngineKind.speechAnalyzer

        public init() {}

        public func supportedLanguages() async -> [String] {
            await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
        }

        public func supports(language: String) async -> Bool {
            guard SpeechTranscriber.isAvailable else { return false }
            return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) != nil
        }

        public func transcribe(_ url: URL, language: String, status: @escaping TranscriptionStatus) async throws -> Transcript {
            guard SpeechTranscriber.isAvailable else { throw TranscriptionError.unavailable }
            let languageName = Locale.current.localizedString(forIdentifier: language) ?? language
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
                throw TranscriptionError.unsupported(language: languageName)
            }
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                                attributeOptions: [.audioTimeRange, .transcriptionConfidence])
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                status("Downloading the \(languageName) speech model…")
                try await request.downloadAndInstall()
            }
            status("Listening…")
            let input = try await AnalysisAudio.prepare(url, modules: [transcriber])
            defer { if input != url { try? FileManager.default.removeItem(at: input) } }
            let file = try AVAudioFile(forReading: input)
            let collector = Task { () throws -> [TranscriptWord] in
                var words: [TranscriptWord] = []
                for try await result in transcriber.results where result.isFinal {
                    for run in result.text.runs {
                        guard let range = run.audioTimeRange else { continue }
                        let text = String(result.text[run.range].characters)
                        words += TranscriptText.words(from: text, start: range.start.seconds, end: range.end.seconds,
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
            guard !words.isEmpty else { throw TranscriptionError.noSpeech }
            return Transcript(words: words.sorted { $0.start < $1.start }, language: language)
        }
    }

    /// Converts any audio file to the analyser's preferred format (sample rate and channels), mono.
    enum AnalysisAudio {
        static func prepare(_ url: URL, modules: [any SpeechModule]) async throws -> URL {
            guard let source = try? AVAudioFile(forReading: url) else { throw TranscriptionError.unreadableAudio }
            let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
            if let best, source.fileFormat.sampleRate == best.sampleRate, source.fileFormat.channelCount == best.channelCount,
               source.fileFormat.commonFormat == best.commonFormat {
                return url
            }
            let rate = best?.sampleRate ?? 16000
            guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: source.processingFormat, to: target) else {
                throw TranscriptionError.unreadableAudio
            }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("hmm-speech-\(UUID().uuidString).caf")
            var settings = best?.settings ?? [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate]
            settings[AVNumberOfChannelsKey] = 1
            let destination = try AVAudioFile(forWriting: output, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let chunk: AVAudioFrameCount = 32768
            let ratio = rate / source.processingFormat.sampleRate
            while source.framePosition < source.length {
                guard let input = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: chunk) else { break }
                try source.read(into: input, frameCount: chunk)
                guard input.frameLength > 0 else { break }
                let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 64
                guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { break }
                let feeder = BufferFeeder(input)
                var conversionError: NSError?
                converter.convert(to: converted, error: &conversionError) { _, outStatus in
                    feeder.next(outStatus)
                }
                if let conversionError { throw conversionError }
                try destination.write(from: converted)
            }
            return output
        }
    }

    /// Hands one buffer to an `AVAudioConverter` input block, then reports "no data now".
    private final class BufferFeeder: @unchecked Sendable {
        // @unchecked: used only inside one synchronous `convert` call on the calling thread.
        private var buffer: AVAudioPCMBuffer?

        init(_ buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            guard let buffer else {
                status.pointee = .noDataNow
                return nil
            }
            self.buffer = nil
            status.pointee = .haveData
            return buffer
        }
    }
#endif
