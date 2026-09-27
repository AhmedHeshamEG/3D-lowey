import Foundation
import LoweyCore
import LoweyRender
import SwiftUI

extension EditorModel {
    var cameras: [ObjectID] { baseScene.cameras }

    /// The camera the shot is seen through at the playhead (cut track, else the active camera).
    var shotCamera: ObjectID? { displayed.camera }

    /// The camera the Camera panel edits: a selected camera, else the shot camera.
    var editedCamera: ObjectID? {
        if let selected = singleSelection, selected.kind == .camera { return selected.id }
        return shotCamera
    }

    // MARK: Looking through

    /// Camera mode shows the shot through its camera, framed exactly like the export.
    func updateLookThrough() {
        guard let stage else { return }
        guard mode == .camera, lookThrough, let id = shotCamera ?? editedCamera, let object = displayed.scene.objects[id] else {
            if stage.lookThrough != nil { stage.setLookThrough(nil) }
            if renderer.hiddenObject != nil { renderer.hiddenObject = nil }
            return
        }
        let world = displayed.scene.worldTransform(of: id)
        let lens = CameraLens(object)
        let framing = lens.framing(aspect: cameraFraming.aspect)
        // Widen the stage so the framing guide covers exactly the camera's frame.
        let size = stage.bounds.size
        var fieldOfView = framing.fieldOfView
        if size.height > 0 {
            let guide = cameraFraming.guideRect(in: size)
            let half = atan(tan(framing.fieldOfView * .pi / 360) * Double(size.height / max(guide.height, 1)))
            fieldOfView = min(half * 360 / .pi, 170)
        }
        let rotation = (world.rotation * Quat(angle: framing.yaw, axis: .unitY)).normalized
        stage.setLookThrough(OffscreenRenderer.Camera(position: world.position.simd, orientation: rotation.simd, fieldOfView: Float(fieldOfView)))
        if renderer.hiddenObject != id { renderer.hiddenObject = id }
    }

    func setLookThrough(_ on: Bool) {
        lookThrough = on
        updateLookThrough()
    }

    // MARK: Cameras & cuts

    func selectCamera(_ id: ObjectID) {
        setSelection([id])
        if timeline.cuts.isEmpty, baseScene.activeCamera != id { perform(.setActiveCamera(id)) }
        updateLookThrough()
    }

    /// From the playhead on, the shot is seen through `id`.
    func cutToCamera(_ id: ObjectID) {
        updateTimeline("Cut to camera") { timeline in
            timeline.cuts.removeAll { abs($0.time - time) < 0.5 / Double(max(timeline.fps, 1)) }
            timeline.cuts.append(CameraCut(time: time, camera: id))
            timeline.cuts.sort { $0.time < $1.time }
        }
    }

    func removeCut(at cutTime: Double) {
        updateTimeline("Remove cut") { $0.cuts.removeAll { abs($0.time - cutTime) < 1e-6 } }
    }

    /// A new camera where the view is now (Camera mode: the shot's current framing).
    func newCameraFromView() {
        addCamera()
    }

    // MARK: Lens

    func lens(of id: ObjectID) -> CameraLens? {
        displayed.scene.objects[id].map(CameraLens.init)
    }

    func setCameraProperty(_ key: PropertyKey, _ value: Double, gesture: String? = nil) {
        guard let camera = editedCamera else { return }
        perform(.setProperties([PropertyChange(object: camera, key: key, value: .float(value))]), coalesceKey: gesture)
    }

    func setFocalLength(_ millimetres: Double, gesture: String? = nil) {
        setCameraProperty(.fieldOfView, CameraLens.fieldOfView(focalLength: millimetres), gesture: gesture)
    }

    /// Sharp on the selection (or animates a focus pull to it from the playhead).
    func focus(onSelection animated: Bool) {
        guard let camera = editedCamera, let subject = selectionSubject else { return }
        let distance = displayed.scene.worldTransform(of: camera).position.distance(to: subject)
        if animated {
            var ids = IDFactory.random
            perform(CameraMoves.focusPull(camera: camera, to: distance, at: time, duration: 1, current: displayed.scene, timeline: timeline, ids: &ids))
        } else {
            setCameraProperty(.focusDistance, distance)
        }
    }

    /// What a move frames: the selected objects (not cameras), else the camera's focus point.
    var selectionSubject: Vec3? {
        let subjects = selection.filter { displayed.scene.objects[$0]?.kind != .camera }
        if !subjects.isEmpty, let bounds = renderer.visualBounds(of: subjects) { return bounds.center }
        guard let camera = editedCamera, let object = displayed.scene.objects[camera] else { return nil }
        let world = displayed.scene.worldTransform(of: camera)
        let focus = object[.focusDistance]?.floatValue ?? 5
        return world.position + world.rotation.act(Vec3(0, 0, -1)) * focus
    }

    // MARK: Moves

    func applyCameraMove(_ move: CameraMove, duration: Double, strength: Double) {
        guard let camera = editedCamera else {
            app.show("Add a camera first (Save camera from view)")
            return
        }
        let subject = selectionSubject ?? stage?.viewpoint.target ?? .zero
        var ids = IDFactory.random
        let current = Animator.keyedScene(session.document, at: time)
        if perform(CameraMoves.apply(move, camera: camera, subject: subject, at: time, options: CameraMoveOptions(duration: duration, strength: strength),
                                     current: current, timeline: timeline, ids: &ids)) {
            Haptics.success()
        }
    }

    func followSelection(with camera: ObjectID) {
        guard let target = selection.first(where: { $0 != camera }) else { return }
        let offset = displayed.scene.worldTransform(of: camera).position - displayed.scene.worldTransform(of: target).position
        updateTimeline("Follow") { timeline in
            timeline.behaviors.append(Behavior(id: UUID().uuidString.lowercased(), target: camera, kind: .follow(target, offset: offset, lag: 0.25)))
            timeline.behaviors.append(Behavior(id: UUID().uuidString.lowercased(), target: camera, kind: .lookAt(target)))
        }
    }

    // MARK: Operating the camera by touch (Camera mode, looking through)

    private func setCameraWorld(_ world: CoreTransform, gesture: String) {
        guard let camera = editedCamera, let object = displayed.scene.objects[camera] else { return }
        if performPhase == .recording, performTargets.contains(camera) {
            performOverride[camera] = world
            refreshDisplay()
            return
        }
        let parentWorld = object.parent.map { displayed.scene.worldTransform(of: $0) } ?? .identity
        let local = CoreTransform.relative(world: world, toParent: parentWorld)
        perform(.setProperties([
            PropertyChange(object: camera, key: .position, value: .vec3(local.position)),
            PropertyChange(object: camera, key: .rotation, value: .quat(local.rotation))
        ]), coalesceKey: gesture)
    }

    private var editedCameraWorld: CoreTransform? {
        guard let camera = editedCamera else { return nil }
        if performPhase == .recording, let override = performOverride[camera] { return override }
        return displayed.scene.worldTransform(of: camera)
    }

    /// One finger: pan (around world up) and tilt (around the camera's own side axis), in degrees.
    func aimCamera(pan: Double, tilt: Double, gesture: String) {
        guard var world = editedCameraWorld else { return }
        let side = world.rotation.act(.unitX)
        let turn = Quat(angle: pan * .pi / 180, axis: .unitY) * Quat(angle: tilt * .pi / 180, axis: side)
        world.rotation = (turn * world.rotation).normalized
        setCameraWorld(world, gesture: gesture)
    }

    /// Two fingers / pinch: move in the camera's own frame (truck, pedestal, dolly).
    func moveCamera(local delta: Vec3, gesture: String) {
        guard var world = editedCameraWorld else { return }
        world.position += world.rotation.act(delta)
        setCameraWorld(world, gesture: gesture)
    }

    /// Twist: roll (dutch angle).
    func rollCamera(by radians: Double, gesture: String) {
        guard var world = editedCameraWorld else { return }
        world.rotation = (world.rotation * Quat(angle: -radians, axis: .unitZ)).normalized
        setCameraWorld(world, gesture: gesture)
    }

    // MARK: Virtual camera (the iPad as the camera)

    func startVirtualCamera() {
        guard let camera = editedCamera else {
            app.show("Add a camera first")
            return
        }
        guard VirtualCameraController.isSupported else {
            app.show("This iPad can't track its motion (ARKit world tracking unavailable)")
            return
        }
        setSelection([camera])
        let start = displayed.scene.worldTransform(of: camera)
        let controller = VirtualCameraController()
        controller.onPose = { [weak self] delta in
            self?.virtualCameraMoved(delta, from: start, camera: camera)
        }
        controller.onFailure = { [weak self] message in
            self?.app.show(message)
            self?.stopVirtualCamera()
        }
        virtualCamera = controller
        virtualCameraActive = true
        controller.start()
        lookThrough = true
        app.show("Move the iPad: the camera follows. Record in Perform mode.")
    }

    func stopVirtualCamera() {
        virtualCamera?.stop()
        virtualCamera = nil
        virtualCameraActive = false
        if performPhase == .idle {
            performOverride = [:]
            refreshDisplay()
        }
    }

    /// Device motion since tracking started → the camera's pose (translation scaled up for big worlds).
    private func virtualCameraMoved(_ delta: CoreTransform, from start: CoreTransform, camera: ObjectID) {
        var pose = start
        pose.position = start.position + start.rotation.act(delta.position * virtualCameraScale)
        pose.rotation = (start.rotation * delta.rotation).normalized
        if performPhase == .recording, !performTouching {
            performTouching = true
            for property in [PropertyKey.position, .rotation] {
                let channel = PerformChannel(object: camera, property: property)
                performChannels.insert(channel)
                var take = takes[channel] ?? PerformTake(object: camera, property: property)
                take.begin()
                takes[channel] = take
            }
        }
        performOverride[camera] = pose
        if !isPlaying { refreshDisplay() }
    }
}
