import Foundation

/// Poses of skeletons that aren't made of objects (drawn rigs, imported skins), as the animator finishes a frame:
/// the clip's pose (or the rest pose), then every joint turned by hand (`bone.<joint>`) on top. Drawn 2D puppets bend
/// their strokes here, so the renderer, picking and every export see the bent drawing.
public enum RigPoses {
    /// Every skeleton's pose: its clip (or its rest), then the joints turned by hand.
    static func resolve(_ scene: Scene, poses: inout [ObjectID: [Transform]], rigs: [AssetID: RigAsset], animated: inout Set<ObjectID>) {
        for (id, object) in scene.objects {
            if let rig = object.rig {
                poses[id] = posed(poses[id] ?? rig.skeleton.restPose, skeleton: rig.skeleton, by: object)
            } else if let asset = object.kind.assetID, let rig = rigs[asset], object.properties.keys.contains(where: { $0.boneJoint != nil }) {
                poses[id] = posed(poses[id] ?? rig.skeleton.restPose, skeleton: rig.skeleton, by: object)
                animated.insert(id)
            }
        }
    }

    /// Drawn puppets bend their strokes to their final pose.
    static func bend(_ scene: inout Scene, poses: [ObjectID: [Transform]], animated: inout Set<ObjectID>) {
        for (id, object) in scene.objects {
            guard let rig = object.rig, let pose = poses[id], case let .drawing(recipe) = object.kind, let weights = rig.points,
                  let bent = bend(recipe, weights: weights, bind: rig.skeleton.modelRest, pose: rig.skeleton.modelSpace(pose)) else { continue }
            scene.objects[id]?.kind = .drawing(bent)
            animated.insert(id)
        }
    }

    /// A drawn rig's pose from its clips ("Rig as a person": the same clips, retargeted onto the drawn skeleton).
    static func clipPose(_ track: ClipTrack, object: SceneObject, rigs: [AssetID: RigAsset], at time: Double, world: Transform,
                         target: (ObjectID) -> Vec3?) -> [Transform]? {
        guard let rig = object.rig, rig.standard != .custom else { return nil }
        return ClipMixer.pose(track: track, character: rig.rigAsset, rigs: rigs, at: time, world: world, targetPosition: target)
    }

    /// `pose` with each joint the object turns by hand set to that turn.
    public static func posed(_ pose: [Transform], skeleton: Skeleton, by object: SceneObject) -> [Transform] {
        var result = pose
        for (index, joint) in skeleton.joints.enumerated() where index < result.count {
            if let turn = object[.boneTurn(joint.name)]?.quatValue {
                result[index].rotation = turn.normalized
            }
        }
        return result
    }

    /// A drawing's strokes moved with its bones (nil when the weights no longer fit the strokes).
    public static func bend(_ recipe: DrawingRecipe, weights: SkinWeights, bind: [Transform], pose: [Transform]) -> DrawingRecipe? {
        let points = recipe.strokes.flatMap(\.points)
        guard points.count == weights.count, !points.isEmpty else { return nil }
        let moved = Skinning.deform(points, weights: weights, bind: bind, pose: pose)
        var result = recipe
        var offset = 0
        for index in result.strokes.indices {
            let count = result.strokes[index].points.count
            result.strokes[index].points = Array(moved[offset ..< offset + count])
            offset += count
        }
        return result
    }
}

/// Linear blend skinning on the CPU: drawings, the posed shapes exports bake, and the tests.
public enum Skinning {
    /// Each point moved by its joints: Σ wᵢ · poseᵢ · bindᵢ⁻¹ (model-space transforms, skeleton order).
    public static func deform(_ points: [Vec3], weights: SkinWeights, bind: [Transform], pose: [Transform]) -> [Vec3] {
        points.indices.map { index in
            guard index < weights.count else { return points[index] }
            var result = Vec3.zero
            var total = 0.0
            for slot in 0 ..< 4 {
                let weight = Double(weights.weights[index][slot])
                let joint = Int(weights.joints[index][slot])
                guard weight > 0, joint < bind.count, joint < pose.count else { continue }
                result += pose[joint].apply(to: bind[joint].inverseApply(to: points[index])) * weight
                total += weight
            }
            return total > 0 ? result / total : points[index]
        }
    }

    /// A mesh in a pose: positions skinned, normals turned with them.
    public static func deform(_ mesh: MeshData, weights: SkinWeights, bind: [Transform], pose: [Transform]) -> MeshData {
        guard mesh.positions.count == weights.count else { return mesh }
        let points = mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
        var result = mesh
        result.positions = deform(points, weights: weights, bind: bind, pose: pose).map(\.float3)
        if mesh.normals.count == mesh.positions.count {
            result.normals = mesh.normals.indices.map { index in
                var turned = Vec3.zero
                for slot in 0 ..< 4 {
                    let weight = Double(weights.weights[index][slot])
                    let joint = Int(weights.joints[index][slot])
                    guard weight > 0, joint < bind.count, joint < pose.count else { continue }
                    let normal = Vec3(Double(mesh.normals[index].x), Double(mesh.normals[index].y), Double(mesh.normals[index].z))
                    turned += (pose[joint].rotation * bind[joint].rotation.inverse).act(normal) * weight
                }
                return turned.length > 1e-9 ? turned.normalized.float3 : mesh.normals[index]
            }
        }
        return result
    }
}

/// The space a rig lives in: the space of the vertices the renderer draws for the object. That's the object's own
/// space, except for bevelled shapes, which are built at their size (their scale leaves the matrix).
public enum RigSpace {
    public static func frame(of id: ObjectID, in scene: Scene) -> Transform {
        var world = scene.worldTransform(of: id)
        if let object = scene.objects[id], let toObject = PaintSource.toObjectSpace(of: object) {
            world.scale = world.scale.scaled(by: Vec3(Double(toObject.x), Double(toObject.y), Double(toObject.z)))
        }
        return world
    }
}
