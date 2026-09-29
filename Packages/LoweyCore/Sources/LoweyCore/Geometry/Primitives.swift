import Foundation

/// Low-poly blockout shapes. All unit-sized, pivot at the center of the base (y = 0).
public enum PrimitiveMesh {
    /// Raw triangles (normals are recomputed by `shaded`).
    public static func make(_ shape: PrimitiveShape) -> MeshData {
        switch shape {
        case .cube: box(size: SIMD3<Float>(1, 1, 1))
        case .sphere: sphere(segments: 16, rings: 10)
        case .cylinder: cylinder(segments: 14, radiusTop: 0.5, radiusBottom: 0.5)
        case .cone: cylinder(segments: 14, radiusTop: 0, radiusBottom: 0.5)
        case .plane: plane()
        case .torus: torus(segments: 18, sides: 8, major: 0.4, minor: 0.12)
        case .ramp: ramp()
        }
    }

    /// Mesh with the requested shading. Smooth uses auto-smooth (hard edges stay hard).
    public static func make(_ shape: PrimitiveShape, shading: ShadingStyle) -> MeshData {
        make(shape).shaded(shading)
    }

    /// Native bounds of each primitive.
    public static func bounds(_ shape: PrimitiveShape) -> Bounds {
        switch shape {
        case .plane: Bounds(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 0, 0.5))
        case .torus: Bounds(min: Vec3(-0.52, 0, -0.52), max: Vec3(0.52, 0.24, 0.52))
        default: .unitBase
        }
    }

    static func quad(_ mesh: inout MeshData, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
        // a-b-c-d counter-clockwise seen from the front.
        let n = normalize3(cross3(b - a, c - a), fallback: SIMD3<Float>(0, 1, 0))
        let i0 = mesh.addVertex(a, normal: n, uv: SIMD2<Float>(0, 0))
        let i1 = mesh.addVertex(b, normal: n, uv: SIMD2<Float>(1, 0))
        let i2 = mesh.addVertex(c, normal: n, uv: SIMD2<Float>(1, 1))
        let i3 = mesh.addVertex(d, normal: n, uv: SIMD2<Float>(0, 1))
        mesh.addTriangle(i0, i1, i2)
        mesh.addTriangle(i0, i2, i3)
    }

    public static func box(size: SIMD3<Float>) -> MeshData {
        var mesh = MeshData()
        let hx = size.x / 2, hz = size.z / 2, h = size.y
        let p000 = SIMD3<Float>(-hx, 0, -hz), p100 = SIMD3<Float>(hx, 0, -hz)
        let p010 = SIMD3<Float>(-hx, h, -hz), p110 = SIMD3<Float>(hx, h, -hz)
        let p001 = SIMD3<Float>(-hx, 0, hz), p101 = SIMD3<Float>(hx, 0, hz)
        let p011 = SIMD3<Float>(-hx, h, hz), p111 = SIMD3<Float>(hx, h, hz)
        quad(&mesh, p001, p101, p111, p011) // +Z front
        quad(&mesh, p100, p000, p010, p110) // -Z back
        quad(&mesh, p101, p100, p110, p111) // +X right
        quad(&mesh, p000, p001, p011, p010) // -X left
        quad(&mesh, p011, p111, p110, p010) // +Y top
        quad(&mesh, p000, p100, p101, p001) // -Y bottom
        return mesh
    }

    static func plane() -> MeshData {
        var mesh = MeshData()
        quad(&mesh, SIMD3<Float>(-0.5, 0, 0.5), SIMD3<Float>(0.5, 0, 0.5), SIMD3<Float>(0.5, 0, -0.5), SIMD3<Float>(-0.5, 0, -0.5))
        return mesh
    }

    static func ramp() -> MeshData {
        var mesh = MeshData()
        let a = SIMD3<Float>(-0.5, 0, 0.5), b = SIMD3<Float>(0.5, 0, 0.5)
        let c = SIMD3<Float>(0.5, 0, -0.5), d = SIMD3<Float>(-0.5, 0, -0.5)
        let e = SIMD3<Float>(0.5, 1, -0.5), f = SIMD3<Float>(-0.5, 1, -0.5)
        quad(&mesh, a, b, e, f) // slope
        quad(&mesh, c, d, f, e) // back wall
        quad(&mesh, d, c, b, a) // bottom
        // sides (triangles)
        let n1 = normalize3(cross3(c - b, e - b), fallback: SIMD3<Float>(1, 0, 0))
        let i0 = mesh.addVertex(b, normal: n1), i1 = mesh.addVertex(c, normal: n1), i2 = mesh.addVertex(e, normal: n1)
        mesh.addTriangle(i0, i1, i2)
        let n2 = normalize3(cross3(a - d, f - d), fallback: SIMD3<Float>(-1, 0, 0))
        let j0 = mesh.addVertex(d, normal: n2), j1 = mesh.addVertex(a, normal: n2), j2 = mesh.addVertex(f, normal: n2)
        mesh.addTriangle(j0, j1, j2)
        return mesh
    }

    static func sphere(segments: Int, rings: Int) -> MeshData {
        var mesh = MeshData()
        let radius: Float = 0.5
        for ring in 0 ... rings {
            let v = Float(ring) / Float(rings)
            let phi = v * Float.pi
            for segment in 0 ... segments {
                let u = Float(segment) / Float(segments)
                let theta = u * 2 * Float.pi
                let normal = SIMD3<Float>(sin(phi) * sin(theta), cos(phi), sin(phi) * cos(theta))
                mesh.addVertex(normal * radius + SIMD3<Float>(0, radius, 0), normal: normal, uv: SIMD2<Float>(u, 1 - v))
            }
        }
        let stride = UInt32(segments + 1)
        for ring in 0 ..< UInt32(rings) {
            for segment in 0 ..< UInt32(segments) {
                let a = ring * stride + segment
                let b = a + stride
                if ring != 0 { mesh.addTriangle(a, b, a + 1) }
                if ring != UInt32(rings) - 1 { mesh.addTriangle(a + 1, b, b + 1) }
            }
        }
        return mesh
    }

    static func cylinder(segments: Int, radiusTop: Float, radiusBottom: Float) -> MeshData {
        var mesh = MeshData()
        let height: Float = 1
        func ringPoint(_ i: Int, _ r: Float, _ y: Float) -> SIMD3<Float> {
            let angle = Float(i) / Float(segments) * 2 * Float.pi
            return SIMD3<Float>(sin(angle) * r, y, cos(angle) * r)
        }
        for i in 0 ..< segments {
            let b0 = ringPoint(i, radiusBottom, 0), b1 = ringPoint(i + 1, radiusBottom, 0)
            let t0 = ringPoint(i, radiusTop, height), t1 = ringPoint(i + 1, radiusTop, height)
            if radiusTop > 0 {
                quad(&mesh, b0, b1, t1, t0)
            } else {
                let n = normalize3(cross3(b1 - b0, t0 - b0), fallback: SIMD3<Float>(0, 1, 0))
                let i0 = mesh.addVertex(b0, normal: n), i1 = mesh.addVertex(b1, normal: n), i2 = mesh.addVertex(t0, normal: n)
                mesh.addTriangle(i0, i1, i2)
            }
            // bottom cap
            let down = SIMD3<Float>(0, -1, 0)
            let c = mesh.addVertex(SIMD3<Float>(0, 0, 0), normal: down)
            let bb0 = mesh.addVertex(b0, normal: down), bb1 = mesh.addVertex(b1, normal: down)
            mesh.addTriangle(c, bb1, bb0)
            if radiusTop > 0 {
                let up = SIMD3<Float>(0, 1, 0)
                let ct = mesh.addVertex(SIMD3<Float>(0, height, 0), normal: up)
                let tt0 = mesh.addVertex(t0, normal: up), tt1 = mesh.addVertex(t1, normal: up)
                mesh.addTriangle(ct, tt0, tt1)
            }
        }
        return mesh
    }

    public static func torus(segments: Int, sides: Int, major: Float, minor: Float) -> MeshData {
        var mesh = MeshData()
        for i in 0 ... segments {
            let u = Float(i) / Float(segments) * 2 * Float.pi
            let center = SIMD3<Float>(sin(u) * major, minor, cos(u) * major)
            let outward = SIMD3<Float>(sin(u), 0, cos(u))
            for j in 0 ... sides {
                let v = Float(j) / Float(sides) * 2 * Float.pi
                let normal = outward * cos(v) + SIMD3<Float>(0, sin(v), 0)
                mesh.addVertex(center + normal * minor, normal: normal, uv: SIMD2<Float>(Float(i) / Float(segments), Float(j) / Float(sides)))
            }
        }
        let stride = UInt32(sides + 1)
        for i in 0 ..< UInt32(segments) {
            for j in 0 ..< UInt32(sides) {
                let a = i * stride + j
                let b = (i + 1) * stride + j
                mesh.addTriangle(a, b, b + 1)
                mesh.addTriangle(a, b + 1, a + 1)
            }
        }
        return mesh
    }
}

public extension MeshData {
    /// Auto-smooth: normals are averaged only across edges flatter than `angle` degrees,
    /// so a cube keeps crisp edges while a sphere turns soft. Vertices are not welded.
    func autoSmoothed(angle: Float = 60) -> MeshData {
        let facetedMesh = faceted()
        let threshold = cos(angle * Float.pi / 180)
        // Area-weighted face normals, one per triangle.
        var faceNormals: [SIMD3<Float>] = []
        var faceWeighted: [SIMD3<Float>] = []
        for tri in stride(from: 0, to: facetedMesh.indices.count - 2, by: 3) {
            let a = facetedMesh.positions[Int(facetedMesh.indices[tri])]
            let b = facetedMesh.positions[Int(facetedMesh.indices[tri + 1])]
            let c = facetedMesh.positions[Int(facetedMesh.indices[tri + 2])]
            let weighted = cross3(b - a, c - a)
            faceWeighted.append(weighted)
            faceNormals.append(normalize3(weighted, fallback: SIMD3<Float>(0, 1, 0)))
        }
        // Group corners by position.
        let scale: Float = 1e5
        var groups: [SIMD3<Int32>: [Int]] = [:]
        for (corner, position) in facetedMesh.positions.enumerated() {
            let key = SIMD3<Int32>(Int32((position.x * scale).rounded()), Int32((position.y * scale).rounded()), Int32((position.z * scale).rounded()))
            groups[key, default: []].append(corner)
        }
        var result = facetedMesh
        for corners in groups.values {
            for corner in corners {
                let face = corner / 3
                let normal = faceNormals[face]
                var sum = SIMD3<Float>(0, 0, 0)
                for other in corners {
                    let otherFace = other / 3
                    if dot3(faceNormals[otherFace], normal) >= threshold {
                        sum += faceWeighted[otherFace]
                    }
                }
                result.normals[corner] = normalize3(sum, fallback: normal)
            }
        }
        return result
    }
}
