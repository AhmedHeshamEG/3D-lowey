import ARKit
import Foundation
import LoweyCore
import LoweyRender
import Network
import os
import QuartzCore
import UIKit

/// Bonjour service the iPhone companion streams face channels to.
enum FaceLinkService {
    static let type = "_loweyface._tcp"
}

/// iPad side: receives face channels from an iPhone with Face ID (ARKit face tracking — more precise than the
/// iPad's camera). Newline-separated JSON objects of channel → value, local network only.
@MainActor
final class FaceLinkReceiver {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "facelink")
    var onChannels: (([PropertyKey: Double]) -> Void)?
    var onStatus: ((String) -> Void)?

    var isRunning: Bool { listener != nil }

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: UIDevice.current.name, type: FaceLinkService.type)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready: self?.onStatus?("Waiting for the iPhone…")
                    case let .failed(error): self?.onStatus?("Face link failed: \(error.localizedDescription)")
                    default: break
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            logger.error("Face link: \(error.localizedDescription)")
            onStatus?("Couldn't start the face link")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections {
            connection.cancel()
        }
        connections = []
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        onStatus?("iPhone connected")
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                var pending = buffer
                if let data { pending.append(data) }
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = pending[pending.startIndex ..< newline]
                    pending = Data(pending[pending.index(after: newline)...])
                    if let values = try? JSONDecoder().decode([String: Double].self, from: line) {
                        var channels: [PropertyKey: Double] = [:]
                        for (key, value) in values {
                            channels[PropertyKey(key)] = value
                        }
                        self.onChannels?(channels)
                    }
                }
                if complete || error != nil {
                    connection.cancel()
                    self.connections.removeAll { $0 === connection }
                    self.onStatus?("iPhone disconnected")
                } else {
                    self.receive(on: connection, buffer: pending)
                }
            }
        }
    }
}

/// iPhone side (the companion screen): ARKit face tracking → channels → the iPad.
@MainActor
final class FaceLinkSender: NSObject, ARSessionDelegate {
    private let session = ARSession()
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var lastSend: TimeInterval = 0
    var onStatus: ((String) -> Void)?

    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    func start() {
        guard Self.isSupported else {
            onStatus?("This iPhone has no Face ID camera")
            return
        }
        session.delegate = self
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        session.run(configuration)
        let browser = NWBrowser(for: .bonjour(type: FaceLinkService.type, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, self.connection == nil, let result = results.first else { return }
                self.connect(to: result.endpoint)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        onStatus?("Looking for your iPad…")
    }

    func stop() {
        session.pause()
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
    }

    private func connect(to endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.onStatus?("Connected — your face drives the character")
                case .failed, .cancelled:
                    self?.connection = nil
                    self?.onStatus?("Looking for your iPad…")
                default: break
                }
            }
        }
        connection.start(queue: .main)
        self.connection = connection
    }

    nonisolated func session(_: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let values = Self.channels(face)
        Task { @MainActor in self.send(values) }
    }

    private func send(_ values: [String: Double]) {
        let now = CACurrentMediaTime()
        guard let connection, now - lastSend > 1.0 / 45, var data = try? JSONEncoder().encode(values) else { return }
        lastSend = now
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    /// ARKit blend shapes → Lowey face channels.
    nonisolated static func channels(_ face: ARFaceAnchor) -> [String: Double] {
        func shape(_ key: ARFaceAnchor.BlendShapeLocation) -> Double { face.blendShapes[key]?.doubleValue ?? 0 }
        let brows = shape(.browInnerUp) * 0.6 + (shape(.browOuterUpLeft) + shape(.browOuterUpRight)) * 0.3
            - (shape(.browDownLeft) + shape(.browDownRight)) * 0.5
        let smile = (shape(.mouthSmileLeft) + shape(.mouthSmileRight)) / 2 - (shape(.mouthFrownLeft) + shape(.mouthFrownRight)) / 2
        let wide = (shape(.mouthStretchLeft) + shape(.mouthStretchRight)) / 2 - shape(.mouthPucker) - shape(.mouthFunnel) * 0.5
        let lookX = (shape(.eyeLookInLeft) + shape(.eyeLookOutRight) - shape(.eyeLookOutLeft) - shape(.eyeLookInRight)) / 2
        let lookY = (shape(.eyeLookUpLeft) + shape(.eyeLookUpRight) - shape(.eyeLookDownLeft) - shape(.eyeLookDownRight)) / 2
        let rotation = Quat(face.transform.rotationQuaternion)
        let euler = rotation.eulerDegrees
        return [
            PropertyKey.jawOpen.rawValue: shape(.jawOpen),
            PropertyKey.blinkLeft.rawValue: shape(.eyeBlinkLeft),
            PropertyKey.blinkRight.rawValue: shape(.eyeBlinkRight),
            PropertyKey.brows.rawValue: max(-1, min(1, brows)),
            PropertyKey.smile.rawValue: max(-1, min(1, smile)),
            PropertyKey.mouthWide.rawValue: max(-1, min(1, wide)),
            PropertyKey.lookX.rawValue: lookX,
            PropertyKey.lookY.rawValue: lookY,
            PropertyKey.headYaw.rawValue: euler.y,
            PropertyKey.headPitch.rawValue: -euler.x,
            PropertyKey.headRoll.rawValue: euler.z
        ]
    }
}

private extension simd_float4x4 {
    var rotationQuaternion: simd_quatf { simd_quatf(self) }
}
