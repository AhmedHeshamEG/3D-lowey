import Foundation

/// A saved pose of a character: its face and hand dials (on the character itself) and the turn of every joint (built
/// characters). Saved on the character, so its poses travel with it (copy, library, Scene Scripts).
public struct CharacterPose: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Dials on the character's root (smile, brows, hands, head turn…).
    public var dials: [PropertyKey: PropertyValue]
    /// Joint rotations by bone name (built characters); the hips also keep their position.
    public var joints: [String: Quat]
    public var hips: Vec3?

    public init(id: String, name: String, dials: [PropertyKey: PropertyValue] = [:], joints: [String: Quat] = [:], hips: Vec3? = nil) {
        self.id = id
        self.name = name
        self.dials = dials
        self.joints = joints
        self.hips = hips
    }
}

public extension PropertyKey {
    /// A character's saved poses (JSON list of `CharacterPose`).
    static let poseLibrary: PropertyKey = "poseLibrary"
}

/// Saving, applying and mirroring poses of Blob and built (puppet) characters.
public enum PoseLibrary {
    /// The dials a pose keeps.
    public static let dialKeys: [PropertyKey] = PropertyKey.faceChannels + [.eyeWide, .eyeHappy, .browAngle, .squash]

    /// The character an object belongs to: itself or its nearest ancestor that has a skeleton (a Blob, a built
    /// character, a drawn rig or a rigged model from the library).
    public static func character(of id: ObjectID, in scene: Scene, rigs: [AssetID: RigAsset] = [:]) -> ObjectID? {
        ([id] + scene.ancestors(of: id)).first { candidate in
            guard let object = scene.objects[candidate] else { return false }
            return object[.rigStandard] != nil || object.rig != nil || object.kind.assetID.map { rigs[$0] != nil } == true
        }
    }

    public static func poses(of character: SceneObject) -> [CharacterPose] {
        guard let text = character[.poseLibrary]?.stringValue, let data = text.data(using: .utf8) else { return [] }
        return (try? LoweyJSON.decode([CharacterPose].self, from: data)) ?? []
    }

    /// The property change that stores `poses` on the character.
    public static func storing(_ poses: [CharacterPose], on character: ObjectID) -> PropertyChange {
        let text = (try? LoweyJSON.encode(poses)).flatMap { String(bytes: $0, encoding: .utf8) }
        return PropertyChange(object: character, key: .poseLibrary, value: poses.isEmpty ? nil : text.map(PropertyValue.string))
    }

    /// The character's pose as it is in `scene` (the scene as shown: animation applied). A skeleton of bones keeps
    /// every joint's turn from `skeletonPose` (the animator's pose), so a pose taken while a clip plays is the pose seen.
    public static func capture(_ character: ObjectID, in scene: Scene, id: String, name: String, skeletonPose: [Transform]? = nil,
                               rigs: [AssetID: RigAsset] = [:]) -> CharacterPose {
        var pose = CharacterPose(id: id, name: name)
        if let root = scene.objects[character] {
            for key in dialKeys {
                if let value = root[key] { pose.dials[key] = value }
            }
        }
        if let rig = CharacterRig.of(character, in: scene, rigs: rigs), rig.body == .bones {
            for (joint, local) in zip(rig.skeleton.joints, rig.localPose(in: scene, pose: skeletonPose)) {
                pose.joints[joint.name] = local.rotation
            }
            return pose
        }
        for joint in scene.subtree(of: character) {
            guard let object = scene.objects[joint], let bone = object[.bone]?.stringValue else { continue }
            pose.joints[bone] = object.transform.rotation
            if bone == "hips" { pose.hips = object.transform.position }
        }
        return pose
    }

    /// The changes that put the character in `pose` (dials missing from the pose go back to rest).
    public static func applying(_ pose: CharacterPose, to character: ObjectID, in scene: Scene, rigs: [AssetID: RigAsset] = [:]) -> [PropertyChange] {
        var changes = dialKeys.map { PropertyChange(object: character, key: $0, value: pose.dials[$0]) }
        if let root = scene.objects[character] {
            changes = changes.filter { root[$0.key] != $0.value }
        }
        if let rig = CharacterRig.of(character, in: scene, rigs: rigs), rig.body == .bones {
            let turns = Dictionary(rig.skeleton.joints.indices.compactMap { index in
                pose.joints[rig.skeleton.joints[index].name].map { (index, $0) }
            }, uniquingKeysWith: { first, _ in first })
            return changes + rig.changes(turning: turns)
        }
        for joint in scene.subtree(of: character) {
            guard let object = scene.objects[joint], let bone = object[.bone]?.stringValue, let rotation = pose.joints[bone] else { continue }
            changes.append(PropertyChange(object: joint, key: .rotation, value: .quat(rotation)))
            if bone == "hips", let hips = pose.hips { changes.append(PropertyChange(object: joint, key: .position, value: .vec3(hips))) }
        }
        return changes
    }

    /// The same pose seen in a mirror: left and right swap, turns to one side become turns to the other.
    public static func mirrored(_ pose: CharacterPose, name: String? = nil) -> CharacterPose {
        var result = CharacterPose(id: pose.id, name: name ?? pose.name)
        let swaps: [PropertyKey: PropertyKey] = [
            .handLeftX: .handRightX, .handRightX: .handLeftX, .handLeftY: .handRightY, .handRightY: .handLeftY,
            .blinkLeft: .blinkRight, .blinkRight: .blinkLeft
        ]
        let negated: Set<PropertyKey> = [.headYaw, .headRoll, .lookX]
        for (key, value) in pose.dials {
            let target = swaps[key] ?? key
            if negated.contains(key), let number = value.floatValue {
                result.dials[target] = .float(-number)
            } else {
                result.dials[target] = value
            }
        }
        for (bone, rotation) in pose.joints {
            result.joints[mirroredBone(bone)] = Quat(x: rotation.x, y: -rotation.y, z: -rotation.z, w: rotation.w)
        }
        result.hips = pose.hips.map { Vec3(-$0.x, $0.y, $0.z) }
        return result
    }

    static func mirroredBone(_ name: String) -> String {
        if name.hasPrefix("left") { return "right" + name.dropFirst(4) }
        if name.hasPrefix("right") { return "left" + name.dropFirst(5) }
        return name
    }
}
