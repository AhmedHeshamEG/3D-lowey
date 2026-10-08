#if canImport(AVFoundation)
    import AVFoundation
    import CoreVideo
    import Foundation

    public enum EncodeError: Error, Equatable, CustomStringConvertible {
        case invalidSettings
        case writer(String)
        case stalled

        public var description: String {
            switch self {
            case .invalidSettings: "The export size must be even and the frame rate above zero."
            case let .writer(reason): "The video writer failed: \(reason)"
            case .stalled: "The encoder stopped accepting frames."
            }
        }
    }

    /// Hardware H.264 / HEVC / HEVC-with-alpha / ProRes encoding with an interleaved AAC sound track.
    ///
    /// Frames are rendered straight into the encoder's own pixel buffers (`makePixelBuffer()`: IOSurface-backed and
    /// Metal-compatible, so a Metal renderer writes into them with no copy), appended in order at a fixed rate.
    /// Confine an instance to one actor.
    public final class VideoEncoder {
        public let settings: EncodeSettings
        public let url: URL
        private let writer: AVAssetWriter
        private let input: AVAssetWriterInput
        private let adaptor: AVAssetWriterInputPixelBufferAdaptor
        private let audioInput: AVAssetWriterInput?
        private let audioFormat: CMAudioFormatDescription?
        private let audio: [Float]
        private var audioWritten = 0

        /// `audio`: interleaved stereo Float32 at `settings.audioSampleRate`, covering the whole export (or nil).
        public init(url: URL, settings: EncodeSettings, audio: [Float]? = nil) throws {
            guard settings.isValid else { throw EncodeError.invalidSettings }
            self.settings = settings
            self.url = url
            try? FileManager.default.removeItem(at: url)
            writer = try AVAssetWriter(outputURL: url, fileType: settings.codec.hasAlpha ? .mov : .mp4)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(settings))
            input.expectsMediaDataInRealTime = false
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: settings.width,
                kCVPixelBufferHeightKey as String: settings.height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
            ])
            guard writer.canAdd(input) else { throw EncodeError.writer("can't add the video track") }
            writer.add(input)
            self.audio = audio ?? []
            if let audio, !audio.isEmpty {
                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: settings.audioSampleRate,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 192_000
                ])
                audioInput.expectsMediaDataInRealTime = false
                guard writer.canAdd(audioInput) else { throw EncodeError.writer("can't add the sound track") }
                writer.add(audioInput)
                self.audioInput = audioInput
                audioFormat = Self.pcmFormat(sampleRate: settings.audioSampleRate)
            } else {
                audioInput = nil
                audioFormat = nil
            }
            guard writer.startWriting() else { throw EncodeError.writer(writer.error?.localizedDescription ?? "couldn't start") }
            writer.startSession(atSourceTime: .zero)
        }

        private static func videoSettings(_ settings: EncodeSettings) -> [String: Any] {
            let codec: AVVideoCodecType = switch settings.codec {
            case .h264: .h264
            case .hevc: .hevc
            case .hevcAlpha: .hevcWithAlpha
            case .prores4444: .proRes4444
            }
            var output: [String: Any] = [AVVideoCodecKey: codec, AVVideoWidthKey: settings.width, AVVideoHeightKey: settings.height]
            if settings.codec != .prores4444 {
                output[AVVideoCompressionPropertiesKey] = [
                    AVVideoAverageBitRateKey: settings.bitrate,
                    AVVideoExpectedSourceFrameRateKey: settings.fps,
                    AVVideoMaxKeyFrameIntervalKey: settings.keyframeInterval
                ]
            }
            return output
        }

        private static func pcmFormat(sampleRate: Int) -> CMAudioFormatDescription? {
            var description = AudioStreamBasicDescription(
                mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
                mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
            )
            var format: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
                                           magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
            return format
        }

        /// A pixel buffer from the encoder's pool (IOSurface-backed, Metal-compatible), to render the next frame into.
        public func makePixelBuffer() throws -> CVPixelBuffer {
            guard let pool = adaptor.pixelBufferPool else { throw EncodeError.writer(writer.error?.localizedDescription ?? "no buffer pool") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw EncodeError.writer("no pixel buffer") }
            return buffer
        }

        /// Appends frame number `frame` (0-based) and the sound up to its end.
        public func append(_ buffer: CVPixelBuffer, frame: Int) async throws {
            try await waitUntilReady(input)
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(settings.fps))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw EncodeError.writer(writer.error?.localizedDescription ?? "couldn't append frame \(frame)")
            }
            let audioEnd = Int((Double(frame + 1) / Double(settings.fps) * Double(settings.audioSampleRate)).rounded())
            try await appendAudio(upTo: audioEnd)
        }

        private func waitUntilReady(_ input: AVAssetWriterInput) async throws {
            var waited = 0
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(4))
                waited += 1
                if waited > 5000 { throw EncodeError.stalled }
            }
        }

        private func appendAudio(upTo frameLimit: Int) async throws {
            guard let audioInput, let audioFormat else { return }
            let limit = min(frameLimit, audio.count / 2)
            while audioWritten < limit {
                try await waitUntilReady(audioInput)
                let count = min(limit - audioWritten, 4096)
                let bytes = count * 8
                var block: CMBlockBuffer?
                CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
                                                   blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                   dataLength: bytes, flags: 0, blockBufferOut: &block)
                guard let block else { throw EncodeError.writer("no audio buffer") }
                let start = audioWritten * 2
                audio.withUnsafeBufferPointer { samples in
                    guard let base = samples.baseAddress else { return }
                    _ = CMBlockBufferReplaceDataBytes(with: base + start, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
                }
                var sample: CMSampleBuffer?
                CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                    allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: audioFormat, sampleCount: count,
                    presentationTimeStamp: CMTime(value: CMTimeValue(audioWritten), timescale: CMTimeScale(settings.audioSampleRate)),
                    packetDescriptions: nil, sampleBufferOut: &sample
                )
                guard let sample, audioInput.append(sample) else {
                    throw EncodeError.writer(writer.error?.localizedDescription ?? "couldn't append sound")
                }
                audioWritten += count
            }
        }

        /// Writes the rest of the sound and closes the file.
        public func finish() async throws {
            try await appendAudio(upTo: audio.count / 2)
            audioInput?.markAsFinished()
            input.markAsFinished()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writer.finishWriting { continuation.resume() }
            }
            guard writer.status == .completed else {
                throw EncodeError.writer(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
            }
        }

        /// Abandons the file.
        public func cancel() {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Reads what a media file contains (for `ExportVerification`).
    public enum MediaInspector {
        public static func facts(of url: URL) async throws -> MediaFacts {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            var width = 0
            var height = 0
            var frames = 0
            var alpha = false
            if let track = videoTracks.first {
                let size = try await track.load(.naturalSize)
                width = Int(size.width.rounded())
                height = Int(size.height.rounded())
                frames = try await countFrames(asset: asset, track: track)
                let descriptions = try await track.load(.formatDescriptions)
                alpha = descriptions.contains { description in
                    let codec = CMFormatDescriptionGetMediaSubType(description)
                    let hasAlphaExtension = (CMFormatDescriptionGetExtension(description,
                                                                             extensionKey: kCMFormatDescriptionExtension_ContainsAlphaChannel)
                            as? Bool) ?? false
                    return hasAlphaExtension || codec == kCMVideoCodecType_AppleProRes4444
                }
            }
            return MediaFacts(duration: duration, frameCount: frames, width: width, height: height, hasAudio: !audioTracks.isEmpty,
                              hasAlpha: alpha)
        }

        /// Counts the samples of a video track (exact, unlike duration × nominal frame rate).
        private static func countFrames(asset: AVURLAsset, track: AVAssetTrack) async throws -> Int {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return 0 }
            reader.add(output)
            guard reader.startReading() else { return 0 }
            var count = 0
            while let sample = output.copyNextSampleBuffer() {
                if CMSampleBufferGetNumSamples(sample) > 0 { count += 1 }
            }
            return count
        }

        /// Verifies an export; returns the problems (empty = good).
        public static func verify(_ url: URL, expected: ExportExpectation) async throws -> [String] {
            try await ExportVerification.problems(facts(of: url), expected: expected)
        }
    }
#endif
