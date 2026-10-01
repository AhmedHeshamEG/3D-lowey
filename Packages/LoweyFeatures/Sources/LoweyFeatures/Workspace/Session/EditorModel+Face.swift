import Foundation
import LoweyCore
import LoweyEngine
import Observation
import QuartzCore

/// Face performance: the front camera or the iPhone companion drives the selected character's face and hands live;
/// while a Perform take records, the values are captured like any performed value.
extension EditorModel {
    /// The character whose face is performed.
    var faceTarget: ObjectID? { selectedPuppet ?? selectedCharacter?.object.id ?? selection.first.flatMap { isBlob($0) ? $0 : nil } }

    func performFace(_ values: [PropertyKey: Double], detected: Bool) {
        guard let target = faceTarget else { return }
        for (key, value) in values {
            propertyOverride[target, default: [:]][key] = .float(value)
        }
        if performPhase == .recording, detected {
            for key in values.keys {
                let channel = PerformChannel(object: target, property: key)
                if takes[channel] == nil || !performTouching { takes[channel, default: PerformTake(object: target, property: key)].begin() }
                performChannels.insert(channel)
            }
        }
        performTouching = detected
        faceDirty = true
    }

    /// "Set rest pose": sit relaxed, look at the screen, tap. That pose becomes neutral.
    func setRestPose() {
        facePerformer.recalibrate()
        app.show("Rest pose set. Relax: this is neutral now")
    }

    func startFaceCapture(useIPhone: Bool) {
        guard faceTarget != nil else {
            app.show("Select your character first")
            return
        }
        stopFaceCapture()
        facePerformer.recalibrate()
        faceMonitor.clear()
        faceMonitor.source = useIPhone ? "iPhone" : "Camera"
        faceClock.onTick = { [weak self] _ in
            guard let self, faceDirty else { return }
            faceDirty = false
            if !isPlaying { refreshDisplay() }
        }
        faceClock.start()
        if useIPhone { startFaceLink() } else { startFrontCamera() }
        faceActive = true
        updateStageClock()
    }

    private func startFaceLink() {
        let receiver = FaceLinkReceiver()
        receiver.onStatus = { [weak self] message in self?.faceStatus = message }
        receiver.onChannels = { [weak self] channels in self?.faceLinkChannels(channels) }
        receiver.onPreview = { [weak self] dots, bones, picture in
            guard let self else { return }
            faceMonitor.dots = dots
            faceMonitor.bones = bones
            if let picture { faceMonitor.picture = picture }
        }
        receiver.start()
        faceLink = receiver
        faceStatus = "Open \(AppIdentity.displayName) on your iPhone"
    }

    private func faceLinkChannels(_ channels: [PropertyKey: Double]) {
        let now = CACurrentMediaTime()
        var face = channels
        var hands: [PropertyKey: Double] = [:]
        for key in PropertyKey.handChannels {
            hands[key] = face.removeValue(forKey: key)
        }
        var values = facePerformer.channels(fromLink: face, at: now)
        if !hands.isEmpty {
            let tracked = facePerformer.hands(hands, at: now)
            values.merge(tracked) { $1 }
            faceMonitor.leftHand = tracked[.handLeftY] ?? 0
            faceMonitor.rightHand = tracked[.handRightY] ?? 0
        }
        faceMonitor.faceFound = true
        performFace(values, detected: true)
    }

    private func startFrontCamera() {
        Task {
            guard await FaceCapture.requestAccess() else {
                app.show("Allow the camera in Settings to perform with your face", kind: .error)
                return
            }
            let capture = FaceCapture { [weak self] sample in self?.faceSampleArrived(sample) }
            do {
                try capture.start()
                faceCapture = capture
                faceStatus = "Relax and look at the iPad…"
            } catch {
                app.show("Face capture failed: \(error)", kind: .error)
            }
        }
    }

    /// One analysed frame of the iPad's camera.
    private func faceSampleArrived(_ sample: FaceSample) {
        let now = CACurrentMediaTime()
        faceMonitor.dots = sample.dots
        if !sample.bones.isEmpty || sample.hands != nil { faceMonitor.bones = sample.bones }
        if let picture = sample.preview { faceMonitor.picture = picture }
        faceMonitor.faceFound = sample.face != nil
        var values: [PropertyKey: Double] = [:]
        if let face = sample.face {
            values = facePerformer.channels(for: face, at: now)
            faceStatus = "Reading your face"
        } else {
            faceStatus = "Look at the iPad"
        }
        if let hands = sample.hands {
            let tracked = facePerformer.hands(hands, at: now)
            values.merge(tracked) { $1 }
            faceMonitor.leftHand = tracked[.handLeftY] ?? 0
            faceMonitor.rightHand = tracked[.handRightY] ?? 0
        }
        performFace(values, detected: sample.face != nil)
    }

    func stopFaceCapture() {
        faceCapture?.stop()
        faceCapture = nil
        faceLink?.stop()
        faceLink = nil
        faceClock.stop()
        faceDirty = false
        faceMonitor.clear()
        guard faceActive else { return }
        faceActive = false
        faceStatus = nil
        if let target = faceTarget {
            for key in PropertyKey.faceChannels {
                propertyOverride[target]?[key] = nil
            }
        }
        refreshDisplay()
        updateStageClock()
    }
}

/// What the face preview shows: the camera, the tracking dots and bones, whether a face is found. Its own observable,
/// so a camera frame redraws only the little preview.
@Observable
@MainActor
final class FaceMonitor {
    var picture: CGImage?
    var dots: [CGPoint] = []
    var bones: [(CGPoint, CGPoint)] = []
    var faceFound = false
    /// How raised each tracked hand is (0…1).
    var leftHand: Double = 0
    var rightHand: Double = 0
    var source = "Camera"

    func clear() {
        picture = nil
        dots = []
        bones = []
        faceFound = false
        leftHand = 0
        rightHand = 0
    }
}
