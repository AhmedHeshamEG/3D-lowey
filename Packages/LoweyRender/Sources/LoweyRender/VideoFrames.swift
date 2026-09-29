import AVFoundation
import CoreGraphics
import Foundation
import LoweyCore

/// Frames of the videos placed in a shot (media overlays, Manim renders). The exporter asks for exact frames;
/// the live stage takes the nearest one and never waits (it shows the last frame it has while the next decodes).
@MainActor
public final class VideoFrames {
    private let exact: Bool
    private var generators: [URL: AVAssetImageGenerator] = [:]
    /// Live stage: the latest decoded frame per key, and keys being decoded.
    private var ready: [String: CGImage] = [:]
    private var latest: [String: CGImage] = [:]
    private var inFlight = Set<String>()
    /// Called when a frame the stage asked for arrives.
    public var onFrame: (() -> Void)?

    public init(exact: Bool) {
        self.exact = exact
    }

    /// The frame for `key` (a `VideoFrameKey`), decoding it if needed.
    public func frame(_ key: String, url: URL) async -> CGImage? {
        guard let (_, time) = VideoFrameKey.parse(key) else { return nil }
        if let image = ready[key] { return image }
        // AVAssetImageGenerator isn't Sendable; it's only ever used from here, one request at a time per video.
        nonisolated(unsafe) let generator = generator(for: url)
        let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 6000)).image
        if let image { remember(image, key: key, url: url) }
        return image
    }

    /// For the live stage: the frame if it's decoded, else the last frame of that video (and start decoding).
    public func frameNow(_ key: String, url: URL) -> CGImage? {
        if let image = ready[key] { return image }
        if !inFlight.contains(key) {
            inFlight.insert(key)
            Task { [weak self] in
                _ = await self?.frame(key, url: url)
                self?.inFlight.remove(key)
                self?.onFrame?()
            }
        }
        return latest[url.path]
    }

    private func remember(_ image: CGImage, key: String, url: URL) {
        if ready.count > 90 { ready.removeAll() }
        ready[key] = image
        latest[url.path] = image
    }

    private func generator(for url: URL) -> AVAssetImageGenerator {
        if let known = generators[url] { return known }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        if exact {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        } else {
            let slack = CMTime(seconds: 1.0 / 30, preferredTimescale: 6000)
            generator.requestedTimeToleranceBefore = slack
            generator.requestedTimeToleranceAfter = slack
            // The stage never needs more than this; smaller frames decode and upload much faster.
            generator.maximumSize = CGSize(width: 1280, height: 1280)
        }
        generators[url] = generator
        return generator
    }
}
