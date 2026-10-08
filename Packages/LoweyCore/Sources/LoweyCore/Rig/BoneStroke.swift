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

    /// For each ray (a Pencil sample, looking into the object): the middle of the part it passes through. The depth
    /// comes from the mesh, never from the surface under the tip:
    ///
    /// - a ray can pass through several parts (an arm in front of the body): the stroke keeps to the one that makes a
    ///   path at one depth, starting with the part in front (`CrossingPath`);
    /// - where the part runs into something much thicker (an arm into the chest), the ray leaves far behind: there the
    ///   point keeps the depth the stroke had where the part was on its own, instead of diving to the middle of the
    ///   body or rising to its skin.
    ///
    /// Rays that miss are skipped; a ray that enters and never leaves (an open shell) keeps the entry point.
    public static func centreline(rays: [Ray], surface: TriangleBVH) -> [Sample] {
        let rows: [CrossingPath.Row] = rays.compactMap { ray in
            let direction = ray.direction.normalized
            let crossings = CrossingPath.crossings(surface.crossings(origin: ray.origin, direction: direction))
            return crossings.isEmpty ? nil : CrossingPath.Row(origin: ray.origin, direction: direction, crossings: crossings)
        }
        let chosen = CrossingPath.continuous(rows)
        let thicknesses = chosen.map(\.thickness).filter { $0 > 0 }.sorted()
        let typical = thicknesses.isEmpty ? 0 : thicknesses[thicknesses.count / 2]
        let limit = typical * CrossingPath.deepest
        let own = chosen.map { typical > 0 && $0.thickness > limit ? nil : Optional($0.middle) }
        return rows.indices.map { index in
            let crossing = chosen[index]
            // Inside something bigger: the depth of the nearest sample where the part was on its own.
            let borrowed = own[index] ?? CrossingPath.nearest(own, to: index) ?? crossing.middle
            let depth = min(max(borrowed, crossing.entry), crossing.exit)
            let thickness = typical > 0 ? min(crossing.thickness, limit) : crossing.thickness
            return Sample(point: rows[index].origin + rows[index].direction * depth, thickness: thickness)
        }
    }

    /// The joints a stroke would make, without touching any rig: what the stage shows while the bone is being drawn.
    public static func preview(_ samples: [Sample]) -> [Vec3] {
        guard samples.count >= 2 else { return [] }
        let path = smoothed(samples.map(\.point))
        return joints(along: path, thickness: thickness(of: samples, length: length(of: path)))
    }

    /// For each ray, where it crosses a drawing's plane (a 2D drawn puppet lies on one).
    public static func onPlane(rays: [Ray], origin: Vec3, normal: Vec3) -> [Sample] {
        rays.compactMap { ray in
            GuideSurface.plane(origin: origin, normal: normal).intersect(ray).map { Sample(point: $0.point, thickness: 0) }
        }
    }

    /// The rig with a chain along `samples` added. Joints land at the stroke's ends, where it bends, and between them
    /// so that no bone is much longer than the part is thick (`joints(along:thickness:)`). The end nearer the existing
    /// bones (or, on a first chain, nearer the body) is the chain's base; it hangs from the bone it starts on. A first
    /// chain also gets a root joint in the middle of the rest of the body, so the body holds still while the chain
    /// bends. A stroke drawn along a chain that's already there replaces it (`redrawn`): what hung from the old chain
    /// hangs from the new one. `surface` is every vertex of the object (rig space).
    public static func addingChain(_ samples: [Sample], to rig: ObjectRig?, surface: [Vec3]) throws(Failure) -> ObjectRig {
        guard !samples.isEmpty else { throw .missed }
        let path = smoothed(samples.map(\.point))
        let length = length(of: path)
        let size = (Bounds(points: surface) ?? Bounds(points: path))?.size.length ?? 1
        guard path.count >= 2, length > size * 0.04 else { throw .tooShort }
        let thickness = thickness(of: samples, length: length)
        var points = joints(along: path, thickness: thickness)
        var kept = rig
        var orphans: [Int] = []
        if let rig, rig.standard == .custom {
            let replaced = redrawn(by: path, in: rig, reach: thickness * 0.75)
            if !replaced.isEmpty { (kept, orphans) = rig.removing(only: replaced) }
        }
        var result = kept ?? ObjectRig(skeleton: Skeleton(joints: []))
        let parent: Int?
        if let kept, !kept.skeleton.isEmpty {
            let attached = Set(kept.skeleton.joints.indices).subtracting(kept.descendants(of: orphans))
            let rest = kept.restPositions
            let anchors = kept.segments.filter { attached.contains($0.joint) }
                + attached.sorted().map { BoneSegment(joint: $0, head: rest[$0], tail: rest[$0]) }
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
        let first = result.skeleton.joints.count
        result.append(chain: points, parent: parent)
        if !orphans.isEmpty { result = result.hanging(orphans, from: Array(first ..< result.skeleton.joints.count)) }
        result.skin = nil
        result.points = nil
        result.surface = nil
        return result
    }

    static func length(of path: [Vec3]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// How thick the part is along the stroke (the median); a drawing has no thickness, so a sixth of the stroke.
    static func thickness(of samples: [Sample], length: Double) -> Double {
        let thick = samples.map(\.thickness).filter { $0 > 0 }.sorted()
        return thick.isEmpty ? length / 6 : thick[thick.count / 2]
    }

    /// Where the joints go along the centreline: its two ends, wherever the stroke bends, and evenly in between. A
    /// stroke with no bend is cut into two to eight bones about 1.4 times as long as the part is thick; one with bends
    /// gets about as many, shared between its stretches by their length (each at least one bone).
    static func joints(along path: [Vec3], thickness: Double) -> [Vec3] {
        let length = length(of: path)
        let bones = min(max(Int((length / max(thickness * 1.4, 1e-9)).rounded()), 2), 8)
        var tolerance = max(thickness * 0.5, length * 0.04)
        var corners = bends(path, tolerance: tolerance)
        while corners.count - 1 > 8 {
            tolerance *= 1.5
            corners = bends(path, tolerance: tolerance)
        }
        guard corners.count > 2 else { return resample(path, count: bones + 1) }
        var result: [Vec3] = []
        for (start, end) in zip(corners, corners.dropFirst()) {
            let stretch = Array(path[start ... end])
            let share = Double(bones) * Self.length(of: stretch) / max(length, 1e-9)
            let cut = resample(stretch, count: max(Int(share.rounded()), 1) + 1)
            result += result.isEmpty ? cut : Array(cut.dropFirst())
        }
        return result
    }

    /// The points where a path bends (Ramer–Douglas–Peucker): the indices kept, ends included, when every other
    /// point lies within `tolerance` of the lines between them.
    static func bends(_ path: [Vec3], tolerance: Double) -> [Int] {
        guard path.count > 2 else { return Array(path.indices) }
        var keep = Set([0, path.count - 1])
        var spans = [(0, path.count - 1)]
        while let (low, high) = spans.popLast() {
            guard high > low + 1 else { continue }
            let chord = BoneSegment(joint: 0, head: path[low], tail: path[high])
            var farthest = low
            var reach = tolerance
            for index in low + 1 ..< high {
                let distance = chord.distance(to: path[index])
                if distance > reach {
                    reach = distance
                    farthest = index
                }
            }
            guard farthest != low else { continue }
            keep.insert(farthest)
            spans.append((low, farthest))
            spans.append((farthest, high))
        }
        return keep.sorted()
    }

    /// The drawn chain a new stroke runs along, so that it's being drawn again: its joints, or none when the stroke
    /// goes somewhere new. A bone lies along the stroke when both its ends are within `reach` of it and it points the
    /// way the stroke does there; the chain is those bones and the unbranched run that carries straight on from them
    /// (a fin standing on a tail isn't the tail), and it counts as redrawn when the stroke covers at least half of it.
    /// The root joint is never part of a chain.
    static func redrawn(by path: [Vec3], in rig: ObjectRig, reach: Double) -> Set<Int> {
        let joints = rig.skeleton.joints
        let rest = rig.restPositions
        let stroke = zip(path, path.dropFirst()).map { BoneSegment(joint: 0, head: $0, tail: $1) }
        func nearest(_ point: Vec3) -> (distance: Double, direction: Vec3)? {
            stroke.map { (distance: $0.distance(to: point), direction: ($0.tail - $0.head).normalized) }.min { $0.distance < $1.distance }
        }
        func isRoot(_ index: Int) -> Bool { joints[index].parent == nil && joints[index].name == "root" }
        var along = Set<Int>()
        for index in joints.indices {
            guard let parent = joints[index].parent, !isRoot(parent),
                  let head = nearest(rest[parent]), let tail = nearest(rest[index]), head.distance < reach, tail.distance < reach else { continue }
            let bone = (rest[index] - rest[parent]).normalized
            if abs(bone.dot(tail.direction)) > 0.7 { along.formUnion([parent, index]) }
        }
        guard !along.isEmpty else { return [] }
        // The unbranched run that carries straight on from those bones, up and down the skeleton.
        func bone(_ index: Int) -> Vec3? {
            joints[index].parent.flatMap { isRoot($0) ? nil : (rest[index] - rest[$0]).normalized }
        }
        func carriesOn(_ lower: Int, from upper: Int) -> Bool {
            guard rig.skeleton.children(of: upper) == [lower], let ahead = bone(lower) else { return false }
            return bone(upper).map { $0.dot(ahead) > 0.5 } ?? true
        }
        var chain = along
        var grew = true
        while grew {
            grew = false
            for index in joints.indices where !chain.contains(index) && !isRoot(index) {
                let below = joints[index].parent.map { chain.contains($0) && carriesOn(index, from: $0) } ?? false
                let above = rig.skeleton.children(of: index).first.map { chain.contains($0) && carriesOn($0, from: index) } ?? false
                if below || above {
                    chain.insert(index)
                    grew = true
                }
            }
        }
        return along.count * 2 >= chain.count ? chain : []
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

    /// The rig without `gone`, and nothing else: joints that hung from them are left without a parent, and are told
    /// apart from the rig's own top joints by `orphans` (their indices in the new rig).
    func removing(only gone: Set<Int>) -> (rig: ObjectRig, orphans: [Int]) {
        let rest = restPositions
        let kept = skeleton.joints.indices.filter { !gone.contains($0) }
        let remap = Dictionary(uniqueKeysWithValues: kept.enumerated().map { ($1, $0) })
        var orphans: [Int] = []
        var parents: [Int?] = []
        for (index, old) in kept.enumerated() {
            let parent = skeleton.joints[old].parent
            if let parent, gone.contains(parent) { orphans.append(index) }
            parents.append(parent.flatMap { remap[$0] })
        }
        let names = kept.map { skeleton.joints[$0].name }
        let rig = ObjectRig(names: names, parents: parents, positions: kept.map { rest[$0] }, standard: standard,
                            tips: tips.filter { names.contains($0.key) })
        return (rig, orphans)
    }

    /// `joints` and everything hanging from them.
    func descendants(of joints: [Int]) -> Set<Int> {
        var result = Set(joints)
        var grew = !result.isEmpty
        while grew {
            grew = false
            for index in skeleton.joints.indices where !result.contains(index) && skeleton.joints[index].parent.map(result.contains) == true {
                result.insert(index)
                grew = true
            }
        }
        return result
    }

    /// The rig with each of `orphans` hung from the nearest of `candidates`, its joints back in parents-first order
    /// (every joint keeps its name and its place).
    func hanging(_ orphans: [Int], from candidates: [Int]) -> ObjectRig {
        let rest = restPositions
        var parents = skeleton.joints.map(\.parent)
        for orphan in orphans {
            parents[orphan] = candidates.min { rest[$0].distance(to: rest[orphan]) < rest[$1].distance(to: rest[orphan]) }
        }
        var order: [Int] = []
        var placed = Set<Int>()
        while order.count < parents.count {
            let ready = parents.indices.filter { !placed.contains($0) && (parents[$0].map(placed.contains) ?? true) }
            guard !ready.isEmpty else { return self }
            order += ready
            placed.formUnion(ready)
        }
        let remap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return ObjectRig(names: order.map { skeleton.joints[$0].name }, parents: order.map { parents[$0].flatMap { remap[$0] } },
                         positions: order.map { rest[$0] }, standard: standard, tips: tips)
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
