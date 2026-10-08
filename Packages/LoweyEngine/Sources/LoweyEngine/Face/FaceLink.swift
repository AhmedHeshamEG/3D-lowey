import ARKit
import CoreImage
import Foundation
import LoweyCore
import Network
import os
import QuartzCore
import UIKit
import Vision

/// Bonjour service the iPhone companion streams face channels to.
public enum FaceLinkService {
    public static let type = "_loweyface._tcp"
}

/// One line of the face link (newline-separated JSON): channels every time, the preview's dots and bones, and now and
/// then a small JPEG of the camera. Channels use the mirror's sides (see `FaceSolver`).
public struct FaceLinkMessage: Codable {
    /// Channel name → value.
    public var c: [String: Double]?
    /// Tracking dots, normalised picture coordinates (x, y down), flattened.
    public var p: [Double]?
    /// Bones as x1, y1, x2, y2 quadruples, flattened.
    public var b: [Double]?
    /// A small JPEG of the camera (base64).
    public var j: String?
}

/// iPad side: receives face channels from an iPhone with Face ID (ARKit face tracking — more precise than the
/// iPad's camera). Local network only.
@MainActor
public final class FaceLinkReceiver {
    public init() {}

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let logger = Logger(subsystem: "studio.h.maquette", category: "facelink")
    /// Channels (face and, when the phone sees them, hands).
    public var onChannels: (([PropertyKey: Double]) -> Void)?
    /// What the preview shows: dots, bones and (sometimes) a picture.
    public var onPreview: (([CGPoint], [(CGPoint, CGPoint)], CGImage?) -> Void)?
    public var onStatus: ((String) -> Void)?

    public var isRunning: Bool { listener != nil }

    public func start() {
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

    public func stop() {
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 18) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                var pending = buffer
                if let data { pending.append(data) }
                // Only the newest complete line matters for channels (older ones would only be drawn and replaced).
                var latest: FaceLinkMessage?
                var picture: CGImage?
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = pending[pending.startIndex ..< newline]
                    pending = Data(pending[pending.index(after: newline)...])
                    guard let message = Self.decode(line) else { continue }
                    if let jpeg = message.j, let bytes = Data(base64Encoded: jpeg), let image = UIImage(data: bytes)?.cgImage { picture = image }
                    latest = message
                }
                if let latest { self.deliver(latest, picture: picture) }
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

    /// A message line (or an older companion's plain channel dictionary).
    public static func decode(_ line: Data) -> FaceLinkMessage? {
        if let message = try? JSONDecoder().decode(FaceLinkMessage.self, from: line), message.c != nil || message.p != nil {
            return message
        }
        if let values = try? JSONDecoder().decode([String: Double].self, from: line) { return FaceLinkMessage(c: values) }
        return nil
    }

    private func deliver(_ message: FaceLinkMessage, picture: CGImage?) {
        if let values = message.c {
            var channels: [PropertyKey: Double] = [:]
            for (key, value) in values {
                channels[PropertyKey(key)] = value
            }
            onChannels?(channels)
        }
        let dots = stride(from: 0, to: (message.p?.count ?? 0) - 1, by: 2).compactMap { index -> CGPoint? in
            guard let p = message.p else { return nil }
            return CGPoint(x: p[index], y: p[index + 1])
        }
        let bones = stride(from: 0, to: (message.b?.count ?? 0) - 3, by: 4).compactMap { index -> (CGPoint, CGPoint)? in
            guard let b = message.b else { return nil }
            return (CGPoint(x: b[index], y: b[index + 1]), CGPoint(x: b[index + 2], y: b[index + 3]))
        }
        onPreview?(dots, bones, picture)
    }
}

/// iPhone side (the companion screen): ARKit face tracking (+ Vision body tracking for the hands) → channels → the iPad.
@MainActor
public final class FaceLinkSender: NSObject, ARSessionDelegate {
    override public init() {
        super.init()
    }

    private let session = ARSession()
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var lastSend: TimeInterval = 0
    private var lastPicture: TimeInterval = 0
    private var frameCount = 0
    private var hands: [String: Double] = [:]
    private var bones: [Double] = []
    private var bodyBusy = false
    private let bodyQueue = DispatchQueue(label: "studio.h.maquette.body")
    private let context = CIContext(options: [.cacheIntermediates: false])
    public var onStatus: ((String) -> Void)?
    /// The companion's own preview: the picture as sent, dots, bones.
    public var onPreview: ((CGImage?, [CGPoint], [(CGPoint, CGPoint)]) -> Void)?

    public static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    public func start() {
        guard Self.isSupported else {
            onStatus?("This iPhone has no Face ID camera")
            return
        }
        session.delegate = self
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        // Head angles relative to the phone (not to where the phone was when tracking started).
        configuration.worldAlignment = .camera
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
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

    public func stop() {
        session.pause()
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
    }

    private func connect(to endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.onStatus?("Connected. Your face drives the character")
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

    public nonisolated func session(_: ARSession, didUpdate frame: ARFrame) {
        guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let values = Self.channels(face)
        let dots = Self.dots(face, frame: frame)
        let pixels = frame.capturedImage
        nonisolated(unsafe) let buffer = pixels
        Task { @MainActor in self.frameArrived(values, dots: dots, pixels: buffer) }
    }

    private func frameArrived(_ values: [String: Double], dots: [Double], pixels: CVPixelBuffer) {
        frameCount += 1
        // The body every third frame, off the main thread (hands move slower than eyelids).
        if frameCount % 3 == 0, !bodyBusy {
            bodyBusy = true
            nonisolated(unsafe) let buffer = pixels
            bodyQueue.async { [weak self] in
                let result = Self.body(buffer)
                Task { @MainActor in
                    self?.hands = result.hands
                    self?.bones = result.bones
                    self?.bodyBusy = false
                }
            }
        }
        let now = CACurrentMediaTime()
        guard now - lastSend > 1.0 / 45 else { return }
        lastSend = now
        var channels = values
        for (key, value) in hands {
            channels[key] = value
        }
        var message = FaceLinkMessage(c: channels, p: dots, b: bones)
        var picture: CGImage?
        if now - lastPicture > 1.0 / 8 {
            lastPicture = now
            picture = preview(pixels)
            if let picture, let jpeg = UIImage(cgImage: picture).jpegData(compressionQuality: 0.5) { message.j = jpeg.base64EncodedString() }
        }
        onPreview?(picture, Self.points(dots), Self.segments(bones))
        guard let connection, var data = try? JSONEncoder().encode(message) else { return }
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    /// The camera picture upright (portrait) and mirrored, small.
    private func preview(_ pixels: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixels).oriented(.leftMirrored)
        let scale = 200 / max(image.extent.width, 1)
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(small, from: small.extent)
    }

    public static func points(_ flat: [Double]) -> [CGPoint] {
        stride(from: 0, to: flat.count - 1, by: 2).map { CGPoint(x: flat[$0], y: flat[$0 + 1]) }
    }

    public static func segments(_ flat: [Double]) -> [(CGPoint, CGPoint)] {
        stride(from: 0, to: flat.count - 3, by: 4).map { (CGPoint(x: flat[$0], y: flat[$0 + 1]), CGPoint(x: flat[$0 + 2], y: flat[$0 + 3])) }
    }

    /// Hands and bones from the camera picture (portrait, then mirrored so sides match the preview).
    public nonisolated static func body(_ pixels: CVPixelBuffer) -> (hands: [String: Double], bones: [Double]) {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .leftMirrored)
        guard (try? handler.perform([request])) != nil, let body = request.results?.first else { return ([:], []) }
        func joint(_ name: VNHumanBodyPoseObservation.JointName) -> BodySolver.Joint? {
            guard let point = try? body.recognizedPoint(name) else { return nil }
            return BodySolver.Joint(x: Double(point.location.x), y: Double(point.location.y), confidence: Double(point.confidence))
        }
        let channels = BodySolver.channels(
            BodySolver.Arm(shoulder: joint(.leftShoulder), wrist: joint(.leftWrist)),
            BodySolver.Arm(shoulder: joint(.rightShoulder), wrist: joint(.rightWrist))
        )
        var hands: [String: Double] = [:]
        for (key, value) in channels {
            hands[key.rawValue] = value
        }
        let pairs: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist)
        ]
        var bones: [Double] = []
        for (a, b) in pairs {
            guard let p = joint(a), let q = joint(b), p.confidence > 0.3, q.confidence > 0.3 else { continue }
            bones += [p.x, 1 - p.y, q.x, 1 - q.y]
        }
        return (hands, bones)
    }

    /// A few dozen points of the face mesh, where they are in the (mirrored, portrait) picture.
    public nonisolated static func dots(_ face: ARFaceAnchor, frame: ARFrame) -> [Double] {
        let vertices = face.geometry.vertices
        let viewport = CGSize(width: 1, height: 1)
        var result: [Double] = []
        for index in stride(from: 0, to: vertices.count, by: 18) {
            let local = vertices[index]
            let world = face.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
            let point = frame.camera.projectPoint(SIMD3<Float>(world.x, world.y, world.z), orientation: .portrait, viewportSize: viewport)
            // Mirrored like the preview.
            result += [Double(1 - point.x), Double(point.y)]
        }
        return result
    }

    /// ARKit blend shapes → Lowey face channels, with the mirror's sides (your left eye is the one on the left of the
    /// preview; turning to your left turns the character to the stage's left).
    public nonisolated static func channels(_ face: ARFaceAnchor) -> [String: Double] {
        func shape(_ key: ARFaceAnchor.BlendShapeLocation) -> Double { face.blendShapes[key]?.doubleValue ?? 0 }
        let brows = shape(.browInnerUp) * 0.6 + (shape(.browOuterUpLeft) + shape(.browOuterUpRight)) * 0.3
            - (shape(.browDownLeft) + shape(.browDownRight)) * 0.5
        let smile = (shape(.mouthSmileLeft) + shape(.mouthSmileRight)) / 2 - (shape(.mouthFrownLeft) + shape(.mouthFrownRight)) / 2
        let wide = (shape(.mouthStretchLeft) + shape(.mouthStretchRight)) / 2 - shape(.mouthPucker) - shape(.mouthFunnel) * 0.5
        // Looking to your right is looking to the preview's right.
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
            // The Blob's cartoon dials: eyes popping wide, brows knitting (angry) or lifting in the middle (worried).
            PropertyKey.eyeWide.rawValue: (shape(.eyeWideLeft) + shape(.eyeWideRight)) / 2,
            PropertyKey.browAngle.rawValue: max(-1, min(1, (shape(.browDownLeft) + shape(.browDownRight)) / 2 - shape(.browInnerUp))),
            // The face's +x is your left: turning to your left is a positive turn about y, which on the mirror is to
            // the left (negative for the character). Tilts likewise.
            PropertyKey.headYaw.rawValue: -euler.y,
            PropertyKey.headPitch.rawValue: -euler.x,
            PropertyKey.headRoll.rawValue: -euler.z
        ]
    }
}

private extension simd_float4x4 {
    var rotationQuaternion: simd_quatf { simd_quatf(self) }
}
