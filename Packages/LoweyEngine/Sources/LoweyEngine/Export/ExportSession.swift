import CoreGraphics
import Foundation
import HmmMedia
import LoweyCore
import os

public enum ExportError: Error, Equatable, CustomStringConvertible {
    case cancelled
    case nothingToExport
    case gpuStopped
    case verification([String])

    public var description: String {
        switch self {
        case .cancelled: "Export cancelled."
        case .nothingToExport: "There's nothing to export."
        case .gpuStopped: "The renderer stopped responding. Keep 3D-lowey in front while it exports."
        case let .verification(problems): "The exported file isn't right: " + problems.joined(separator: " ")
        }
    }
}

/// Renders a document frame by frame at a fixed timestep (never real time) into video, GIF, PNG stills or a PNG
/// sequence. Same renderer, same `ShotBuilder` as the stage: the preview is the export. Every video is verified
/// (duration, frame count, sound, size) before it counts as done.
@MainActor
public final class ExportSession {
    public let builder: ShotBuilder
    let frames: FrameRenderer
    private let videoFrames = VideoFrames(exact: true)
    private let logger = Logger(subsystem: "studio.hmm.lowey", category: "export")
    /// Where a project media file lives (videos on cards and overlays, Manim renders).
    public var mediaURL: (String) -> URL? = { _ in nil }
    /// Stills in the project's assets.
    public var stillImage: (String) -> CGImage? = { _ in nil }
    /// Whether the GPU may be used now (iOS suspends GPU work in the background: the export waits instead).
    public var canRender: () -> Bool = { true }
    public var onWaiting: (Bool) -> Void = { _ in }

    public init(document: Document, catalog: AssetCatalog, device: RenderDevice, models: ModelLibrary = .shared) throws {
        builder = ShotBuilder(document: document, catalog: catalog, models: models)
        frames = try FrameRenderer(device: device, models: models)
    }

    /// Loads every model the document uses (exports never show placeholders).
    public func loadModels() async {
        for object in builder.document.scene.objects.values {
            guard let id = object.kind.assetID, let asset = builder.catalog.manifest.asset(id) else { continue }
            _ = await builder.models.load(asset, catalog: builder.catalog)
        }
        await builder.models.waitUntilLoaded()
    }

    /// Loads the exact pictures and video frames shown at `time` (never "the nearest one").
    func prepareMedia(at time: Double, size: CGSize, framing: Framing) async {
        var images: [String: CGImage] = [:]
        let scene = builder.document.scene
        var keys: [String] = scene.objects.values.compactMap { object in
            guard case let .card(recipe) = object.kind else { return nil }
            return recipe.frameKey(at: time)
        }
        let placements = OverlayLayout.placements(in: builder.evaluate(at: time).scene, palette: builder.document.palette,
                                                  width: Double(size.width), height: Double(size.height), time: time)
        keys += placements.compactMap(\.recipe.image)
        for key in Set(keys) {
            if let (file, _) = VideoFrameKey.parse(key) {
                if let url = mediaURL(file), let image = await videoFrames.frame(key, url: url) { images[key] = image }
            } else if let image = stillImage(key) {
                images[key] = image
            }
        }
        let stills = stillImage
        builder.mediaImage = { images[$0] ?? stills($0) }
    }

    /// One frame as an image (snapshots, stills, tests).
    public func image(at time: Double, framing: Framing, longSide: Int, transparent: Bool = false) async throws -> CGImage {
        await loadModels()
        let size = framing.pixelSize(longSide: longSide)
        let cgSize = CGSize(width: size.width, height: size.height)
        await prepareMedia(at: time, size: cgSize, framing: framing)
        let request = builder.request(at: time, framing: framing, size: cgSize, frameIndex: builder.timeline.frame(for: time),
                                      transparent: transparent)
        return try await frames.image(request, width: size.width, height: size.height)
    }

    /// A video: H.264 / HEVC .mp4, or HEVC with alpha .mov when transparent. Verified before it returns.
    public func video(_ settings: ExportSettings, audio: [Float]?, to url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        await loadModels()
        let size = settings.size
        let encoder = try VideoEncoder(url: url, settings: settings.encodeSettings, audio: audio)
        do {
            for frame in 0 ..< settings.frameCount {
                try Task.checkCancellation()
                try await waitUntilRenderable()
                let time = settings.range.start + Double(frame) / Double(settings.fps)
                let buffer = try encoder.makePixelBuffer()
                let request = try await frameRequest(at: time, settings: settings)
                _ = try await frames.render(request, into: buffer)
                try await encoder.append(buffer, frame: frame)
                progress(Double(frame + 1) / Double(settings.frameCount))
                await Task.yield()
            }
            try await encoder.finish()
        } catch is CancellationError {
            encoder.cancel()
            throw ExportError.cancelled
        } catch {
            encoder.cancel()
            throw error
        }
        let expected = ExportExpectation(duration: Double(settings.frameCount) / Double(settings.fps), frameCount: settings.frameCount,
                                         width: size.width, height: size.height, audio: !(audio ?? []).isEmpty, alpha: settings.transparent)
        let problems = try await MediaInspector.verify(url, expected: expected)
        guard problems.isEmpty else { throw ExportError.verification(problems) }
        return url
    }

    /// A short looping GIF.
    public func gif(_ settings: ExportSettings, to url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        await loadModels()
        let size = settings.size
        let writer = try GIFWriter(url: url, frameCount: settings.frameCount, fps: settings.fps)
        for frame in 0 ..< settings.frameCount {
            try Task.checkCancellation()
            try await waitUntilRenderable()
            let time = settings.range.start + Double(frame) / Double(settings.fps)
            let request = try await frameRequest(at: time, settings: settings)
            try await writer.append(frames.image(request, width: size.width, height: size.height))
            progress(Double(frame + 1) / Double(settings.frameCount))
        }
        try writer.finish()
        return url
    }

    /// One PNG per frame in a folder (plus the soundtrack as WAV).
    public func pngSequence(_ settings: ExportSettings, audio: [Float]?, to folder: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        await loadModels()
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let audio, !audio.isEmpty {
            try WAV.data(audio, channels: 2, sampleRate: 48000).write(to: folder.appendingPathComponent("soundtrack.wav"))
        }
        let size = settings.size
        for frame in 0 ..< settings.frameCount {
            try Task.checkCancellation()
            try await waitUntilRenderable()
            let time = settings.range.start + Double(frame) / Double(settings.fps)
            let request = try await frameRequest(at: time, settings: settings)
            let image = try await frames.image(request, width: size.width, height: size.height)
            try ImageWriters.writePNG(image, to: folder.appendingPathComponent(String(format: "frame_%05d.png", frame + 1)))
            progress(Double(frame + 1) / Double(settings.frameCount))
        }
        return folder
    }

    private func frameRequest(at time: Double, settings: ExportSettings) async throws -> FrameRequest {
        let size = CGSize(width: settings.size.width, height: settings.size.height)
        await prepareMedia(at: time, size: size, framing: settings.framing)
        return builder.request(at: time, framing: settings.framing, size: size, frameIndex: builder.timeline.frame(for: time),
                               transparent: settings.transparent)
    }

    /// Holds the export while the app can't use the GPU (it resumes by itself when the app is back in front).
    private func waitUntilRenderable() async throws {
        guard !canRender() else { return }
        logger.notice("Export waiting: the app is not in front")
        onWaiting(true)
        defer { onWaiting(false) }
        while !canRender() {
            try await Task.sleep(for: .milliseconds(250))
        }
    }
}
