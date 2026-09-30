import AVFoundation
import CoreImage
import Foundation
import LoweyCore
import os
import Vision

/// One analysed camera frame: the face (nil = no face in view), the hands, and what the preview draws.
struct FaceSample: @unchecked Sendable {
    var face: FaceLandmarks?
    /// Hand channels from body tracking (nil when this frame didn't look for the body).
    var hands: [PropertyKey: Double]?
    /// Tracking dots and bones in normalised picture coordinates (0…1, y down), as the preview shows them.
    var dots: [CGPoint]
    var bones: [(CGPoint, CGPoint)]
    /// A small mirrored picture of the camera for the preview (a few times a second).
    var preview: CGImage?
}

/// Reads your face (and upper body) from the iPad's front camera with Vision, no TrueDepth needed. Frames arrive upright
/// and mirrored (like a mirror, and like the preview), so what Vision sees is what you see.
final class FaceCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.hesham.lowey.face")
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "face")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var lastFrame: CFTimeInterval = 0
    private var lastPreview: CFTimeInterval = 0
    private var frameIndex = 0
    private var connection: AVCaptureConnection?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    /// Called on the main actor for every analysed frame.
    let onSample: @MainActor @Sendable (FaceSample) -> Void

    init(onSample: @escaping @MainActor @Sendable (FaceSample) -> Void) {
        self.onSample = onSample
        super.init()
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    @MainActor
    func start() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw FaceCaptureError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        if let connection = output.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
            self.connection = connection
        }
        session.commitConfiguration()
        // Keep frames upright whichever way the iPad is turned.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        rotation = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, change in
            guard let angle = change.newValue else { return }
            self?.queue.async { self?.applyRotation(angle) }
        }
        queue.async { [session] in session.startRunning() }
    }

    private func applyRotation(_ angle: CGFloat) {
        guard let connection, connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle else { return }
        connection.videoRotationAngle = angle
    }

    func stop() {
        rotationObservation?.invalidate()
        rotationObservation = nil
        queue.async { [session] in session.stopRunning() }
    }

    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastFrame > 1.0 / 30, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        frameIndex += 1
        let faceRequest = VNDetectFaceLandmarksRequest()
        // The body every other frame: hands move slower than eyelids.
        let bodyRequest: VNDetectHumanBodyPoseRequest? = frameIndex % 2 == 0 ? VNDetectHumanBodyPoseRequest() : nil
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
        do {
            var requests: [VNRequest] = [faceRequest]
            if let bodyRequest { requests.append(bodyRequest) }
            try handler.perform(requests)
        } catch {
            logger.error("Vision: \(error.localizedDescription)")
            return
        }
        var sample = FaceSample(face: nil, hands: nil, dots: [], bones: [], preview: nil)
        if let observation = faceRequest.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }) {
            sample.face = Self.landmarks(observation)
            sample.dots = Self.dots(observation)
        }
        if let bodyRequest {
            let body = bodyRequest.results?.first
            sample.hands = Self.hands(body)
            sample.bones = Self.bones(body)
        }
        if now - lastPreview > 1.0 / 12 {
            lastPreview = now
            sample.preview = preview(pixels)
        }
        let callback = onSample
        let finished = sample
        Task { @MainActor in callback(finished) }
    }

    /// A small copy of the frame for the preview.
    private func preview(_ pixels: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixels)
        let scale = 240 / max(image.extent.width, 1)
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(small, from: small.extent)
    }

    static func landmarks(_ observation: VNFaceObservation) -> FaceLandmarks? {
        guard let marks = observation.landmarks else { return nil }
        func points(_ region: VNFaceLandmarkRegion2D?) -> [Vec2] {
            region?.normalizedPoints.map { Vec2(Double($0.x), Double($0.y)) } ?? []
        }
        func center(_ region: VNFaceLandmarkRegion2D?) -> Vec2? {
            let values = points(region)
            guard !values.isEmpty else { return nil }
            return Vec2(values.map(\.x).reduce(0, +) / Double(values.count), values.map(\.y).reduce(0, +) / Double(values.count))
        }
        return FaceLandmarks(
            leftEye: points(marks.leftEye), rightEye: points(marks.rightEye),
            leftBrow: points(marks.leftEyebrow), rightBrow: points(marks.rightEyebrow),
            outerLips: points(marks.outerLips), innerLips: points(marks.innerLips),
            leftPupil: center(marks.leftPupil), rightPupil: center(marks.rightPupil), nose: points(marks.nose),
            yaw: observation.yaw?.doubleValue ?? 0, pitch: observation.pitch?.doubleValue ?? 0, roll: observation.roll?.doubleValue ?? 0
        )
    }

    /// Every landmark as a dot in picture space (y down).
    static func dots(_ observation: VNFaceObservation) -> [CGPoint] {
        guard let points = observation.landmarks?.allPoints?.normalizedPoints else { return [] }
        let box = observation.boundingBox
        return points.map { point in
            CGPoint(x: box.minX + point.x * box.width, y: 1 - (box.minY + point.y * box.height))
        }
    }

    static func joint(_ body: VNHumanBodyPoseObservation?, _ name: VNHumanBodyPoseObservation.JointName) -> BodySolver.Joint? {
        guard let point = try? body?.recognizedPoint(name) else { return nil }
        return BodySolver.Joint(x: Double(point.location.x), y: Double(point.location.y), confidence: Double(point.confidence))
    }

    static func hands(_ body: VNHumanBodyPoseObservation?) -> [PropertyKey: Double] {
        BodySolver.channels(
            BodySolver.Arm(shoulder: joint(body, .leftShoulder), wrist: joint(body, .leftWrist)),
            BodySolver.Arm(shoulder: joint(body, .rightShoulder), wrist: joint(body, .rightWrist))
        )
    }

    /// Shoulders, arms and neck as lines for the preview.
    static func bones(_ body: VNHumanBodyPoseObservation?) -> [(CGPoint, CGPoint)] {
        guard let body else { return [] }
        let pairs: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.neck, .nose)
        ]
        return pairs.compactMap { a, b in
            guard let p = joint(body, a), let q = joint(body, b), p.confidence > 0.3, q.confidence > 0.3 else { return nil }
            return (CGPoint(x: p.x, y: 1 - p.y), CGPoint(x: q.x, y: 1 - q.y))
        }
    }

    enum FaceCaptureError: Error, CustomStringConvertible {
        case noCamera

        var description: String { "No front camera" }
    }
}

/// Turns raw faces into smooth character channels: calibrates the neutral face, filters jitter, mirrors.
@MainActor
final class FacePerformer {
    private var neutral: FaceMeasure?
    private var filters: [PropertyKey: OneEuroFilter] = [:]
    /// Your rest pose (head angles, gaze, dials), taken when capture starts and whenever you ask.
    private(set) var rest = RestPose()
    private var wantsRest = true
    var mirror = true

    /// Use the next face as "neutral" (relaxed, looking at the iPad): Character Animator's Set Rest Pose.
    func recalibrate() {
        neutral = nil
        wantsRest = true
        filters = [:]
    }

    /// Camera face → channels (measured from your neutral face and rest pose, filtered, mirrored). The iPad's frames are
    /// mirrored, so the solver's picture sides are already the mirror's sides.
    func channels(for face: FaceLandmarks, at time: Double) -> [PropertyKey: Double] {
        if neutral == nil { neutral = FaceSolver.measure(face) }
        guard let neutral else { return [:] }
        return finish(FaceSolver.channels(face, neutral: neutral), at: time)
    }

    /// Channels that arrive ready (the iPhone's ARKit face, sent with the mirror's sides): the same rest pose,
    /// filtering and mirroring.
    func channels(fromLink values: [PropertyKey: Double], at time: Double) -> [PropertyKey: Double] {
        finish(values, at: time)
    }

    /// Hands from the body tracker (already in on-screen sides; the mirror switch swaps them).
    func hands(_ values: [PropertyKey: Double], at time: Double) -> [PropertyKey: Double] {
        var result = values
        if !mirror {
            result[.handLeftX] = values[.handRightX]
            result[.handLeftY] = values[.handRightY]
            result[.handRightX] = values[.handLeftX]
            result[.handRightY] = values[.handLeftY]
        }
        for (key, value) in result {
            var filter = filters[key] ?? OneEuroFilter(minCutoff: 0.8, beta: 0.4)
            result[key] = filter.filter(value, at: time)
            filters[key] = filter
        }
        return result
    }

    /// Every source reports the mirror's sides (the hand you raise on the left of the preview raises the character's
    /// hand on the left of the stage). Mirror off = the character copies you as a camera sees you: sides swap.
    private func finish(_ raw: [PropertyKey: Double], at time: Double) -> [PropertyKey: Double] {
        if wantsRest {
            rest.capture(raw)
            wantsRest = false
        }
        var values = rest.apply(raw)
        if !mirror {
            // Flip sides: left blink ↔ right blink, turns and tilts the other way.
            let left = values[.blinkLeft]
            values[.blinkLeft] = values[.blinkRight]
            values[.blinkRight] = left
            values[.headYaw] = values[.headYaw].map { -$0 }
            values[.headRoll] = values[.headRoll].map { -$0 }
            values[.lookX] = values[.lookX].map { -$0 }
        }
        for (key, value) in values {
            var filter = filters[key] ?? OneEuroFilter(minCutoff: key == .blinkLeft || key == .blinkRight ? 3 : 1.2, beta: 0.05)
            values[key] = filter.filter(value, at: time)
            filters[key] = filter
        }
        return values
    }
}
