import Foundation
import HmmMedia
import LoweyCore

/// The export sheet's presets (docs/SPEC.md §10). Each one is a complete answer; Custom opens the details.
public enum ExportPreset: String, CaseIterable, Identifiable, Sendable, Codable {
    case youtube4K, hd1080, vertical, square, transparent, stillHD, still4K, gifLoop, model3D, captions

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .youtube4K: "YouTube 16:9 4K"
        case .hd1080: "1080p"
        case .vertical: "Shorts / Reels 9:16"
        case .square: "Square"
        case .transparent: "Transparent (HEVC alpha)"
        case .stillHD: "PNG still (HD)"
        case .still4K: "PNG still (4K)"
        case .gifLoop: "GIF loop"
        case .model3D: "3D model"
        case .captions: "Captions (.srt)"
        }
    }

    public var systemImage: String {
        switch self {
        case .youtube4K, .hd1080: "play.rectangle"
        case .vertical: "rectangle.portrait"
        case .square: "square"
        case .transparent: "square.dashed"
        case .stillHD, .still4K: "photo"
        case .gifLoop: "repeat"
        case .model3D: "cube"
        case .captions: "captions.bubble"
        }
    }

    public var kind: ExportKind {
        switch self {
        case .youtube4K, .hd1080, .vertical, .square, .transparent: .video
        case .stillHD, .still4K: .still
        case .gifLoop: .gif
        case .model3D: .model
        case .captions: .captions
        }
    }

    /// The settings the preset stands for (range, audio and quality come from the project and the sheet).
    public func settings(range: TimeRange, fps: Int) -> ExportSettings {
        switch self {
        case .youtube4K: ExportSettings(framing: .landscape, longSide: 3840, fps: fps, codec: .hevc, range: range)
        case .hd1080: ExportSettings(framing: .landscape, longSide: 1920, fps: fps, codec: .h264, range: range)
        case .vertical: ExportSettings(framing: .portrait, longSide: 1920, fps: fps, codec: .h264, range: range)
        case .square: ExportSettings(framing: .square, longSide: 1080, fps: fps, codec: .h264, range: range)
        case .transparent: ExportSettings(framing: .landscape, longSide: 1920, fps: fps, codec: .hevcAlpha, range: range, transparent: true)
        case .stillHD: ExportSettings(framing: .landscape, longSide: 1920, fps: fps, codec: .h264, range: range)
        case .still4K: ExportSettings(framing: .landscape, longSide: 3840, fps: fps, codec: .h264, range: range)
        case .gifLoop:
            ExportSettings(framing: .square, longSide: 640, fps: 15, codec: .h264,
                           range: TimeRange(start: range.start, end: min(range.end, range.start + 6)))
        case .model3D, .captions: ExportSettings(framing: .landscape, longSide: 1920, fps: fps, codec: .h264, range: range)
        }
    }
}

public enum ExportKind: String, Sendable, Codable {
    case video, still, gif, model, captions
}

/// Everything one video export needs.
public struct ExportSettings: Sendable, Hashable, Codable {
    public var framing: Framing
    /// Long side in pixels (1920 = HD, 3840 = 4K).
    public var longSide: Int
    /// 24, 25, 30 or 60.
    public var fps: Int
    public var codec: VideoCodecKind
    public var range: TimeRange
    public var transparent: Bool
    /// 0…1 (0.5 = the preset's bitrate).
    public var quality: Double

    public init(framing: Framing, longSide: Int, fps: Int, codec: VideoCodecKind, range: TimeRange, transparent: Bool = false,
                quality: Double = 0.5) {
        self.framing = framing
        self.longSide = longSide
        self.fps = fps
        self.codec = transparent ? .hevcAlpha : codec
        self.range = range
        self.transparent = transparent
        self.quality = quality
    }

    public static let frameRates = [24, 25, 30, 60]

    public var size: (width: Int, height: Int) { framing.pixelSize(longSide: longSide) }
    public var frameCount: Int { max(Int((range.duration * Double(fps)).rounded()), 1) }

    public var encodeSettings: EncodeSettings {
        EncodeSettings(width: size.width, height: size.height, fps: fps, codec: codec, quality: quality)
    }
}
