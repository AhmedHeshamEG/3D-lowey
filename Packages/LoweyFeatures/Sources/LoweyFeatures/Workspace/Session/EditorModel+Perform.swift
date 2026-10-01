import Foundation
import HmmDesign
import LoweyCore

/// Perform: record direct manipulation as keys while the timeline plays (touch, sliders, a flown camera, the iPad's
/// motion, a face). Lifting the finger pauses the take; one recording is one undo step.
extension EditorModel {
    /// What performing moves: in the Director view with nothing else selected, the shot camera (fly it with the usual
    /// gestures); otherwise the selection's top-level objects.
    var performTargets: [ObjectID] {
        if let camera = performedCamera { return [camera] }
        return operations.topLevel(selection, in: baseScene).filter { !baseScene.isEffectivelyLocked($0) }
    }

    /// The camera being flown: the Director view's shot camera when nothing else is selected.
    var performedCamera: ObjectID? {
        guard directorView, let camera = editedCamera, selection.allSatisfy({ $0 == camera }) else { return nil }
        return camera
    }

    /// A camera gesture (or the iPad's motion) starts moving the camera while recording: start its takes.
    func beginCameraTake(_ camera: ObjectID) {
        guard performPhase == .recording, !performTouching else { return }
        performTouching = true
        for property in [PropertyKey.position, .rotation] {
            let channel = PerformChannel(object: camera, property: property)
            performChannels.insert(channel)
            var take = takes[channel] ?? PerformTake(object: camera, property: property)
            take.begin()
            takes[channel] = take
        }
    }

    /// Record: a 3-2-1 countdown, then the timeline plays and touches are captured.
    func armPerform() {
        guard performPhase == .idle else {
            cancelPerform()
            return
        }
        guard !performTargets.isEmpty || virtualCameraActive || faceActive else {
            app.show(directorView ? "Select what to perform, or fly the shot camera" : "Select what to perform first")
            return
        }
        pause()
        takes = [:]
        performChannels = []
        performOverride = [:]
        if !faceActive { propertyOverride = [:] }
        Task { @MainActor in
            for count in [3, 2, 1] {
                performPhase = .countdown(count)
                HmmHaptics.play(.selection)
                try? await Task.sleep(for: .milliseconds(650))
                guard performPhase != .idle else { return }
            }
            performPhase = .recording
            HmmHaptics.play(.commit)
            play()
        }
    }

    func cancelPerform() {
        performPhase = .idle
        takes = [:]
        performOverride = [:]
        propertyOverride = [:]
        performTouching = false
        if isPlaying {
            isPlaying = false
            clock.stop()
        }
        updateStageClock()
        refreshDisplay()
    }

    func finishPerform() {
        guard performPhase == .recording else { return }
        performPhase = .idle
        let recorded = Array(takes.values)
        takes = [:]
        performOverride = [:]
        propertyOverride = [:]
        performTouching = false
        var ids = IDFactory.random
        if let command = PerformBaker.command(for: recorded, fps: timeline.fps, smoothing: performSettings.smoothing, timeline: timeline, ids: &ids) {
            perform(command)
            app.show("Performance recorded")
        } else {
            refreshDisplay()
            app.show("Nothing was performed. Touch and move while it plays")
        }
        updateStageClock()
    }

    /// A touch starts while recording: the performed values start from what's shown now.
    func performTouchBegan(_ channels: Set<PropertyKey>) {
        guard performPhase == .recording else { return }
        performTouching = true
        for id in performTargets {
            if performOverride[id] == nil { performOverride[id] = displayed.scene.worldTransform(of: id) }
            for property in channels {
                let channel = PerformChannel(object: id, property: property)
                performChannels.insert(channel)
                var take = takes[channel] ?? PerformTake(object: id, property: property)
                take.begin()
                takes[channel] = take
            }
        }
        recordPerformSample()
    }

    /// Lifting the finger pauses recording (the playhead keeps going).
    func performTouchEnded() {
        performTouching = false
    }

    func performMove(by delta: Vec3) {
        let scaled = delta * performSettings.sensitivity
        for id in performTargets {
            performOverride[id]?.position += scaled
        }
        refreshDisplay()
    }

    func performScale(by factor: Double) {
        let factor = 1 + (factor - 1) * performSettings.sensitivity
        for id in performTargets {
            if var transform = performOverride[id] {
                transform.scale = (transform.scale * factor).map { max($0, 0.01) }
                performOverride[id] = transform
            }
        }
        refreshDisplay()
    }

    func performRotate(by radians: Double) {
        let turn = Quat(angle: radians * performSettings.sensitivity, axis: .unitY)
        for id in performTargets {
            if var transform = performOverride[id] {
                transform.rotation = (turn * transform.rotation).normalized
                performOverride[id] = transform
            }
        }
        refreshDisplay()
    }

    /// A number performed with a slider (glow, light strength, focal length, opacity…).
    func performValue(_ key: PropertyKey, _ value: Double, touching: Bool) {
        for id in performTargets {
            propertyOverride[id, default: [:]][key] = .float(value)
            if touching, performPhase == .recording {
                let channel = PerformChannel(object: id, property: key)
                if !performTouching { takes[channel, default: PerformTake(object: id, property: key)].begin() }
                performChannels.insert(channel)
            }
        }
        performTouching = touching
        refreshDisplay()
    }

    func recordPerformSample() {
        guard performPhase == .recording, performTouching else { return }
        for channel in performChannels where takes[channel] != nil {
            if let value = performedValue(channel) { takes[channel]?.add(.init(time: time, value: value)) }
        }
    }

    private func performedValue(_ channel: PerformChannel) -> PropertyValue? {
        guard let world = performOverride[channel.object], [.position, .rotation, .scale].contains(channel.property) else {
            return propertyOverride[channel.object]?[channel.property]
        }
        let parentWorld = displayed.scene.objects[channel.object]?.parent.map { displayed.scene.worldTransform(of: $0) } ?? .identity
        let local = CoreTransform.relative(world: world, toParent: parentWorld)
        return switch channel.property {
        case .position: .vec3(local.position)
        case .rotation: .quat(local.rotation)
        default: .vec3(local.scale)
        }
    }
}
