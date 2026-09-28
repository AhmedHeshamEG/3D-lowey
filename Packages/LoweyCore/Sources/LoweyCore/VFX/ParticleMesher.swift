import Foundation

/// Turns particles into a few low-poly meshes, one per colour band, so a whole effect is a handful of
/// draw calls: diamonds (octahedra), streaks stretched along their motion, flat tumbling cards, puffs.
public enum ParticleMesher {
    public struct Band: Sendable {
        public var mesh: MeshData
        public var color: RGBA
        public var opacity: Double
    }

    /// At most this many bands (colour × opacity buckets).
    public static let maxBands = 8

    public static func bands(_ particles: [Particle], recipe: ParticleRecipe) -> [Band] {
        guard !particles.isEmpty else { return [] }
        // Bucket by quantised colour and opacity so fading particles share a few materials.
        var buckets: [Int: (mesh: MeshData, r: Double, g: Double, b: Double, a: Double, count: Double)] = [:]
        for particle in particles where particle.size > 1e-4 && particle.color.a > 0.02 {
            let key = bucket(particle.color)
            var entry = buckets[key] ?? (MeshData(), 0, 0, 0, 0, 0)
            append(particle, shape: recipe.shape, to: &entry.mesh)
            entry.r += particle.color.r
            entry.g += particle.color.g
            entry.b += particle.color.b
            entry.a += particle.color.a
            entry.count += 1
            buckets[key] = entry
        }
        var result = buckets.sorted { $0.key < $1.key }.map { _, entry in
            Band(mesh: entry.mesh, color: RGBA(entry.r / entry.count, entry.g / entry.count, entry.b / entry.count),
                 opacity: entry.a / entry.count)
        }
        // Merge the smallest bands into their neighbours when there are too many.
        while result.count > maxBands {
            let index = result.indices.dropLast().min { result[$0].mesh.triangleCount < result[$1].mesh.triangleCount } ?? 0
            var merged = result[index + 1]
            merged.mesh.append(result[index].mesh)
            result[index + 1] = merged
            result.remove(at: index)
        }
        return result
    }

    static func bucket(_ color: RGBA) -> Int {
        let r = Int(color.r * 3.99), g = Int(color.g * 3.99), b = Int(color.b * 3.99), a = Int(color.a * 3.99)
        return ((r * 4 + g) * 4 + b) * 4 + a
    }

    static func append(_ particle: Particle, shape: ParticleRecipe.Shape, to mesh: inout MeshData) {
        let s = Float(particle.size / 2)
        let p = SIMD3<Float>(Float(particle.position.x), Float(particle.position.y), Float(particle.position.z))
        // Local frame: `forward` along the motion for streaks, spun around Y otherwise.
        var forward = SIMD3<Float>(0, 1, 0)
        var right = SIMD3<Float>(Float(cos(particle.spin)), 0, Float(sin(particle.spin)))
        var up = SIMD3<Float>(-right.z, 0, right.x)
        var stretch: Float = 1
        var flatten: Float = 1
        switch shape {
        case .streak:
            let v = SIMD3<Float>(Float(particle.velocity.x), Float(particle.velocity.y), Float(particle.velocity.z))
            let speed = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
            if speed > 1e-4 {
                forward = v / speed
                let helper = abs(forward.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
                right = normalize3(cross3(forward, helper), fallback: SIMD3(1, 0, 0))
                up = cross3(right, forward)
            }
            stretch = 3 + min(speed * 0.04, 6)
        case .card:
            // A tumbling flat card: tilt the frame with the spin too.
            let tilt = Float(sin(particle.spin * 1.7))
            forward = normalize3(SIMD3<Float>(tilt, 1, Float(cos(particle.spin))), fallback: SIMD3(0, 1, 0))
            right = normalize3(cross3(forward, SIMD3<Float>(0, 0, 1)), fallback: SIMD3(1, 0, 0))
            up = cross3(right, forward)
            flatten = 0.08
        case .puff, .diamond:
            break
        }
        // Octahedron: six tips around the centre.
        let tips = [
            p + forward * (s * stretch), p - forward * (s * stretch),
            p + right * s, p - right * s,
            p + up * (s * flatten), p - up * (s * flatten)
        ]
        let faces: [(Int, Int, Int)] = [(0, 2, 4), (0, 4, 3), (0, 3, 5), (0, 5, 2), (1, 4, 2), (1, 3, 4), (1, 5, 3), (1, 2, 5)]
        for (a, b, c) in faces {
            let normal = normalize3(cross3(tips[b] - tips[a], tips[c] - tips[a]), fallback: SIMD3(0, 1, 0))
            let i0 = mesh.addVertex(tips[a], normal: normal)
            let i1 = mesh.addVertex(tips[b], normal: normal)
            let i2 = mesh.addVertex(tips[c], normal: normal)
            mesh.addTriangle(i0, i1, i2)
        }
    }
}
