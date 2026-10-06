import Foundation

/// A joint you can grab and drag: the limb or chain follows (IK). Every character type has them through
/// `CharacterRig`: a humanoid's hands, feet and head, every joint of a drawn chain, a Blob's mitten hands.
public struct IKHandle: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// A Blob's mitten hand (driven by `handLeftX/Y` or `handRightX/Y`; its rubber-hose arm bends to it).
        case blobHand(left: Bool, hand: ObjectID)
        /// Skeleton joints from the one that stays put to the one being dragged.
        case chain([Int])
    }

    public var name: String
    public var character: ObjectID
    public var kind: Kind
    /// A hand, foot, head or the tip of a chain (drawn larger than the joints along a chain).
    public var isEnd: Bool

    public var id: String {
        switch kind {
        case let .blobHand(left, _): "\(character.raw).\(left ? "L" : "R")"
        case let .chain(joints): "\(character.raw).\(joints.last ?? -1)"
        }
    }
}

public enum IKHandles {
    /// A humanoid's limbs and which way each bends (model space: elbows back, knees forward).
    static let limbs: [(name: String, bones: [String], pole: Vec3)] = [
        ("Left hand", ["leftUpperArm", "leftLowerArm", "leftHand"], Vec3(0, 0, -1)),
        ("Right hand", ["rightUpperArm", "rightLowerArm", "rightHand"], Vec3(0, 0, -1)),
        ("Left foot", ["leftUpperLeg", "leftLowerLeg", "leftFoot"], Vec3(0, 0, 1)),
        ("Right foot", ["rightUpperLeg", "rightLowerLeg", "rightFoot"], Vec3(0, 0, 1)),
        ("Head", ["chest", "neck", "head"], Vec3(0, 0, 1))
    ]

    /// The handles of a character. `rigs` are the library's rigged models.
    public static func handles(of character: ObjectID, in scene: Scene, rigs: [AssetID: RigAsset] = [:]) -> [IKHandle] {
        guard let rig = CharacterRig.of(character, in: scene, rigs: rigs) else { return [] }
        switch rig.body {
        case .blob:
            return scene.subtree(of: character).compactMap { id in
                guard let role = scene.objects[id]?[.faceRole]?.stringValue, role == "hand.L" || role == "hand.R" else { return nil }
                let left = role == "hand.L"
                return IKHandle(name: left ? "Left hand" : "Right hand", character: character, kind: .blobHand(left: left, hand: id), isEnd: true)
            }
        case .bones, .joints:
            if rig.standard == .humanoid {
                return limbs.compactMap { limb in
                    let chain = limb.bones.compactMap(rig.joint)
                    guard chain.count == limb.bones.count else { return nil }
                    return IKHandle(name: limb.name, character: character, kind: .chain(chain), isEnd: true)
                }
            }
            return chainHandles(rig)
        }
    }

    /// Every joint below where its chain begins: dragging one bends the chain from its base to it.
    static func chainHandles(_ rig: CharacterRig) -> [IKHandle] {
        let skeleton = rig.skeleton
        return skeleton.joints.indices.compactMap { index in
            var chain = [index]
            var current = index
            // Up to the chain's base: the joint hanging from the root or from a fork stays put.
            while let parent = skeleton.joints[current].parent, skeleton.joints[parent].parent != nil,
                  skeleton.children(of: parent).count == 1, chain.count < 12 {
                chain.insert(parent, at: 0)
                current = parent
            }
            guard chain.count >= 2 else { return nil }
            let isEnd = skeleton.children(of: index).isEmpty
            return IKHandle(name: skeleton.joints[index].name, character: rig.character, kind: .chain(chain), isEnd: isEnd)
        }
    }

    /// Where a handle is in the world. `pose` is the animator's pose of a skeleton of bones.
    public static func position(of handle: IKHandle, in scene: Scene, pose: [Transform]?, rigs: [AssetID: RigAsset] = [:]) -> Vec3? {
        switch handle.kind {
        case let .blobHand(_, hand):
            return scene.objects[hand] != nil ? scene.worldTransform(of: hand).position : nil
        case let .chain(joints):
            guard let rig = CharacterRig.of(handle.character, in: scene, rigs: rigs), let end = joints.last else { return nil }
            let model = rig.skeleton.modelSpace(rig.localPose(in: scene, pose: pose))
            guard model.indices.contains(end) else { return nil }
            return rig.frame(in: scene).apply(to: model[end].position)
        }
    }

    /// The changes that bring the handle to `target` (world) in `scene` (the scene as shown). `rest` is the edited
    /// scene (a Blob's hands move from their rest spot).
    public static func solve(_ handle: IKHandle, to target: Vec3, in scene: Scene, pose: [Transform]? = nil, rest: Scene,
                             rigs: [AssetID: RigAsset] = [:]) -> [PropertyChange] {
        switch handle.kind {
        case let .blobHand(left, hand):
            return blobHand(handle.character, hand: hand, left: left, target: target, scene: scene, rest: rest)
        case let .chain(joints):
            guard let rig = CharacterRig.of(handle.character, in: scene, rigs: rigs) else { return [] }
            let local = rig.localPose(in: scene, pose: pose)
            let frame = rig.frame(in: scene)
            let pole = rig.standard == .humanoid ? limbs.first { $0.bones.compactMap(rig.joint) == joints }?.pole : nil
            let turns = ChainIK.solve(chain: joints, skeleton: rig.skeleton, local: local, target: frame.inverseApply(to: target), pole: pole)
            return rig.changes(turning: turns)
        }
    }

    static func blobHand(_ character: ObjectID, hand: ObjectID, left: Bool, target: Vec3, scene: Scene, rest: Scene) -> [PropertyChange] {
        guard let resting = rest.objects[hand] else { return [] }
        let local = scene.worldTransform(of: character).inverseApply(to: target)
        let delta = local - resting.transform.position
        let side: Double = left ? -1 : 1
        let out = min(max(delta.x / (side * BlobRig.handReach.x), -1), 1)
        let up = min(max(delta.y / BlobRig.handReach.y, -1), 1)
        return [
            PropertyChange(object: character, key: left ? .handLeftX : .handRightX, value: .float(out)),
            PropertyChange(object: character, key: left ? .handLeftY : .handRightY, value: .float(up))
        ]
    }
}
