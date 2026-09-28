import AVFoundation
import Foundation
import LoweyCore
import os
import QuartzCore

/// Decodes audio files to float PCM at a fixed rate (mixing, waveforms, loudness).
enum AudioDecoder {
    static let sampleRate = 48000.0

    enum DecodeError: Error, CustomStringConvertible {
        case unreadable(String)

        var description: String {
            switch self {
            case let .unreadable(reason): "Couldn't read the audio: \(reason)"
            }
        }
    }

    /// Up to two channels at `sampleRate`, deinterleaved.
    static func decode(_ url: URL, sampleRate: Double = sampleRate) throws -> PCMAudio {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        let channels = min(Int(source.channelCount), 2)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels),
                                         interleaved: false),
            let converter = AVAudioConverter(from: source, to: target)
        else { throw DecodeError.unreadable("unsupported format") }
        let chunk: AVAudioFrameCount = 16384
        var output = [[Float]](repeating: [], count: channels)
        var finished = false
        while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: chunk) else { break }
            var error: NSError?
            let status = converter.convert(to: buffer, error: &error) { _, outStatus in
                if finished {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: chunk) else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: input)
                } catch {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                if input.frameLength == 0 {
                    finished = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return input
            }
            if let error { throw DecodeError.unreadable(error.localizedDescription) }
            if let data = buffer.floatChannelData, buffer.frameLength > 0 {
                for channel in 0 ..< channels {
                    output[channel].append(contentsOf: UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength)))
                }
            }
            if status == .endOfStream || status == .error { break }
        }
        return PCMAudio(sampleRate: sampleRate, channels: output)
    }

    static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}

/// Plays the timeline's audio in the editor, locked to the same clock as the picture.
/// One player node (+ an EQ for gain above 1) per clip; gains follow fades and envelopes per frame.
@MainActor
final class AudioPlayback {
    private let engine = AVAudioEngine()
    private var nodes: [String: (player: AVAudioPlayerNode, eq: AVAudioUnitEQ)] = [:]
    private var files: [String: AVAudioFile] = [:]
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "audio")
    /// Host time (CACurrentMediaTime) at which timeline time `time` is heard.
    private(set) var anchor: (host: CFTimeInterval, time: Double)?
    var folder: URL

    init(folder: URL) {
        self.folder = folder
    }

    var isPlaying: Bool { anchor != nil }

    /// The timeline time being heard now (the picture follows this, so sound and image never drift).
    var currentTime: Double? {
        guard let anchor else { return nil }
        return anchor.time + max(CACurrentMediaTime() - anchor.host, 0)
    }

    func file(_ name: String) -> AVAudioFile? {
        if let cached = files[name] { return cached }
        let url = folder.appendingPathComponent(name)
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        files[name] = file
        return file
    }

    func forget(_ name: String) {
        files[name] = nil
    }

    /// Starts every clip that is (or will be) heard from `time` on. Returns false without audio.
    @discardableResult
    func play(_ clips: [AudioClip], from time: Double, until end: Double) -> Bool {
        stop()
        let audible = clips.filter { !$0.muted && $0.end > time && $0.start < end }
        guard !audible.isEmpty else { return false }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("Audio session: \(error.localizedDescription)")
        }
        let lead = 0.06
        let hostStart = CACurrentMediaTime() + lead
        for clip in audible {
            guard let file = file(clip.file) else { continue }
            let rate = file.processingFormat.sampleRate
            let from = max(time, clip.start)
            guard let fileTime = clip.fileTime(at: from) else { continue }
            let startFrame = AVAudioFramePosition(fileTime * rate)
            let frames = AVAudioFrameCount(max((min(clip.end, end) - from) * rate, 0))
            guard frames > 0, startFrame < file.length else { continue }
            let player = AVAudioPlayerNode()
            let eq = AVAudioUnitEQ(numberOfBands: 0)
            engine.attach(player)
            engine.attach(eq)
            engine.connect(player, to: eq, format: file.processingFormat)
            engine.connect(eq, to: engine.mainMixerNode, format: file.processingFormat)
            player.scheduleSegment(file, startingFrame: startFrame, frameCount: min(frames, AVAudioFrameCount(file.length - startFrame)), at: nil)
            nodes[clip.id] = (player, eq)
        }
        guard !nodes.isEmpty else { return false }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            logger.error("Audio engine: \(error.localizedDescription)")
            stop()
            return false
        }
        for clip in audible {
            guard let node = nodes[clip.id] else { continue }
            let delay = max(clip.start - time, 0)
            let when = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: hostStart + delay))
            apply(gain: clip.gain(at: max(time, clip.start)), to: node)
            node.player.play(at: when)
        }
        anchor = (hostStart, time)
        return true
    }

    /// Fades and envelopes, applied once per displayed frame.
    func updateGains(_ clips: [AudioClip], at time: Double) {
        for clip in clips {
            guard let node = nodes[clip.id] else { continue }
            apply(gain: clip.gain(at: time), to: node)
        }
    }

    private func apply(gain: Double, to node: (player: AVAudioPlayerNode, eq: AVAudioUnitEQ)) {
        node.player.volume = Float(min(max(gain, 0), 1))
        node.eq.globalGain = gain > 1 ? Float(min(20 * log10(gain), 24)) : 0
    }

    func stop() {
        for node in nodes.values {
            node.player.stop()
            engine.detach(node.player)
            engine.detach(node.eq)
        }
        nodes = [:]
        anchor = nil
    }

    /// A short snippet at `time` while scrubbing (hear the word you're on).
    func scrub(_ clips: [AudioClip], at time: Double) {
        guard !isPlaying else { return }
        play(clips, from: time, until: time + 0.09)
        anchor = nil
    }
}

/// Records a voiceover into the project's audio folder.
@MainActor
final class VoiceRecorder {
    private var recorder: AVAudioRecorder?
    private(set) var url: URL?

    var isRecording: Bool { recorder?.isRecording ?? false }
    var level: Float {
        recorder?.updateMeters()
        guard let power = recorder?.averagePower(forChannel: 0) else { return 0 }
        return max(0, min(1, (power + 50) / 50))
    }

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(in folder: URL, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        let url = folder.appendingPathComponent(name).appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw VoiceRecorderError.couldNotStart }
        self.recorder = recorder
        self.url = url
        return url
    }

    /// Stops and returns the file and its length.
    func stop() -> (URL, Double)? {
        guard let recorder, let url else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.url = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        return (url, AudioDecoder.duration(of: url) ?? duration)
    }

    enum VoiceRecorderError: Error, CustomStringConvertible {
        case couldNotStart

        var description: String { "The microphone didn't start" }
    }
}
