import Foundation

/// The codecs the hmm. apps write.
public enum VideoCodecKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case h264
    case hevc
    /// HEVC with an alpha channel (.mov): transparent exports.
    case hevcAlpha
    /// ProRes 4444 (.mov): editing masters with alpha.
    case prores4444

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .hevcAlpha: "HEVC with transparency"
        case .prores4444: "ProRes 4444"
        }
    }

    public var hasAlpha: Bool { self == .hevcAlpha || self == .prores4444 }

    /// .mp4 for the delivery codecs, .mov when alpha or ProRes needs it.
    public var fileExtension: String { hasAlpha ? "mov" : "mp4" }

    /// Average bits per pixel per frame for a good-looking delivery file.
    var bitsPerPixel: Double {
        switch self {
        case .h264: 0.12
        case .hevc, .hevcAlpha: 0.08
        case .prores4444: 1.2
        }
    }
}

/// Everything an encode session needs to know.
public struct EncodeSettings: Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var fps: Int
    public var codec: VideoCodecKind
    /// "Quality" slider 0…1 (0.5 = the default bitrate, 1 = twice it).
    public var quality: Double
    /// Stereo interleaved audio sample rate (when there is audio).
    public var audioSampleRate: Int

    public init(width: Int, height: Int, fps: Int, codec: VideoCodecKind, quality: Double = 0.5, audioSampleRate: Int = 48000) {
        self.width = width
        self.height = height
        self.fps = fps
        self.codec = codec
        self.quality = quality
        self.audioSampleRate = audioSampleRate
    }

    /// Target average bitrate in bits per second.
    public var bitrate: Int {
        let factor = 0.5 + min(max(quality, 0), 1)
        return Int(Double(width * height * max(fps, 1)) * codec.bitsPerPixel * factor)
    }

    /// A keyframe every two seconds.
    public var keyframeInterval: Int { max(fps, 1) * 2 }

    /// Encoders need even dimensions.
    public var isValid: Bool { width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0 && fps > 0 }
}
