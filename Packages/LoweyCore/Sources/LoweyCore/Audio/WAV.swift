import Foundation

/// 16-bit PCM WAV files (the soundtrack next to a PNG sequence, test fixtures).
public enum WAV {
    /// `samples` interleaved, `channels` per frame.
    public static func data(_ samples: [Float], channels: Int, sampleRate: Int) -> Data {
        var data = Data()
        let frames = samples.count / max(channels, 1)
        let dataSize = UInt32(frames * channels * 2)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * channels * 2))
        append(UInt16(channels * 2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        data.reserveCapacity(data.count + Int(dataSize))
        for sample in samples.prefix(frames * channels) {
            append(Int16((max(-1, min(1, sample)) * 32767).rounded()))
        }
        return data
    }

    /// Reads a 16-bit PCM WAV back (mono or stereo).
    public static func read(_ data: Data) -> PCMAudio? {
        let bytes = [UInt8](data)
        guard bytes.count >= 44, String(bytes: bytes[0 ..< 4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8 ..< 12], encoding: .ascii) == "WAVE" else { return nil }
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        var offset = 12
        var channels = 1
        var rate = 44100
        var bits = 16
        while offset + 8 <= bytes.count {
            let id = String(bytes: bytes[offset ..< offset + 4], encoding: .ascii) ?? ""
            let size = u32(offset + 4)
            let body = offset + 8
            if id == "fmt " {
                channels = u16(body + 2)
                rate = u32(body + 4)
                bits = u16(body + 14)
            } else if id == "data" {
                guard bits == 16, channels > 0 else { return nil }
                let end = min(body + size, bytes.count)
                let frames = (end - body) / (2 * channels)
                var output = [[Float]](repeating: [Float](repeating: 0, count: frames), count: channels)
                for frame in 0 ..< frames {
                    for channel in 0 ..< channels {
                        let at = body + (frame * channels + channel) * 2
                        output[channel][frame] = Float(Int16(bitPattern: UInt16(u16(at)))) / 32767
                    }
                }
                return PCMAudio(sampleRate: Double(rate), channels: output)
            }
            offset = body + size + (size & 1)
        }
        return nil
    }
}
