import Foundation

/// A character built from rigid parts (the character builder, or any hand-made puppet) whose joints carry humanoid
/// bone names. It plays every humanoid clip — imported (Mixamo & co.) or built in — through the same retargeting
/// as skinned models: the joints form a skeleton, clip poses are written back onto the joint objects.
public struct PuppetRig: Sendable {
    public var rig: RigAsset
    /// The object behind each skeleton joint (same order).
    public var joints: [ObjectID]

    /// Reads the joints under `root` (objects with a `bone` property). Arms are straightened to a T-pose for
    /// retargeting (clips are made for T-poses); the objects keep their relaxed pose when no clip plays.
    public static func build(_ root: ObjectID, in scene: Scene) -> PuppetRig? {
        guard scene.objects[root]?[.rigStandard]?.stringValue == SkeletonStandard.humanoid.rawValue else { return nil }
        var ids: [ObjectID] = []
        var parents: [Int?] = []
        var rests: [Transform] = []
        var modelRest: [Transform] = []
        let known = Set(SkeletonStandard.humanoid.bones)
        let rootWorld = scene.worldTransform(of: root)
        // Joints are direct children of their parent joint (the builder makes them that way); model space is the
        // character's own space (its scale excluded).
        func visit(_ id: ObjectID, parentJoint: Int?) {
            guard let object = scene.objects[id] else { return }
            var jointIndex = parentJoint
            if let bone = object[.bone]?.stringValue, known.contains(bone) {
                let index = ids.count
                let model = Transform.relative(world: scene.worldTransform(of: id), toParent: rootWorld)
                let parentModel = parentJoint.map { modelRest[$0] } ?? .identity
                ids.append(id)
                parents.append(parentJoint)
                modelRest.append(model)
                rests.append(Transform.relative(world: model, toParent: parentModel))
                jointIndex = index
            }
            for child in object.children {
                visit(child, parentJoint: jointIndex)
            }
        }
        for child in scene.objects[root]?.children ?? [] {
            visit(child, parentJoint: nil)
        }
        guard !ids.isEmpty else { return nil }
        let names = ids.map { scene.objects[$0]?[.bone]?.stringValue ?? "" }
        // T-pose: rotate each upper arm (in model space) so the arm points straight out sideways.
        for (index, name) in names.enumerated() where name == "leftUpperArm" || name == "rightUpperArm" {
            guard let child = parents.firstIndex(where: { $0 == index }) else { continue }
            let direction = modelRest[index].rotation.act(rests[child].position).normalized
            let target = Vec3(name == "leftUpperArm" ? 1 : -1, 0, 0)
            let correction = Quat.between(direction, target)
            let parentModel = parents[index].map { modelRest[$0].rotation } ?? .identity
            let corrected = (correction * modelRest[index].rotation).normalized
            rests[index].rotation = (parentModel.inverse * corrected).normalized
            // Everything below follows in model space.
            var stack = [index]
            while let current = stack.popLast() {
                let parentRotation = parents[current].map { modelRest[$0].rotation } ?? .identity
                if current == index {
                    modelRest[current].rotation = corrected
                } else {
                    modelRest[current].rotation = (parentRotation * rests[current].rotation).normalized
                }
                stack += parents.indices.filter { parents[$0] == current }
            }
        }
        let skeleton = Skeleton(joints: names.indices.map { Joint(name: names[$0], parent: parents[$0], rest: rests[$0]) })
        let boneMap = Dictionary(names.map { ($0, $0) }, uniquingKeysWith: { first, _ in first })
        return PuppetRig(rig: RigAsset(skeleton: skeleton, clips: [], standard: .humanoid, boneMap: boneMap), joints: ids)
    }

    /// Writes a pose (local joint transforms from `ClipMixer`) onto the joint objects. Hips move, the rest rotate.
    public func apply(_ pose: [Transform], to scene: inout Scene, animated: inout Set<ObjectID>) {
        for (index, id) in joints.enumerated() where index < pose.count {
            guard var object = scene.objects[id] else { continue }
            var transform = object.transform
            transform.rotation = pose[index].rotation
            if rig.skeleton.joints[index].name == "hips" { transform.position = pose[index].position }
            object.transform = transform
            scene.objects[id] = object
            animated.insert(id)
        }
    }
}

public extension Quat {
    /// Shortest rotation taking direction `a` to direction `b`.
    static func between(_ a: Vec3, _ b: Vec3) -> Quat {
        let from = a.normalized
        let to = b.normalized
        let d = from.dot(to)
        if d > 0.999999 { return .identity }
        if d < -0.999999 {
            let axis = abs(from.x) < 0.9 ? from.cross(Vec3(1, 0, 0)) : from.cross(Vec3(0, 1, 0))
            return Quat(angle: .pi, axis: axis.normalized)
        }
        let axis = from.cross(to)
        return Quat(x: axis.x, y: axis.y, z: axis.z, w: 1 + d).normalized
    }
}
