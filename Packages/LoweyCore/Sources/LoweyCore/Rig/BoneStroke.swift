import Foundation

/// "Draw a bone": a Pencil stroke through a limb, tail or rope becomes a chain of joints along its middle. Everything
/// here is in the rig's space (the space of the vertices the renderer draws for the object).
public enum BoneStroke {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// The stroke didn't cross the object.
        case missed
        /// Too short to hold a bone.
        case tooShort

        public var description: String {
            switch self {
            case .missed: "Draw the bone across the object, through the part that should bend."
            case .tooShort: "Draw a longer bone, through the whole part that should bend."
            }
        }
    }

    /// One point of the centreline and how thick the part is there.
    public struct Sample: Hashable, Sendable {
        public var point: Vec3
        public var thickness: Double

        public init(point: Vec3, thickness: Double) {
            self.point = point
            self.thickness = thickness
        }
    }

    /// For each ray (a Pencil sample, looking into the object): midway between where it first enters the surface and
    /// where it leaves again. Rays that miss are skipped; a ray that enters and never leaves (an open shell) keeps the
    /// entry point.
    public static func centreline(rays: [Ray], surface: TriangleBVH) -> [Sample] {
        rays.compactMap { ray in
            let direction = ray.direction.normalized
            let hits = surface.hits(origin: ray.origin, direction: direction)
            guard let entry = hits.first else { return nil }
            let exit = hits.dropFirst().first { $0 > entry + 1e-6 } ?? entry
            return Sample(point: ray.origin + direction * ((entry + exit) / 2), thickness: exit - entry)
        }
    }

    /// For each ray, where it crosses a drawing's plane (a 2D drawn puppet lies on one).
    public static func onPlane(rays: [Ray], origin: Vec3, normal: Vec3) -> [Sample] {
        rays.compactMap { ray in
            GuideSurface.plane(origin: origin, normal: normal).intersect(ray).map { Sample(point: $0.point, thickness: 0) }
        }
    }

    /// The rig with a chain along `samples` added. The end nearer the existing bones (or, on a first chain, nearer the
    /// body) is the chain's base; it hangs from the bone it starts on. A first chain also gets a root joint in the
    /// middle of the rest of the body, so the body holds still while the chain bends. `surface` is every vertex of the
    /// object (rig space).
    public static func addingChain(_ samples: [Sample], to rig: ObjectRig?, surface: [Vec3]) throws(Failure) -> ObjectRig {
        guard !samples.isEmpty else { throw .missed }
        let path = smoothed(samples.map(\.point))
        let length = zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        let size = (Bounds(points: surface) ?? Bounds(points: path))?.size.length ?? 1
        guard path.count >= 2, length > size * 0.04 else { throw .tooShort }
        let thick = samples.map(\.thickness).filter { $0 > 0 }
        let thickness = thick.isEmpty ? length / 6 : thick.sorted()[thick.count / 2]
        let bones = min(max(Int((length / max(thickness * 1.4, 1e-9)).rounded()), 2), 8)
        var points = resample(path, count: bones + 1)
        var result = rig ?? ObjectRig(skeleton: Skeleton(joints: []))
        let parent: Int?
        if let rig, !rig.skeleton.isEmpty {
            let anchors = rig.segments.isEmpty ? rig.restPositions.indices
                .map { BoneSegment(joint: $0, head: rig.restPositions[$0], tail: rig.restPositions[$0]) } : rig.segments
            func distance(_ point: Vec3) -> Double { anchors.map { $0.distance(to: point) }.min() ?? .infinity }
            if distance(points[points.count - 1]) < distance(points[0]) { points.reverse() }
            parent = anchors.min { $0.distance(to: points[0]) < $1.distance(to: points[0]) }?.joint
        } else {
            let body = surface.filter { vertex in path.allSatisfy { $0.distance(to: vertex) > thickness * 1.5 } }
            let centre = body.isEmpty ? nil : body.reduce(Vec3.zero, +) / Double(body.count)
            if let centre, points[points.count - 1].distance(to: centre) < points[0].distance(to: centre) { points.reverse() }
            if let centre, centre.distance(to: points[0]) > thickness * 0.5 {
                result = ObjectRig(names: ["root"], parents: [nil], positions: [centre])
                parent = 0
            } else {
                parent = nil
            }
        }
        result.append(chain: points, parent: parent)
        result.skin = nil
        result.points = nil
        result.surface = nil
        return result
    }

    /// A light moving average, so a wobbly hand doesn't make a zig-zag chain (the ends stay put).
    static func smoothed(_ points: [Vec3]) -> [Vec3] {
        guard points.count > 4 else { return points }
        var result = points
        for index in 1 ..< points.count - 1 {
            let low = max(index - 2, 0)
            let high = min(index + 2, points.count - 1)
            result[index] = points[low ... high].reduce(Vec3.zero, +) / Double(high - low + 1)
        }
        return result
    }

    /// `count` points evenly spaced along the polyline (its ends included).
    static func resample(_ path: [Vec3], count: Int) -> [Vec3] {
        var lengths = [0.0]
        for (a, b) in zip(path, path.dropFirst()) {
            lengths.append(lengths[lengths.count - 1] + a.distance(to: b))
        }
        let total = lengths[lengths.count - 1]
        guard total > 0, count > 1 else { return [path[0]] }
        var result: [Vec3] = []
        var segment = 0
        for step in 0 ..< count {
            let along = total * Double(step) / Double(count - 1)
            while segment < path.count - 2, lengths[segment + 1] < along {
                segment += 1
            }
            let span = lengths[segment + 1] - lengths[segment]
            let t = span > 0 ? (along - lengths[segment]) / span : 0
            result.append(path[segment].lerp(to: path[segment + 1], min(max(t, 0), 1)))
        }
        return result
    }
}

public extension ObjectRig {
    /// Adds joints at `points` (rig space), each the child of the one before; the first hangs from `parent`.
    mutating func append(chain points: [Vec3], parent: Int?) {
        var model = skeleton.modelRest
        var previous = parent
        for point in points {
            let name = newJointName()
            let offset = previous.map { point - model[$0].position } ?? point
            skeleton.joints.append(Joint(name: name, parent: previous, rest: Transform(position: offset)))
            model.append(Transform(position: point))
            previous = skeleton.joints.count - 1
        }
    }

    /// The rig without `joint` and everything hanging from it.
    func removing(_ joint: Int) -> ObjectRig {
        var gone = Set([joint])
        for index in skeleton.joints.indices where skeleton.joints[index].parent.map(gone.contains) == true {
            gone.insert(index)
        }
        let kept = skeleton.joints.indices.filter { !gone.contains($0) }
        let remap = Dictionary(uniqueKeysWithValues: kept.enumerated().map { ($1, $0) })
        let joints = kept.map { index in
            var joint = skeleton.joints[index]
            joint.parent = joint.parent.flatMap { remap[$0] }
            return joint
        }
        let names = Set(joints.map(\.name))
        return ObjectRig(skeleton: Skeleton(joints: joints), standard: standard, tips: tips.filter { names.contains($0.key) })
    }
}
