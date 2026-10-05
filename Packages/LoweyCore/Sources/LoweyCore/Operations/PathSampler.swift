import Foundation

/// Evenly spaced places along a polyline, for arrays along a path. The first place is the start of the path; each
/// copy is offset from the original by where it lands minus where the path starts, so the original stays put and the
/// copies follow the path's shape from there.
public enum PathSampler {
    /// Places for `count` objects in all (the original included, so `count - 1` copies). An open path puts the last
    /// copy on its end; a closed one spreads them all the way round.
    public static func transforms(along points: [Vec3], closed: Bool, count: Int, from base: Transform, align: Bool) -> [Transform] {
        let path = closed && points.count > 2 && points.first != points.last ? points + [points[0]] : points
        guard path.count >= 2, count >= 2 else { return [] }
        let lengths = zip(path, path.dropFirst()).map { $0.distance(to: $1) }
        let total = lengths.reduce(0, +)
        guard total > 1e-12 else { return [] }
        let step = total / Double(closed ? count : count - 1)
        let start = path[0]
        let firstTangent = tangent(at: 0, path: path, lengths: lengths)
        return (1 ..< count).map { index in
            let (point, direction) = sample(at: step * Double(index), path: path, lengths: lengths)
            var transform = base
            transform.position = base.position + (point - start)
            if align {
                transform.rotation = (Quat.rotation(from: firstTangent, to: direction) * base.rotation).normalized
            }
            return transform
        }
    }

    /// The point and the direction of travel at a distance along the path.
    static func sample(at distance: Double, path: [Vec3], lengths: [Double]) -> (Vec3, Vec3) {
        var remaining = distance
        for (index, length) in lengths.enumerated() {
            if remaining <= length || index == lengths.count - 1 {
                let t = length > 0 ? min(max(remaining / length, 0), 1) : 0
                return (path[index].lerp(to: path[index + 1], t), tangent(at: index, path: path, lengths: lengths))
            }
            remaining -= length
        }
        return (path[path.count - 1], tangent(at: lengths.count - 1, path: path, lengths: lengths))
    }

    static func tangent(at segment: Int, path: [Vec3], lengths: [Double]) -> Vec3 {
        let index = min(max(segment, 0), lengths.count - 1)
        let direction = path[index + 1] - path[index]
        return direction.length > 1e-15 ? direction.normalized : .unitX
    }
}
