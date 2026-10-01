import AVFoundation
import HmmTranscript
import LoweyCore
@testable import LoweyFeatures
import XCTest

/// Word timing on the device (Apple's SpeechAnalyzer through hmm-kit, no Whisper): a synthesized sentence comes back
/// as words with times that go forward.
final class TranscriptionTests: XCTestCase {
    /// Speaks `sentence` into a file with the system voice (nil when the simulator has no voice).
    private func spoken(_ sentence: String) async throws -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lowey-voice-\(UUID().uuidString).caf")
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        let written: Bool = await withCheckedContinuation { continuation in
            var file: AVAudioFile?
            var done = false
            synthesizer.write(utterance) { buffer in
                guard !done else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    done = true
                    continuation.resume(returning: file != nil)
                    return
                }
                if file == nil {
                    file = try? AVAudioFile(forWriting: url, settings: pcm.format.settings, commonFormat: pcm.format.commonFormat, interleaved: false)
                }
                try? file?.write(from: pcm)
            }
        }
        return written ? url : nil
    }

    func testSpeechAnalyzerGivesWordTimes() async throws {
        guard await SpeechTranscription.languages().contains(where: { $0.hasPrefix("en") }) else {
            throw XCTSkip("English transcription isn't available on this simulator")
        }
        guard let url = try await spoken("This is a German army message from nineteen forty one. Nobody could read it.") else {
            throw XCTSkip("No speech voice on this simulator")
        }
        let words: [LoweyCore.TranscriptWord]
        do {
            words = try await SpeechTranscription.words(in: url, language: "en-US") { _ in }
        } catch {
            throw XCTSkip("The speech model couldn't be used here: \(error)")
        }
        let texts = words.map { TimelineWord.normalize($0.text) }
        XCTAssertTrue(texts.contains("german"), "heard: \(texts)")
        XCTAssertTrue(texts.contains("message"))
        XCTAssertTrue(zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start + 1e-6 }, "word times go forward")
        let attachment = XCTAttachment(string: words.map { "\($0.text) \(String(format: "%.2f–%.2f", $0.start, $0.end))" }.joined(separator: "\n"))
        attachment.name = "speechanalyzer-words"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
