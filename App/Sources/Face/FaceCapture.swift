import AVFoundation
import Foundation
import LoweyCore
import os
import Vision

/// Reads your face from the iPad's front camera with Vision (no TrueDepth needed): landmarks → `FaceLandmarks`.
final class FaceCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.hesham.lowey.face")
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "face")
    private var lastFrame: CFTimeInterval = 0
    /// Called on the main actor for every analysed frame (nil = no face in view).
    let onFace: @MainActor @Sendable (FaceLandmarks?) -> Void

    init(onFace: @escaping @MainActor @Sendable (FaceLandmarks?) -> Void) {
        self.onFace = onFace
        super.init()
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

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
        session.commitConfiguration()
        queue.async { [session] in session.startRunning() }
    }

    func stop() {
        queue.async { [session] in session.stopRunning() }
    }

    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastFrame > 1.0 / 30, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let request = VNDetectFaceLandmarksRequest()
        // Front camera in landscape iPad: the image arrives rotated; `.leftMirrored` presents it upright and mirrored.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .leftMirrored)
        do {
            try handler.perform([request])
        } catch {
            logger.error("Vision: \(error.localizedDescription)")
            return
        }
        let face = request.results?.max { $0.boundingBox.width < $1.boundingBox.width }.flatMap(Self.landmarks)
        let callback = onFace
        Task { @MainActor in callback(face) }
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
            leftPupil: center(marks.leftPupil), rightPupil: center(marks.rightPupil),
            yaw: observation.yaw?.doubleValue ?? 0, pitch: observation.pitch?.doubleValue ?? 0, roll: observation.roll?.doubleValue ?? 0
        )
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
    var mirror = true

    /// Use the next face as "neutral" (relaxed, looking at the iPad).
    func recalibrate() {
        neutral = nil
    }

    func channels(for face: FaceLandmarks, at time: Double) -> [PropertyKey: Double] {
        if neutral == nil { neutral = FaceSolver.measure(face) }
        guard let neutral else { return [:] }
        var values = FaceSolver.channels(face, neutral: neutral)
        if mirror {
            // Like a mirror: your left is the character's right as you face it.
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
