import Foundation

/// One Shadow Brush dab: pushes the toon shadow in (negative) or pulls it out (positive) around a point on the
/// object's surface. Stored as dabs, not per-vertex numbers, so the painting survives any change of mesh density
/// (bevel segments, a re-meshed drawing) and stays small in the file.
public struct ShadowDab: Codable, Hashable, Sendable {
    /// Object-local position.
    public var position: Vec3
    /// Radius in object-local units.
    public var radius: Double
    /// −1 (always in shadow) … +1 (always lit), scaled by the falloff.
    public var amount: Double

    public init(position: Vec3, radius: Double, amount: Double) {
        self.position = position
        self.radius = max(radius, 1e-4)
        self.amount = min(max(amount, -1), 1)
    }
}

public enum ShadowPaint {
    /// The shadow bias at a vertex: every dab's amount with a smooth falloff (1 at the centre, 0 at the radius),
    /// summed and clamped to −1…1.
    public static func bias(at point: SIMD3<Float>, dabs: [ShadowDab]) -> Float {
        var total = 0.0
        for dab in dabs {
            let dx = Double(point.x) - dab.position.x
            let dy = Double(point.y) - dab.position.y
            let dz = Double(point.z) - dab.position.z
            let distance = (dx * dx + dy * dy + dz * dz).squareRoot() / dab.radius
            guard distance < 1 else { continue }
            let t = 1 - distance
            total += dab.amount * t * t * (3 - 2 * t)
        }
        return Float(min(max(total, -1), 1))
    }

    /// Per-vertex bias for a mesh (empty when there's no painting).
    public static func biases(for mesh: MeshData, dabs: [ShadowDab]) -> [Float] {
        guard !dabs.isEmpty else { return [] }
        return mesh.positions.map { bias(at: $0, dabs: dabs) }
    }

    /// Adds a dab, merging it into an existing one at nearly the same place (a held brush doesn't pile up
    /// thousands of dabs).
    public static func adding(_ dab: ShadowDab, to dabs: [ShadowDab]) -> [ShadowDab] {
        var result = dabs
        if let index = result.lastIndex(where: { ($0.position - dab.position).length < dab.radius * 0.25 && ($0.amount >= 0) == (dab.amount >= 0) }) {
            result[index].amount = min(max(result[index].amount + dab.amount * 0.5, -1), 1)
            result[index].radius = max(result[index].radius, dab.radius)
        } else {
            result.append(dab)
        }
        return result
    }
}

public extension SceneObject {
    /// Shadow Brush painting (empty = none).
    var shadowDabs: [ShadowDab] {
        get { shadowPaint ?? [] }
        set { shadowPaint = newValue.isEmpty ? nil : newValue }
    }
}
