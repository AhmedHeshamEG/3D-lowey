import Foundation

public extension EditableMesh {
    /// A blockout shape as an editable mesh at a size (metres), its base on y = 0 like the shape itself.
    static func primitive(_ shape: PrimitiveShape, size: Vec3 = .one) -> EditableMesh {
        let unit = MeshBuilder.mesh(from: PrimitiveMesh.make(shape))
        return unit.scaled(by: size)
    }

    /// An axis-aligned box between two corners.
    static func box(min lo: Vec3, max hi: Vec3) -> EditableMesh {
        let corners = (0 ..< 8).map { i in
            Vec3(i & 1 == 0 ? lo.x : hi.x, i & 2 == 0 ? lo.y : hi.y, i & 4 == 0 ? lo.z : hi.z)
        }
        let faces: [[Int]] = [[0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4], [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6]]
        return EditableMesh(vertices: corners, faces: faces.map { Face($0) })
    }

    /// A round prism standing on `base`: `segments` sides, axis along +Y.
    static func cylinder(base: Vec3, radius: Double, height: Double, segments: Int = 32) -> EditableMesh {
        let outline = (0 ..< max(segments, 3)).map { index -> Vec3 in
            let angle = Double(index) / Double(max(segments, 3)) * 2 * .pi
            return base + Vec3(cos(angle) * radius, 0, -sin(angle) * radius)
        }
        return Prism.make(outline: outline, holes: [], normal: .unitY, from: 0, to: height)
    }

    /// The mesh with every vertex scaled about the origin (a negative scale mirrors, so faces are turned back out).
    func scaled(by scale: Vec3) -> EditableMesh {
        let moved = vertices.map { $0.scaled(by: scale) }
        let mirrored = scale.x * scale.y * scale.z < 0
        let faces = mirrored ? faces.map { Face(loops: $0.loops.map { Array($0.reversed()) }) } : faces
        return EditableMesh(vertices: moved, faces: faces)
    }

    /// The mesh carried through a transform (scale, then rotation, then position).
    func transformed(by transform: Transform) -> EditableMesh {
        let scaled = scaled(by: transform.scale)
        return EditableMesh(vertices: scaled.vertices.map { transform.rotation.act($0) + transform.position }, faces: scaled.faces)
    }

    /// The mesh brought back from world space into a transform's local space (the inverse of `transformed`).
    func untransformed(by transform: Transform) -> EditableMesh {
        let inverse = transform.rotation.inverse
        let local = EditableMesh(vertices: vertices.map { inverse.act($0 - transform.position) }, faces: faces)
        let scale = transform.scale
        return local.scaled(by: Vec3(1 / nonZero(scale.x), 1 / nonZero(scale.y), 1 / nonZero(scale.z)))
    }

    private func nonZero(_ value: Double) -> Double {
        abs(value) < 1e-12 ? 1e-12 : value
    }
}
