import AVFoundation
import Foundation
import LoweyCore

/// A temporary voiceover for samples and tests: the device's own speech voice says each sentence at its time.
/// Hesham replaces it with his recording (Audio → Record voiceover / import) and re-transcribes.
@MainActor
enum PlaceholderVoice {
    /// Speaks `lines` (text, start seconds) into one audio file of `duration` seconds at `url` (.m4a or .caf/.wav).
    static func render(_ lines: [(String, Double)], duration: Double, to url: URL, language: String = "en-US") async throws {
        let rate = 48000.0
        var mix = [Float](repeating: 0, count: Int(duration * rate))
        let synthesizer = AVSpeechSynthesizer()
        for (text, start) in lines {
            let samples = try await speak(text, language: language, synthesizer: synthesizer, sampleRate: rate)
            let offset = Int(start * rate)
            for (index, sample) in samples.enumerated() where offset + index < mix.count {
                mix[offset + index] += sample * 0.9
            }
        }
        try write(mix, sampleRate: rate, to: url)
    }

    /// One utterance as mono float samples at `sampleRate`.
    static func speak(_ text: String, language: String, synthesizer: AVSpeechSynthesizer, sampleRate: Double) async throws -> [Float] {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.52
        return await withCheckedContinuation { continuation in
            var collected: [Float] = []
            var finished = false
            synthesizer.write(utterance) { buffer in
                guard !finished else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    finished = true
                    continuation.resume(returning: collected)
                    return
                }
                collected += convert(pcm, sampleRate: sampleRate)
            }
        }
    }

    /// Resamples one synthesiser buffer to mono float.
    nonisolated static func convert(_ buffer: AVAudioPCMBuffer, sampleRate: Double) -> [Float] {
        var output: [Float] = []
        do {
            guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: buffer.format, to: target) else { return [] }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate) + 1024
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
            var consumed = false
            _ = converter.convert(to: converted, error: nil) { _, status in
                if consumed {
                    status.pointee = .endOfStream
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if let data = converted.floatChannelData {
                output += UnsafeBufferPointer(start: data[0], count: Int(converted.frameLength))
            }
        }
        return output
    }

    static func write(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else { return }
        let settings: [String: Any] = url.pathExtension.lowercased() == "m4a"
            ? [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96000]
            : format.settings
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 16384
        var offset = 0
        while offset < samples.count {
            let count = min(chunk, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { break }
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { source in
                buffer.floatChannelData![0].update(from: source.baseAddress! + offset, count: count)
            }
            try file.write(from: buffer)
            offset += count
        }
    }
}
