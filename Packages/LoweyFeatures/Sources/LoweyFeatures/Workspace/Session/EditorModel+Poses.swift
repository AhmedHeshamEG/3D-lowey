import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// The pose library (save, apply, mirror a character's pose) and IK handles (drag a joint; the limb or chain follows).
/// Every character type poses the same way (`CharacterRig`). Applying a pose or dragging a handle keys the change at the
/// playhead in Keyframe mode, like any other edit.
extension EditorModel {
    /// The character (Blob, Puppet, drawn rig or rigged model) the selection belongs to.
    var poseCharacter: ObjectID? {
        selection.count == 1 ? selection.first.flatMap { PoseLibrary.character(of: $0, in: baseScene, rigs: libraryRigs()) } : nil
    }

    func poses(of character: ObjectID) -> [CharacterPose] {
        baseScene.objects[character].map(PoseLibrary.poses) ?? []
    }

    /// Saves the character's pose at the playhead.
    func savePose(of character: ObjectID, named name: String? = nil) {
        var poses = poses(of: character)
        let pose = PoseLibrary.capture(character, in: displayed.scene, id: UUID().uuidString.lowercased(), name: name ?? "Pose \(poses.count + 1)",
                                       skeletonPose: displayed.poses[character], rigs: libraryRigs())
        poses.append(pose)
        perform(.batch("Save pose", [.setProperties([PoseLibrary.storing(poses, on: character)])]))
        app.show("Saved “\(pose.name)”")
    }

    func applyPose(_ pose: CharacterPose, to character: ObjectID) {
        let changes = PoseLibrary.applying(pose, to: character, in: displayed.scene, rigs: libraryRigs())
        guard !changes.isEmpty else { return }
        perform(.batch("Pose: \(pose.name)", [.setProperties(changes)]))
        HmmHaptics.play(.commit)
    }

    /// The character's current pose, flipped left for right.
    func mirrorPose(of character: ObjectID) {
        let current = PoseLibrary.capture(character, in: displayed.scene, id: "current", name: "Mirror", skeletonPose: displayed.poses[character],
                                          rigs: libraryRigs())
        applyPose(PoseLibrary.mirrored(current), to: character)
    }

    func saveMirrored(_ pose: CharacterPose, of character: ObjectID) {
        var poses = poses(of: character)
        poses.append(PoseLibrary.mirrored(pose, name: "\(pose.name) (mirrored)").withID(UUID().uuidString.lowercased()))
        perform(.batch("Save pose", [.setProperties([PoseLibrary.storing(poses, on: character)])]))
    }

    func deletePose(_ id: String, of character: ObjectID) {
        let poses = poses(of: character).filter { $0.id != id }
        perform(.batch("Delete pose", [.setProperties([PoseLibrary.storing(poses, on: character)])]))
    }

    func renamePose(_ id: String, of character: ObjectID, to name: String) {
        let poses = poses(of: character).map { pose in
            var renamed = pose
            if pose.id == id { renamed.name = name }
            return renamed
        }
        perform(.batch("Rename pose", [.setProperties([PoseLibrary.storing(poses, on: character)])]))
    }

    // MARK: IK handles

    /// The selected character's joints on screen (select tool, not while playing). Puppets and Blobs show theirs in
    /// Keyframe and Perform modes (in Compose a drag moves the whole character); drawn rigs and rigged models show
    /// theirs in every mode, since their joints are the only way to pose them.
    func ikHandlesOnScreen() -> [(handle: IKHandle, point: CGPoint)] {
        guard let stage, tool == .select, !isPlaying, let character = poseCharacter else { return [] }
        let rigs = libraryRigs()
        if timelineMode == .compose, CharacterRig.of(character, in: displayed.scene, rigs: rigs)?.body != .bones { return [] }
        let pose = displayed.poses[character]
        return IKHandles.handles(of: character, in: displayed.scene, rigs: rigs).compactMap { handle in
            IKHandles.position(of: handle, in: displayed.scene, pose: pose, rigs: rigs).flatMap(stage.screenPoint(of:)).map { (handle, $0) }
        }
    }

    func ikHandle(at point: CGPoint) -> IKHandle? {
        ikHandlesOnScreen().filter { hypot($0.point.x - point.x, $0.point.y - point.y) < 26 }
            .min { hypot($0.point.x - point.x, $0.point.y - point.y) < hypot($1.point.x - point.x, $1.point.y - point.y) }?.handle
    }

    /// Drags a joint under the finger (on the plane facing the camera through it). One undo step per drag.
    func dragIK(_ handle: IKHandle, to point: CGPoint, gesture: String) {
        let rigs = libraryRigs()
        let pose = displayed.poses[handle.character]
        guard let stage, let ray = stage.worldRay(at: point),
              let end = IKHandles.position(of: handle, in: displayed.scene, pose: pose, rigs: rigs) else { return }
        let normal = (Vec3(stage.camera.position) - end).normalized
        guard let target = GuideSurface.plane(origin: end, normal: normal).intersect(ray)?.point, target.distance(to: end) < 20 else { return }
        let changes = IKHandles.solve(handle, to: target, in: displayed.scene, pose: pose, rest: baseScene, rigs: rigs)
        guard !changes.isEmpty else { return }
        perform(.setProperties(changes), coalesceKey: gesture)
    }
}

extension CharacterPose {
    func withID(_ id: String) -> CharacterPose {
        var copy = self
        copy.id = id
        return copy
    }
}
