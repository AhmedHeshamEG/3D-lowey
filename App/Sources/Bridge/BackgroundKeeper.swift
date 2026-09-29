import AVFoundation
import os
import UIKit
import UserNotifications

/// Keeps 3D-lowey running while it is in the background or the iPad is locked, so the laptop bridge (Claude,
/// lowey-mcp) keeps answering. iOS suspends a background app within seconds unless it plays audio, so while the bridge
/// is on and the app is away it plays silence, mixed with anything else (your music keeps playing).
@MainActor
final class BackgroundKeeper {
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "bridge")

    func start() {
        guard engine == nil else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            // A voiceover being recorded keeps its own category (and keeps the app awake by itself).
            if session.category != .playAndRecord {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let hardware = engine.mainMixerNode.outputFormat(forBus: 0)
            let format = hardware.sampleRate > 0 ? hardware : AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else { return }
            silence.frameLength = silence.frameCapacity
            if let channels = silence.floatChannelData {
                for channel in 0 ..< Int(format.channelCount) {
                    channels[channel].update(repeating: 0, count: Int(silence.frameLength))
                }
            }
            player.scheduleBuffer(silence, at: nil, options: .loops)
            try engine.start()
            player.play()
            self.engine = engine
        } catch {
            logger.error("Background audio: \(error.localizedDescription)")
        }
        // A call or Siri stops the silence: start it again when they're done.
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                                          queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw.flatMap(AVAudioSession.InterruptionType.init) == .ended else { return }
            Task { @MainActor in
                guard let self, self.engine != nil else { return }
                self.stop()
                self.start()
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine?.stop()
        engine = nil
    }
}

/// The "bridge is on" notice (like a VPN app's): posted when the app leaves the screen with the bridge on, removed when
/// you come back. Also tells you when Claude proposes a change while the app is away.
@MainActor
enum BridgeNotice {
    private static let onID = "bridge.on"
    private static let proposalID = "bridge.proposal"

    static func requestPermission() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    static func showOn(address: String) {
        let content = UNMutableNotificationContent()
        content.title = "Bridge on"
        content.body = "Claude can reach 3D-lowey at \(address), even with the screen locked. Open the app to turn it off."
        content.interruptionLevel = .passive
        post(onID, content)
    }

    static func proposal(_ title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Claude proposes a change"
        content.body = "\(title) — open 3D-lowey to answer."
        content.sound = .default
        post(proposalID, content)
    }

    static func clear() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [onID, proposalID])
        center.removePendingNotificationRequests(withIdentifiers: [onID, proposalID])
    }

    private static func post(_ id: String, _ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
