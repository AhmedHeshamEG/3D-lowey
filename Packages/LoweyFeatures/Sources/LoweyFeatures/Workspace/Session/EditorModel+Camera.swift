import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Cameras: shots and cuts, the lens, one-tap moves, Frame shot, operating the camera by touch in the Director view,
/// and the iPad as the camera.
extension EditorModel {
    var cameras: [ObjectID] { baseScene.cameras }

    /// The camera the camera tools edit: a selected camera, else the shot camera.
    var editedCamera: ObjectID? {
        if let selected = singleSelection, selected.kind == .camera { return selected.id }
        return shotCamera
    }

    func setDirectorView(_ on: Bool) {
        guard on != directorView else { return }
        if !on { stopFlying() }
        if on, shotCamera == nil {
            app.show("Add a camera first (Build ▸ Camera saves this view)")
            return
        }
        directorView = on
        stage?.redraw()
        HmmHaptics.play(.selection)
    }

    func selectCamera(_ id: ObjectID) {
        setSelection([id])
        if timeline.cuts.isEmpty, baseScene.activeCamera != id { perform(.setActiveCamera(id)) }
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

    /// Sharp on the selection (or a focus pull to it from the playhead).
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
        if !subjects.isEmpty, let bounds = stage?.visualBounds(of: subjects) ?? operations.bounds.worldBounds(of: subjects, in: scene) {
            return bounds.center
        }
        guard let camera = editedCamera, let object = displayed.scene.objects[camera] else { return nil }
        let world = displayed.scene.worldTransform(of: camera)
        return world.position + world.rotation.act(Vec3(0, 0, -1)) * (object[.focusDistance]?.floatValue ?? 5)
    }

    // MARK: Moves

    func applyCameraMove(_ move: CameraMove, duration: Double, strength: Double) {
        guard let camera = editedCamera else {
            app.show("Add a camera first (Build ▸ Camera)")
            return
        }
        let subject = selectionSubject ?? stage?.viewpoint.target ?? .zero
        var ids = IDFactory.random
        let current = Animator.keyedScene(session.document, at: time)
        if perform(CameraMoves.apply(move, camera: camera, subject: subject, at: time, options: CameraMoveOptions(duration: duration, strength: strength),
                                     current: current, timeline: timeline, ids: &ids)) {
            HmmHaptics.play(.commit)
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

    // MARK: Frame shot

    /// Places and aims the camera (a new one when there is none) at the selected subject: a shot type and a
    /// composition, the same solver the AI uses.
    func frameShot(_ type: ShotType, composition: Composition, focalLength: Double? = nil, side: Double = 1) {
        let subjects = selection.filter { displayed.scene.objects[$0]?.kind != .camera }
        guard let first = subjects.first, let subject = shotSubject(first) else {
            app.show("Select the subject to frame first")
            return
        }
        let other = subjects.dropFirst().first.flatMap(shotSubject)
        let solution = FrameShot.solve(subject, type: type, composition: composition, focalLength: focalLength, other: other, side: side,
                                       aspect: deliveryFraming.aspect)
        var commands: [EditCommand] = []
        let cameraID: ObjectID
        if let existing = editedCamera {
            cameraID = existing
        } else {
            var made = factory.camera(at: stage?.viewpoint ?? baseScene.viewpoint)
            made.name = ObjectFactory.uniqueName("Camera", in: scene)
            commands += [operations.add(made), .setActiveCamera(made.id)]
            cameraID = made.id
        }
        commands.append(.setProperties([
            PropertyChange(object: cameraID, key: .position, value: .vec3(solution.position)),
            PropertyChange(object: cameraID, key: .rotation, value: .quat(solution.rotation)),
            PropertyChange(object: cameraID, key: .fieldOfView, value: .float(solution.fieldOfView)),
            PropertyChange(object: cameraID, key: .focusDistance, value: .float(solution.focusDistance))
        ]))
        if perform(.batch("\(type.title) shot", commands)) {
            directorView = true
            HmmHaptics.play(.commit)
        }
    }

    private func shotSubject(_ id: ObjectID) -> ShotSubject? {
        guard let object = displayed.scene.objects[id],
              let bounds = stage?.visualBounds(of: [id]) ?? operations.bounds.worldBounds(of: [id], in: scene) else { return nil }
        let front = displayed.scene.worldTransform(of: id).rotation.act(Vec3(0, 0, 1))
        let isCharacter = object[.rigStandard] != nil || object.kind.assetID.flatMap { library.manifest.asset($0)?.rig.isRigged } == true
        return ShotSubject(bounds: bounds, front: Vec3(front.x, 0, front.z).normalized, isCharacter: isCharacter)
    }

    // MARK: Operating the camera by touch (Director view)

    func setCameraWorld(_ world: CoreTransform, gesture: String) {
        guard let camera = editedCamera, let object = displayed.scene.objects[camera] else { return }
        if performPhase == .recording, performTargets.contains(camera) {
            beginCameraTake(camera)
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

    var editedCameraWorld: CoreTransform? {
        guard let camera = editedCamera else { return nil }
        if performPhase == .recording, let override = performOverride[camera] { return override }
        return displayed.scene.worldTransform(of: camera)
    }

    /// One finger: pan (around world up) and tilt (around the camera's side), in degrees.
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

    /// Twist: roll (a Dutch angle).
    func rollCamera(by radians: Double, gesture: String) {
        guard var world = editedCameraWorld else { return }
        world.rotation = (world.rotation * Quat(angle: -radians, axis: .unitZ)).normalized
        setCameraWorld(world, gesture: gesture)
    }

    // MARK: The iPad as the camera

    func startVirtualCamera() {
        guard let camera = editedCamera else {
            app.show("Add a camera first")
            return
        }
        guard VirtualCameraController.isSupported else {
            app.show("This iPad can't track its motion (ARKit world tracking is unavailable)")
            return
        }
        setSelection([camera])
        let start = displayed.scene.worldTransform(of: camera)
        let controller = VirtualCameraController()
        controller.onPose = { [weak self] delta in self?.virtualCameraMoved(delta, from: start, camera: camera) }
        controller.onFailure = { [weak self] message in
            self?.app.show(String.LocalizationValue(message), kind: .error)
            self?.stopVirtualCamera()
        }
        virtualCamera = controller
        virtualCameraActive = true
        directorView = true
        controller.start()
        updateStageClock()
        app.show("Move the iPad: the camera follows. Record in Perform.")
    }

    func stopVirtualCamera() {
        virtualCamera?.stop()
        virtualCamera = nil
        guard virtualCameraActive else { return }
        virtualCameraActive = false
        if performPhase == .idle {
            performOverride = [:]
            refreshDisplay()
        }
        updateStageClock()
    }

    /// Device motion since tracking started → the camera's pose (walking scaled up for big worlds).
    private func virtualCameraMoved(_ delta: CoreTransform, from start: CoreTransform, camera: ObjectID) {
        var pose = start
        pose.position = start.position + start.rotation.act(delta.position * virtualCameraScale)
        pose.rotation = (start.rotation * delta.rotation).normalized
        beginCameraTake(camera)
        performOverride[camera] = pose
        if !isPlaying { refreshDisplay() }
    }
}
