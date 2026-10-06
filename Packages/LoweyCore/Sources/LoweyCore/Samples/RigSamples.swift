import Foundation

/// Shapes the rigging checks are made on (and Diagnostics can show): a creature with a long tail behind it.
public enum RigSamples {
    /// The tail runs along +x from inside the body to its tip.
    public static let tailStart = 0.32
    public static let tailEnd = 1.6
    public static let tailHeight = 0.62

    /// A body (a box, 0.8 × 0.5 × 0.5 standing on the ground) with a tapering tail behind it: two separate pieces,
    /// as models from other apps often are.
    public static func creature() -> MeshData {
        var mesh = box(centre: Vec3(0, 0.5, 0), size: Vec3(0.8, 0.5, 0.5), steps: 6)
        mesh.append(tube(from: tailStart, to: tailEnd, height: tailHeight, radius: (0.09, 0.03), rings: 24, sides: 12))
        return mesh
    }

    /// The creature as a GLB, so it comes in through the same import path as anyone's model.
    public static func creatureGLB() -> Data {
        var scene = Scene(id: "creature", name: "Creature")
        let object = SceneObject(id: "creature", name: "Creature", kind: .asset("creature"))
        scene.objects[object.id] = object
        scene.roots = [object.id]
        let mesh = creature()
        return GLTFScene.glb(nil, in: scene, look: Look()) { _ in
            [GLTFScene.LocalPart(name: "Creature", mesh: mesh, material: ExportMaterial(color: RGBA(0.85, 0.55, 0.3)))]
        }
    }

    /// A box with each side cut into `steps` × `steps` squares (bone heat needs vertices to spread over).
    static func box(centre: Vec3, size: Vec3, steps: Int) -> MeshData {
        var mesh = MeshData()
        let axes: [(normal: Vec3, u: Vec3, v: Vec3)] = [
            (.unitX, .unitY, .unitZ), (-.unitX, .unitZ, .unitY), (.unitY, .unitZ, .unitX),
            (-.unitY, .unitX, .unitZ), (.unitZ, .unitX, .unitY), (-.unitZ, .unitY, .unitX)
        ]
        for (normal, u, v) in axes {
            let start = UInt32(mesh.positions.count)
            for i in 0 ... steps {
                for j in 0 ... steps {
                    let a = Double(i) / Double(steps) - 0.5
                    let b = Double(j) / Double(steps) - 0.5
                    let local = normal * 0.5 + u * a + v * b
                    mesh.positions.append((centre + local.scaled(by: size)).float3)
                    mesh.normals.append(normal.float3)
                    mesh.uvs.append(SIMD2<Float>(Float(a + 0.5), Float(b + 0.5)))
                }
            }
            let row = UInt32(steps + 1)
            for i in 0 ..< UInt32(steps) {
                for j in 0 ..< UInt32(steps) {
                    let corner = start + i * row + j
                    // u × v = normal for every side above, so (i, j) → (i+1, j) → (i+1, j+1) is counter-clockwise.
                    mesh.indices += [corner, corner + row, corner + row + 1, corner, corner + row + 1, corner + 1]
                }
            }
        }
        return mesh
    }

    /// A tube along +x, its radius going from `radius.0` to `radius.1`, closed at the tip.
    static func tube(from start: Double, to end: Double, height: Double, radius: (Double, Double), rings: Int, sides: Int) -> MeshData {
        var mesh = MeshData()
        for ring in 0 ... rings {
            let t = Double(ring) / Double(rings)
            let x = start + (end - start) * t
            let r = radius.0 + (radius.1 - radius.0) * t
            for side in 0 ..< sides {
                let angle = 2 * Double.pi * Double(side) / Double(sides)
                let normal = Vec3(0, cos(angle), sin(angle))
                mesh.positions.append(Vec3(x, height + r * cos(angle), r * sin(angle)).float3)
                mesh.normals.append(normal.float3)
                mesh.uvs.append(SIMD2<Float>(Float(t), Float(Double(side) / Double(sides))))
            }
        }
        let count = UInt32(sides)
        for ring in 0 ..< UInt32(rings) {
            for side in 0 ..< count {
                let a = ring * count + side
                let b = ring * count + (side + 1) % count
                let c = a + count
                let d = b + count
                mesh.indices += [a, b, d, a, d, c]
            }
        }
        // The tip: a fan to a point just past the last ring.
        let tip = UInt32(mesh.positions.count)
        mesh.positions.append(Vec3(end + radius.1, height, 0).float3)
        mesh.normals.append(Vec3.unitX.float3)
        mesh.uvs.append(SIMD2<Float>(1, 0.5))
        let last = UInt32(rings) * count
        for side in 0 ..< count {
            mesh.indices += [last + side, last + (side + 1) % count, tip]
        }
        return mesh
    }
}
