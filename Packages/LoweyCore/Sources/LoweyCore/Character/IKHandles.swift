import Foundation

/// A hand or foot you can grab and drag: the character's limb follows (two-bone IK on built characters, the reach
/// dials on a Blob, whose rubber-hose arm then bends to it).
public struct IKHandle: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// A Blob's mitten hand (driven by `handLeftX/Y` or `handRightX/Y`).
        case blobHand(left: Bool)
        /// A built character's limb: upper joint, lower joint, end joint.
        case limb(upper: ObjectID, lower: ObjectID, end: ObjectID)
    }

    public var name: String
    public var character: ObjectID
    /// The object the handle sits on (the hand or foot).
    public var end: ObjectID
    public var kind: Kind

    public var id: ObjectID { end }
}

public enum IKHandles {
    /// The limbs of a built character, by their bone names.
    static let limbs: [(name: String, upper: String, lower: String, end: String)] = [
        ("Left hand", "leftUpperArm", "leftLowerArm", "leftHand"), ("Right hand", "rightUpperArm", "rightLowerArm", "rightHand"),
        ("Left foot", "leftUpperLeg", "leftLowerLeg", "leftFoot"), ("Right foot", "rightUpperLeg", "rightLowerLeg", "rightFoot")
    ]

    /// The handles of a character (Blob hands, built characters' hands and feet).
    public static func handles(of character: ObjectID, in scene: Scene) -> [IKHandle] {
        guard let root = scene.objects[character] else { return [] }
        let subtree = scene.subtree(of: character)
        if root[.rigStandard]?.stringValue == "blob" {
            return subtree.compactMap { id in
                guard let role = scene.objects[id]?[.faceRole]?.stringValue, role == "hand.L" || role == "hand.R" else { return nil }
                let left = role == "hand.L"
                return IKHandle(name: left ? "Left hand" : "Right hand", character: character, end: id, kind: .blobHand(left: left))
            }
        }
        var bones: [String: ObjectID] = [:]
        for id in subtree {
            if let bone = scene.objects[id]?[.bone]?.stringValue { bones[bone] = id }
        }
        return limbs.compactMap { limb in
            guard let upper = bones[limb.upper], let lower = bones[limb.lower], let end = bones[limb.end] else { return nil }
            return IKHandle(name: limb.name, character: character, end: end, kind: .limb(upper: upper, lower: lower, end: end))
        }
    }

    /// The changes that bring the handle to `target` (world) in `scene` (the scene as shown). `rest` is the edited
    /// scene (a Blob's hands move from their rest spot).
    public static func solve(_ handle: IKHandle, to target: Vec3, in scene: Scene, rest: Scene) -> [PropertyChange] {
        switch handle.kind {
        case let .blobHand(left):
            return blobHand(handle, left: left, target: target, scene: scene, rest: rest)
        case let .limb(upper, lower, end):
            return twoBone(upper: upper, lower: lower, end: end, target: target, in: scene)
        }
    }

    static func blobHand(_ handle: IKHandle, left: Bool, target: Vec3, scene: Scene, rest: Scene) -> [PropertyChange] {
        guard let hand = rest.objects[handle.end] else { return [] }
        let local = scene.worldTransform(of: handle.character).inverseApply(to: target)
        let delta = local - hand.transform.position
        let side: Double = left ? -1 : 1
        let out = min(max(delta.x / (side * BlobRig.handReach.x), -1), 1)
        let up = min(max(delta.y / BlobRig.handReach.y, -1), 1)
        return [
            PropertyChange(object: handle.character, key: left ? .handLeftX : .handRightX, value: .float(out)),
            PropertyChange(object: handle.character, key: left ? .handLeftY : .handRightY, value: .float(up))
        ]
    }

    /// Analytic two-bone IK keeping the limb's current bend plane (the elbow or knee bends the way it already does).
    static func twoBone(upper: ObjectID, lower: ObjectID, end: ObjectID, target: Vec3, in scene: Scene) -> [PropertyChange] {
        let a = scene.worldTransform(of: upper)
        let b = scene.worldTransform(of: lower)
        let c = scene.worldTransform(of: end)
        let upperLength = a.position.distance(to: b.position)
        let lowerLength = b.position.distance(to: c.position)
        guard upperLength > 1e-5, lowerLength > 1e-5 else { return [] }
        let reach = target - a.position
        let distance = min(max(reach.length, abs(upperLength - lowerLength) + 1e-4), upperLength + lowerLength - 1e-4)
        let toward = reach.length > 1e-6 ? reach.normalized : (c.position - a.position).normalized
        // The plane the limb bends in now (fallback: bend forward).
        var normal = (b.position - a.position).cross(c.position - a.position)
        if normal.length < 1e-6 { normal = toward.cross(Vec3(0, 0, 1)) }
        if normal.length < 1e-6 { normal = toward.cross(Vec3(1, 0, 0)) }
        var perpendicular = normal.normalized.cross(toward).normalized
        if perpendicular.dot(b.position - a.position) < 0 { perpendicular = -perpendicular }
        let cosine = min(max((upperLength * upperLength + distance * distance - lowerLength * lowerLength) / (2 * upperLength * distance), -1), 1)
        let sine = (1 - cosine * cosine).squareRoot()
        let elbow = a.position + toward * (cosine * upperLength) + perpendicular * (sine * upperLength)
        let wrist = a.position + toward * distance
        // World turns: the upper bone onto the new elbow, then the lower bone onto the wrist.
        let upperTurn = Quat.between(b.position - a.position, elbow - a.position)
        let movedLower = upperTurn.act(c.position - b.position)
        let lowerTurn = Quat.between(movedLower, wrist - elbow)
        let upperWorld = (upperTurn * a.rotation).normalized
        let lowerWorld = (lowerTurn * upperTurn * b.rotation).normalized
        let upperParent = scene.objects[upper]?.parent.map { scene.worldTransform(of: $0).rotation } ?? .identity
        // The lower joint hangs under the upper one (directly or through plain groups).
        let lowerParentRest = scene.objects[lower]?.parent.map { scene.worldTransform(of: $0).rotation } ?? .identity
        let lowerParentNew = (upperTurn * lowerParentRest).normalized
        return [
            PropertyChange(object: upper, key: .rotation, value: .quat((upperParent.inverse * upperWorld).normalized)),
            PropertyChange(object: lower, key: .rotation, value: .quat((lowerParentNew.inverse * lowerWorld).normalized))
        ]
    }
}
