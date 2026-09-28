import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import LoweyCore
import Metal
import os
import RealityKit
import UIKit
import UniformTypeIdentifiers

public enum VideoCodec: String, CaseIterable, Sendable, Identifiable {
    case h264, hevc

    public var id: String { rawValue }
    public var title: String { self == .h264 ? "H.264" : "HEVC" }
}

public enum ExportFormat: String, CaseIterable, Sendable, Identifiable {
    /// .mp4 (or .mov with alpha when transparent).
    case video
    /// One PNG per frame in a folder.
    case pngSequence

    public var id: String { rawValue }
}

public struct VideoExportSettings: Sendable, Hashable {
    public var framings: [Framing]
    /// Long side in pixels (1920 = HD, 3840 = 4K).
    public var longSide: Int
    public var range: TimeRange
    public var fps: Int
    public var codec: VideoCodec
    public var format: ExportFormat
    public var transparent: Bool
    /// The soundtrack for `range`: interleaved stereo at `audioSampleRate` (from `AudioMixer`), or nil for silence.
    public var audio: [Float]?
    public var audioSampleRate: Int

    public init(framings: [Framing] = [.landscape, .portrait], longSide: Int = 1920, range: TimeRange, fps: Int = 30,
                codec: VideoCodec = .h264, format: ExportFormat = .video, transparent: Bool = false,
                audio: [Float]? = nil, audioSampleRate: Int = 48000) {
        self.framings = framings
        self.longSide = longSide
        self.range = range
        self.fps = fps
        self.codec = codec
        self.format = format
        self.transparent = transparent
        self.audio = audio
        self.audioSampleRate = audioSampleRate
    }

    public var frameCount: Int { max(Int((range.duration * Double(fps)).rounded()), 1) }
}

public enum ExportError: Error, CustomStringConvertible {
    case writer(String)
    case cancelled
    case nothingToExport

    public var description: String {
        switch self {
        case let .writer(reason): "The video writer failed: \(reason)"
        case .cancelled: "Export cancelled"
        case .nothingToExport: "Nothing to export"
        }
    }
}

/// Renders a scene frame by frame at a fixed timestep (never real time) and writes videos or
/// PNG sequences. It owns its own world (a second `SceneRenderer` without editor helpers), so the
/// stage stays usable while it runs, and the same document always produces the same frames.
@MainActor
public final class VideoExporter {
    private let document: Document
    private let world = SceneRenderer()
    private let rigCache: RigCache
    private let device: MTLDevice?
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "export")
    private var previousAnimated = Set<ObjectID>()

    public init(document: Document, library: LibraryProviding?, rigs: RigCache) {
        self.document = document
        rigCache = rigs
        device = MTLCreateSystemDefaultDevice()
        world.showsHelpers = false
        world.library = library
    }

    /// Where each framing looks from at `time` (the cut camera, else the scene's saved view).
    public static func camera(for animated: AnimatedScene, fallback: Viewpoint, aspect: Double) -> OffscreenRenderer.Camera {
        if let id = animated.camera, let object = animated.scene.objects[id] {
            let world = animated.scene.worldTransform(of: id)
            let framing = CameraLens(object).framing(aspect: aspect)
            let rotation = (world.rotation * Quat(angle: framing.yaw, axis: .unitY)).normalized
            return OffscreenRenderer.Camera(position: world.position.simd, orientation: rotation.simd, fieldOfView: Float(framing.fieldOfView))
        }
        let pose = StageView.cameraPose(for: fallback)
        return OffscreenRenderer.Camera(position: pose.eye.simd, orientation: pose.rotation.simd, fieldOfView: Float(pose.fieldOfView))
    }

    /// Shows the scene at `time` in the export world.
    func prepare(at time: Double, rigs: [AssetID: RigAsset], first: Bool) -> AnimatedScene {
        let animated = Animator.evaluate(document, at: time, rigs: rigs)
        let evaluated = Document(project: document.project, scene: animated.scene)
        if first {
            world.load(evaluated)
        } else {
            world.sync(evaluated, changes: ChangeSet(objects: animated.animated.union(previousAnimated)))
        }
        previousAnimated = animated.animated
        world.applyPoses(animated.poses, rigs: rigs)
        world.applyClipFallback(document.scene.timeline, at: time, skipping: Set(animated.poses.keys))
        return animated
    }

    /// Renders one frame of every framing at `time` as images (single frames, tests).
    public func images(at time: Double, framings: [Framing], longSide: Int, transparent: Bool = false) async throws -> [CGImage] {
        let session = try await makeSession(transparent: transparent)
        let rigs = rigCache.rigs(for: document, library: world.library)
        let animated = prepare(at: time, rigs: rigs, first: true)
        await world.waitForAssets()
        _ = prepare(at: time, rigs: rigs, first: false)
        var result: [CGImage] = []
        for framing in framings {
            let size = framing.pixelSize(longSide: longSide)
            let target = try session.target(width: size.width, height: size.height)
            let camera = Self.camera(for: animated, fallback: document.scene.viewpoint, aspect: framing.aspect)
            // Warm-up renders let textures and lighting settle; export frames get the same treatment once.
            for _ in 0 ..< 3 {
                try await session.render(camera: camera, target: target, world: world, deltaTime: 1 / 30)
            }
            try result.append(target.image(transparent: transparent))
        }
        return result
    }

    /// Exports every framing. Returns the files (or folders for PNG sequences) written.
    public func export(
        settings: VideoExportSettings, to folder: URL, baseName: String, progress: @escaping (Double) -> Void
    ) async throws -> [URL] {
        guard !settings.framings.isEmpty else { throw ExportError.nothingToExport }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let session = try await makeSession(transparent: settings.transparent)
        let rigs = rigCache.rigs(for: document, library: world.library)
        _ = prepare(at: settings.range.start, rigs: rigs, first: true)
        await world.waitForAssets()

        var outputs: [Output] = []
        for framing in settings.framings {
            let size = framing.pixelSize(longSide: settings.longSide)
            let name = "\(baseName) \(framing.rawValue.replacingOccurrences(of: ":", with: "x"))"
            let target = try session.target(width: size.width, height: size.height)
            switch settings.format {
            case .video:
                let ext = settings.transparent ? "mov" : "mp4"
                let url = folder.appendingPathComponent(name).appendingPathExtension(ext)
                try? FileManager.default.removeItem(at: url)
                let writer = try VideoWriter(url: url, width: size.width, height: size.height, fps: settings.fps, codec: settings.codec,
                                             alpha: settings.transparent, audio: settings.audio, audioSampleRate: settings.audioSampleRate)
                outputs.append(Output(framing: framing, target: target, url: url, writer: writer))
            case .pngSequence:
                let url = folder.appendingPathComponent(name, isDirectory: true)
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                if let audio = settings.audio, !audio.isEmpty {
                    try WAV.data(audio, channels: 2, sampleRate: settings.audioSampleRate).write(to: url.appendingPathComponent("soundtrack.wav"))
                }
                outputs.append(Output(framing: framing, target: target, url: url, writer: nil))
            }
        }

        let frames = settings.frameCount
        let step = 1 / Double(max(settings.fps, 1))
        // Settle textures and lighting once before frame 0.
        let first = prepare(at: settings.range.start, rigs: rigs, first: false)
        for output in outputs {
            let camera = Self.camera(for: first, fallback: document.scene.viewpoint, aspect: output.framing.aspect)
            for _ in 0 ..< 3 {
                try await session.render(camera: camera, target: output.target, world: world, deltaTime: step)
            }
        }
        do {
            for frame in 0 ..< frames {
                try Task.checkCancellation()
                let time = settings.range.start + Double(frame) * step
                let animated = prepare(at: time, rigs: rigs, first: false)
                for output in outputs {
                    let camera = Self.camera(for: animated, fallback: document.scene.viewpoint, aspect: output.framing.aspect)
                    try await session.render(camera: camera, target: output.target, world: world, deltaTime: step)
                    if let writer = output.writer {
                        try await writer.append(output.target, frame: frame)
                    } else {
                        let image = try output.target.image(transparent: settings.transparent)
                        let url = output.url.appendingPathComponent(String(format: "frame_%05d.png", frame + 1))
                        try Self.writePNG(image, to: url)
                    }
                }
                progress(Double(frame + 1) / Double(frames))
                // Let the UI breathe between frames.
                await Task.yield()
            }
        } catch {
            for output in outputs {
                output.writer?.cancel()
            }
            if error is CancellationError { throw ExportError.cancelled }
            throw error
        }
        for output in outputs {
            try await output.writer?.finish()
        }
        return outputs.map(\.url)
    }

    private struct Output {
        var framing: Framing
        var target: RenderTarget
        var url: URL
        var writer: VideoWriter?
    }

    private func makeSession(transparent: Bool) async throws -> RenderSession {
        guard let device else { throw OffscreenError.noMetal }
        world.environment.backdropHidden = transparent
        world.load(document)
        await world.environment.waitForEnvironment()
        let look = document.effectiveLook
        let background = transparent ? UIColor.clear : look.sky.horizon.uiColor
        let session = try RenderSession(device: device, world: world, background: background)
        session.transparent = transparent
        return session
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw OffscreenError.readback
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw OffscreenError.readback }
    }
}

/// One persistent `RealityRenderer` for a whole export (creating one per frame is far too slow).
@MainActor
final class RenderSession {
    let device: MTLDevice
    let renderer: RealityRenderer
    let camera = Entity()

    init(device: MTLDevice, world: SceneRenderer, background: UIColor) throws {
        self.device = device
        renderer = try RealityRenderer()
        renderer.entities.append(world.root)
        camera.components.set(PerspectiveCameraComponent(near: 0.02, far: 60000, fieldOfViewInDegrees: 50))
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        if let environment = world.environment.environment {
            renderer.lighting.resource = environment
            renderer.lighting.intensityExponent = world.environment.ambientExponent
        }
        renderer.cameraSettings.colorBackground = .color(background.cgColor)
        renderer.cameraSettings.antialiasing = .multisample4X
    }

    func target(width: Int, height: Int) throws -> RenderTarget {
        try RenderTarget(device: device, width: width, height: height)
    }

    /// Transparent frames: RealityRenderer always writes opaque pixels, so the frame is rendered over black and
    /// over white; alpha = 1 − (white − black) and the over-black colour is the premultiplied colour.
    var transparent = false

    func render(camera pose: OffscreenRenderer.Camera, target: RenderTarget, world: SceneRenderer, deltaTime: Double) async throws {
        guard transparent else {
            try await renderOnce(camera: pose, target: target, world: world, deltaTime: deltaTime)
            return
        }
        renderer.cameraSettings.colorBackground = .color(UIColor.white.cgColor)
        try await renderOnce(camera: pose, target: target, world: world, deltaTime: deltaTime)
        let white = target.bytes()
        renderer.cameraSettings.colorBackground = .color(UIColor.black.cgColor)
        try await renderOnce(camera: pose, target: target, world: world, deltaTime: 0)
        var black = target.bytes()
        for index in stride(from: 0, to: black.count - 3, by: 4) {
            let spread = (Int(white[index]) - Int(black[index]) + Int(white[index + 1]) - Int(black[index + 1])
                + Int(white[index + 2]) - Int(black[index + 2])) / 3
            black[index + 3] = UInt8(clamping: 255 - max(spread, 0))
        }
        target.matte = black
    }

    private func renderOnce(camera pose: OffscreenRenderer.Camera, target: RenderTarget, world: SceneRenderer, deltaTime: Double) async throws {
        camera.components.set(PerspectiveCameraComponent(near: 0.02, far: 60000, fieldOfViewInDegrees: pose.fieldOfView))
        camera.position = pose.position
        camera.orientation = pose.orientation
        world.environment.follow(camera: Vec3(pose.position))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try renderer.updateAndRender(
                    deltaTime: deltaTime, cameraOutput: target.output, whenScheduled: nil,
                    onComplete: { _ in continuation.resume() }, actionsBeforeRender: [], actionsAfterRender: []
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// A colour texture plus its RealityRenderer output.
@MainActor
final class RenderTarget {
    let texture: MTLTexture
    let output: RealityRenderer.CameraOutput
    let width: Int
    let height: Int
    /// Premultiplied BGRA of the last transparent frame (overrides the texture).
    var matte: [UInt8]?

    init(device: MTLDevice, width: Int, height: Int) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw OffscreenError.textureCreation }
        self.texture = texture
        output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        self.width = width
        self.height = height
    }

    func bytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return bytes
    }

    func copy(into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        if let matte {
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            matte.withUnsafeBytes { source in
                for row in 0 ..< height {
                    memcpy(base + row * rowBytes, source.baseAddress! + row * width * 4, width * 4)
                }
            }
            return
        }
        texture.getBytes(base, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    }

    func image(transparent: Bool) throws -> CGImage {
        let bytesPerRow = width * 4
        let bytes = transparent ? (matte ?? bytes()) : bytes()
        let alpha: CGImageAlphaInfo = transparent ? .premultipliedFirst : .noneSkipFirst
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | alpha.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { throw OffscreenError.readback }
        return image
    }
}

/// AVAssetWriter wrapper: frames in order at a fixed rate.
@MainActor
final class VideoWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let fps: Int
    private let audioInput: AVAssetWriterInput?
    private let audio: [Float]
    private let audioRate: Int
    private var audioWritten = 0
    private let audioFormat: CMAudioFormatDescription?

    init(url: URL, width: Int, height: Int, fps: Int, codec: VideoCodec, alpha: Bool, audio: [Float]? = nil, audioSampleRate: Int = 48000) throws {
        let type: AVFileType = alpha ? .mov : .mp4
        writer = try AVAssetWriter(outputURL: url, fileType: type)
        let codecType: AVVideoCodecType = alpha ? .hevcWithAlpha : (codec == .hevc ? .hevc : .h264)
        let bitsPerPixel = codec == .hevc || alpha ? 0.08 : 0.12
        let bitrate = Int(Double(width * height * fps) * bitsPerPixel)
        let settings: [String: Any] = [
            AVVideoCodecKey: codecType,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2
            ]
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(input) else { throw ExportError.writer("can't add the video track") }
        writer.add(input)
        self.audio = audio ?? []
        audioRate = audioSampleRate
        if let audio, !audio.isEmpty {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: audioSampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            audioInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(audioInput) else { throw ExportError.writer("can't add the sound track") }
            writer.add(audioInput)
            self.audioInput = audioInput
            var description = AudioStreamBasicDescription(
                mSampleRate: Float64(audioSampleRate), mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
                mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
            )
            var format: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
                                           magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
            audioFormat = format
        } else {
            audioInput = nil
            audioFormat = nil
        }
        guard writer.startWriting() else { throw ExportError.writer(writer.error?.localizedDescription ?? "couldn't start") }
        writer.startSession(atSourceTime: .zero)
        self.fps = fps
    }

    func append(_ target: RenderTarget, frame: Int) async throws {
        var waited = 0
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(4))
            waited += 1
            if waited > 5000 { throw ExportError.writer("the encoder stopped accepting frames") }
        }
        guard let pool = adaptor.pixelBufferPool else { throw ExportError.writer(writer.error?.localizedDescription ?? "no buffer pool") }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw ExportError.writer("no pixel buffer") }
        target.copy(into: buffer)
        let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw ExportError.writer(writer.error?.localizedDescription ?? "couldn't append frame \(frame)")
        }
        // Keep the sound interleaved with the picture: write audio up to the end of this frame.
        try await appendAudio(upTo: Int((Double(frame + 1) / Double(fps) * Double(audioRate)).rounded()))
    }

    private func appendAudio(upTo frameLimit: Int) async throws {
        guard let audioInput, let audioFormat else { return }
        let totalFrames = audio.count / 2
        let limit = min(frameLimit, totalFrames)
        while audioWritten < limit {
            var waited = 0
            while !audioInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(4))
                waited += 1
                if waited > 5000 { throw ExportError.writer("the audio encoder stopped accepting samples") }
            }
            let count = min(limit - audioWritten, 4096)
            let bytes = count * 8
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes, blockAllocator: kCFAllocatorDefault,
                                               customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
            guard let block else { throw ExportError.writer("no audio buffer") }
            audio.withUnsafeBufferPointer { samples in
                _ = CMBlockBufferReplaceDataBytes(with: samples.baseAddress! + audioWritten * 2, blockBuffer: block, offsetIntoDestination: 0,
                                                  dataLength: bytes)
            }
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: audioFormat, sampleCount: count,
                presentationTimeStamp: CMTime(value: CMTimeValue(audioWritten), timescale: CMTimeScale(audioRate)),
                packetDescriptions: nil, sampleBufferOut: &sample
            )
            guard let sample, audioInput.append(sample) else {
                throw ExportError.writer(writer.error?.localizedDescription ?? "couldn't append sound")
            }
            audioWritten += count
        }
    }

    func finish() async throws {
        try await appendAudio(upTo: audio.count / 2)
        audioInput?.markAsFinished()
        input.markAsFinished()
        let writer = writer
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status != .completed {
            throw ExportError.writer(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }
    }

    func cancel() {
        writer.cancelWriting()
    }
}
