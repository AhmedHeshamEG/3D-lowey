import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// The pose library (save, apply, mirror a character's pose) and IK handles (drag a hand or foot; the limb follows).
/// Applying a pose or dragging a handle keys the change at the playhead in Keyframe mode, like any other edit.
extension EditorModel {
    /// The Blob or built character the selection belongs to.
    var poseCharacter: ObjectID? {
        selection.count == 1 ? selection.first.flatMap { PoseLibrary.character(of: $0, in: baseScene) } : nil
    }

    func poses(of character: ObjectID) -> [CharacterPose] {
        baseScene.objects[character].map(PoseLibrary.poses) ?? []
    }

    /// Saves the character's pose at the playhead.
    func savePose(of character: ObjectID, named name: String? = nil) {
        var poses = poses(of: character)
        let pose = PoseLibrary.capture(character, in: displayed.scene, id: UUID().uuidString.lowercased(), name: name ?? "Pose \(poses.count + 1)")
        poses.append(pose)
        perform(.batch("Save pose", [.setProperties([PoseLibrary.storing(poses, on: character)])]))
        app.show("Saved “\(pose.name)”")
    }

    func applyPose(_ pose: CharacterPose, to character: ObjectID) {
        let changes = PoseLibrary.applying(pose, to: character, in: displayed.scene)
        guard !changes.isEmpty else { return }
        perform(.batch("Pose: \(pose.name)", [.setProperties(changes)]))
        HmmHaptics.play(.commit)
    }

    /// The character's current pose, flipped left for right.
    func mirrorPose(of character: ObjectID) {
        let current = PoseLibrary.capture(character, in: displayed.scene, id: "current", name: "Mirror")
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

    /// The selected character's hands and feet on screen (Keyframe and Perform modes, select tool).
    func ikHandlesOnScreen() -> [(handle: IKHandle, point: CGPoint)] {
        guard let stage, timelineMode != .compose, tool == .select, !isPlaying, let character = poseCharacter else { return [] }
        return IKHandles.handles(of: character, in: displayed.scene).compactMap { handle in
            stage.screenPoint(of: displayed.scene.worldTransform(of: handle.end).position).map { (handle, $0) }
        }
    }

    func ikHandle(at point: CGPoint) -> IKHandle? {
        ikHandlesOnScreen().filter { hypot($0.point.x - point.x, $0.point.y - point.y) < 26 }
            .min { hypot($0.point.x - point.x, $0.point.y - point.y) < hypot($1.point.x - point.x, $1.point.y - point.y) }?.handle
    }

    /// Drags a hand or foot under the finger (on the plane facing the camera through it). One undo step per drag.
    func dragIK(_ handle: IKHandle, to point: CGPoint, gesture: String) {
        guard let stage, let ray = stage.worldRay(at: point) else { return }
        let end = displayed.scene.worldTransform(of: handle.end).position
        let normal = (Vec3(stage.camera.position) - end).normalized
        guard let target = GuideSurface.plane(origin: end, normal: normal).intersect(ray)?.point, target.distance(to: end) < 20 else { return }
        let changes = IKHandles.solve(handle, to: target, in: displayed.scene, rest: baseScene)
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
