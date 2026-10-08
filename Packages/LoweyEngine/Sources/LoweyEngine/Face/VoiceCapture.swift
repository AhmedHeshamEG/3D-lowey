@preconcurrency import AVFoundation
import Foundation
import LoweyCore
import os

/// Listens to the microphone and says what mouth the sound makes, a few dozen times a second (`VoiceSolver`). Nothing
/// is recorded or kept: the samples are measured and dropped.
@MainActor
public final class VoiceCapture {
    public init() {}

    private let engine = AVAudioEngine()
    private var sink: AVAudioSinkNode?
    private let logger = Logger(subsystem: "studio.h.maquette", category: "voice")
    public private(set) var isRunning = false
    /// Called on the main actor with each new mouth.
    public var onMouth: (@MainActor @Sendable (VoiceSolver.Mouth) -> Void)?

    public static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceCaptureError.noMicrophone }
        let listener = VoiceListener(sampleRate: format.sampleRate) { [weak self] mouth in
            Task { @MainActor in self?.onMouth?(mouth) }
        }
        let sink = AVAudioSinkNode { _, frames, buffers -> OSStatus in
            listener.hear(buffers, frames: Int(frames))
            return noErr
        }
        engine.attach(sink)
        engine.connect(engine.inputNode, to: sink, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.detach(sink)
            throw error
        }
        self.sink = sink
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        engine.stop()
        if let sink { engine.detach(sink) }
        sink = nil
        isRunning = false
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            logger.error("Audio session: \(error.localizedDescription)")
        }
    }

    public enum VoiceCaptureError: Error, CustomStringConvertible {
        case noMicrophone

        public var description: String { "No microphone" }
    }
}

/// Copies each audio buffer's first channel off the audio thread and measures it on its own queue.
private final class VoiceListener: @unchecked Sendable {
    // Proof: `stream` is only touched on `queue` (serial); `deliver` is Sendable and immutable.
    private var stream: VoiceStream
    private let queue = DispatchQueue(label: "studio.h.maquette.voice")
    private let deliver: @Sendable (VoiceSolver.Mouth) -> Void

    init(sampleRate: Double, deliver: @escaping @Sendable (VoiceSolver.Mouth) -> Void) {
        stream = VoiceStream(sampleRate: sampleRate)
        self.deliver = deliver
    }

    func hear(_ buffers: UnsafePointer<AudioBufferList>, frames: Int) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffers))
        guard frames > 0, let first = list.first, let data = first.mData, Int(first.mDataByteSize) >= frames * MemoryLayout<Float>.size else { return }
        let samples = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: frames))
        queue.async { [self] in
            if let mouth = stream.hear(samples) { deliver(mouth) }
        }
    }
}
