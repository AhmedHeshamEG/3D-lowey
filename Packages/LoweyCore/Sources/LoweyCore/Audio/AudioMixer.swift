import Foundation

/// Decoded audio: one array of samples per channel (mono or stereo), all at `sampleRate`.
public struct PCMAudio: Hashable, Sendable {
    public var sampleRate: Double
    public var channels: [[Float]]

    public init(sampleRate: Double, channels: [[Float]]) {
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public var frameCount: Int { channels.first?.count ?? 0 }
    public var duration: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }

    /// Sample of `channel` (the last channel repeats for mono sources) at frame `index`, 0 outside.
    @inline(__always)
    public func sample(_ channel: Int, _ index: Int) -> Float {
        guard !channels.isEmpty, index >= 0, index < frameCount else { return 0 }
        return channels[min(channel, channels.count - 1)][index]
    }

    /// Mono mixdown (for analysis).
    public var mono: [Float] {
        guard channels.count > 1 else { return channels.first ?? [] }
        let scale = 1 / Float(channels.count)
        return (0 ..< frameCount).map { index in channels.reduce(0) { $0 + $1[index] } * scale }
    }
}

/// Mixes the timeline's audio clips into one stereo track, exactly as the preview plays it
/// (volume × fades × envelope). Pure and deterministic: export and tests use it.
public enum AudioMixer {
    /// Interleaved stereo samples for `range` at `sampleRate`. `sources` maps `AudioClip.file` to decoded
    /// audio at the same `sampleRate` (the app resamples on decode).
    public static func mix(_ clips: [AudioClip], sources: [String: PCMAudio], range: TimeRange, sampleRate: Double) -> [Float] {
        let frames = max(Int((range.duration * sampleRate).rounded()), 0)
        var output = [Float](repeating: 0, count: frames * 2)
        for clip in clips where !clip.muted && clip.volume > 0 {
            guard let source = sources[clip.file], source.sampleRate == sampleRate else { continue }
            let overlapStart = max(range.start, clip.start)
            let overlapEnd = min(range.end, clip.end)
            guard overlapEnd > overlapStart else { continue }
            let firstFrame = Int(((overlapStart - range.start) * sampleRate).rounded())
            let lastFrame = min(Int(((overlapEnd - range.start) * sampleRate).rounded()), frames)
            guard lastFrame > firstFrame else { continue }
            for frame in firstFrame ..< lastFrame {
                let time = range.start + Double(frame) / sampleRate
                let gain = Float(clip.gain(at: time))
                if gain == 0 { continue }
                guard let fileTime = clip.fileTime(at: time) else { continue }
                let index = Int((fileTime * sampleRate).rounded())
                output[frame * 2] += source.sample(0, index) * gain
                output[frame * 2 + 1] += source.sample(1, index) * gain
            }
        }
        for index in output.indices {
            output[index] = softClip(output[index])
        }
        return output
    }

    /// Transparent below 0.9, smoothly limited above (no hard digital clipping when clips pile up).
    @inline(__always)
    public static func softClip(_ value: Float) -> Float {
        let limit: Float = 0.9
        let magnitude = abs(value)
        guard magnitude > limit else { return value }
        let over = magnitude - limit
        let squashed = limit + (1 - limit) * (over / (over + (1 - limit)))
        return value < 0 ? -squashed : squashed
    }
}

/// Waveform drawing and audio-driven animation (the jaw fallback for lip sync).
public enum AudioAnalysis {
    /// Peak magnitude per bucket of `bucket` samples (what the timeline draws).
    public static func peaks(_ samples: [Float], bucket: Int) -> [Float] {
        guard bucket > 0, !samples.isEmpty else { return [] }
        return stride(from: 0, to: samples.count, by: bucket).map { start in
            var peak: Float = 0
            for index in start ..< min(start + bucket, samples.count) {
                peak = max(peak, abs(samples[index]))
            }
            return peak
        }
    }

    /// Loudness (RMS) per video frame at `fps`, normalised so the loudest frame is 1.
    public static func loudness(_ audio: PCMAudio, fps: Int) -> [Double] {
        let mono = audio.mono
        guard fps > 0, audio.sampleRate > 0, !mono.isEmpty else { return [] }
        let window = max(Int(audio.sampleRate / Double(fps)), 1)
        var values: [Double] = []
        values.reserveCapacity(mono.count / window + 1)
        for start in stride(from: 0, to: mono.count, by: window) {
            var sum: Double = 0
            let end = min(start + window, mono.count)
            for index in start ..< end {
                sum += Double(mono[index]) * Double(mono[index])
            }
            values.append((sum / Double(end - start)).squareRoot())
        }
        let loudest = values.max() ?? 0
        return loudest > 0 ? values.map { $0 / loudest } : values
    }
}
