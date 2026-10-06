import Foundation

/// Making and changing an object's rig. Each returns the rig to store (with `setRig`) and the files to write first.
public enum RigOperations {
    public typealias Files = [String: Data]

    /// The surface the rig bends, for weights: a solid's mesh, or a drawing's stroke points chained along each stroke
    /// (and to points of other strokes that touch them, so a drawn figure holds together).
    public static func surface(of object: SceneObject, mesh: MeshData?) -> BoneHeat.Surface? {
        if case let .drawing(recipe) = object.kind {
            return drawingSurface(recipe)
        }
        guard let mesh, !mesh.isEmpty else { return nil }
        return BoneHeat.Surface(mesh)
    }

    static func drawingSurface(_ recipe: DrawingRecipe) -> BoneHeat.Surface? {
        let points = recipe.strokes.flatMap(\.points)
        guard !points.isEmpty else { return nil }
        var edges: [(Int, Int)] = []
        var offset = 0
        var spacing: [Double] = []
        for stroke in recipe.strokes {
            for index in 0 ..< max(stroke.points.count - 1, 0) {
                edges.append((offset + index, offset + index + 1))
                spacing.append(stroke.points[index].distance(to: stroke.points[index + 1]))
            }
            offset += stroke.points.count
        }
        let step = spacing.isEmpty ? 0.01 : spacing.sorted()[spacing.count / 2]
        // Strokes that touch: each point joins the nearest point of every other stroke within a step and a half.
        var starts: [Int] = []
        var total = 0
        for stroke in recipe.strokes {
            starts.append(total)
            total += stroke.points.count
        }
        let grid = PointGrid(points, cell: max(step * 1.5, 1e-6))
        func stroke(of index: Int) -> Int { (starts.lastIndex { $0 <= index }) ?? 0 }
        for index in points.indices {
            let own = stroke(of: index)
            var best: [Int: (Int, Double)] = [:]
            for other in grid.near(points[index]) where stroke(of: other) != own {
                let distance = points[index].distance(to: points[other])
                guard distance <= step * 1.5 else { continue }
                if distance < best[stroke(of: other)]?.1 ?? .infinity { best[stroke(of: other)] = (other, distance) }
            }
            for (_, match) in best where match.0 > index {
                edges.append((index, match.0))
            }
        }
        return BoneHeat.Surface(positions: points, edges: edges)
    }

    /// The plane a drawing lies on (its centre and the guide plane's normal), where drawn bones land.
    public static func drawingPlane(_ recipe: DrawingRecipe) -> (origin: Vec3, normal: Vec3) {
        let points = recipe.strokes.flatMap(\.points)
        let centre = points.isEmpty ? .zero : points.reduce(Vec3.zero, +) / Double(points.count)
        return (centre, recipe.normal.length > 1e-9 ? recipe.normal.normalized : .unitZ)
    }

    /// The rig with its weights computed for the object (bone heat). Solids get a `.skin` file; drawings keep theirs
    /// inline.
    public static func weighted(_ rig: ObjectRig, object: SceneObject, mesh: MeshData?) -> (rig: ObjectRig, files: Files)? {
        guard let surface = surface(of: object, mesh: mesh) else { return nil }
        let isDrawing = if case .drawing = object.kind {
            true
        } else {
            false
        }
        let visibility = isDrawing ? nil : mesh.map(TriangleBVH.init)
        let weights = BoneHeat.weights(surface, segments: rig.segments, jointCount: rig.skeleton.joints.count, visibility: visibility)
        return stored(weights, in: rig, object: object, mesh: mesh)
    }

    /// The rig holding these weights (a drawing inline, a solid as a file), stamped with the surface they fit.
    public static func stored(_ weights: SkinWeights, in rig: ObjectRig, object: SceneObject, mesh: MeshData?) -> (rig: ObjectRig, files: Files) {
        var result = rig
        if case let .drawing(recipe) = object.kind {
            result.points = weights
            result.skin = nil
            result.surface = fingerprint(recipe)
            return (result, [:])
        }
        let data = weights.data
        let name = RigFiles.skinName(for: data)
        result.skin = name
        result.points = nil
        result.surface = mesh.map(PaintMesh.fingerprint)
        return (result, [name: data])
    }

    /// The fingerprint of a drawing's points, so changed strokes are noticed.
    public static func fingerprint(_ recipe: DrawingRecipe) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for point in recipe.strokes.flatMap(\.points) {
            for value in [point.x, point.y, point.z] {
                hash = (hash ^ value.bitPattern) &* 0x0000_0100_0000_01B3
            }
        }
        return BrushKey.hex(hash)
    }

    /// Whether the rig's weights still fit the object (its shape or strokes may have changed since).
    public static func fits(_ rig: ObjectRig, object: SceneObject, mesh: MeshData?) -> Bool {
        if case let .drawing(recipe) = object.kind { return rig.surface == fingerprint(recipe) }
        return mesh.map { rig.surface == PaintMesh.fingerprint($0) } ?? false
    }
}

/// Painting weights by hand: the brush adds weight for one joint (or takes it away) where it passes; the vertex's other
/// joints share what's left as they did.
public enum WeightPaint {
    /// A dab of the brush on the surface: rig-space centre, radius, and how much it gives (0…1, after pressure and flow).
    public struct Dab: Hashable, Sendable {
        public var centre: Vec3
        public var radius: Double
        public var amount: Double

        public init(centre: Vec3, radius: Double, amount: Double) {
            self.centre = centre
            self.radius = radius
            self.amount = amount
        }
    }

    public static func apply(_ dabs: [Dab], joint: Int, erase: Bool, to weights: SkinWeights, positions: [Vec3]) -> SkinWeights {
        guard weights.count == positions.count, !dabs.isEmpty else { return weights }
        var result = weights
        let grid = PointGrid(positions, cell: max(dabs.map(\.radius).max() ?? 0.01, 1e-6))
        var touched: [Int: Double] = [:]
        for dab in dabs {
            for index in grid.near(dab.centre) {
                let distance = positions[index].distance(to: dab.centre)
                guard distance < dab.radius else { continue }
                let falloff = 1 - (distance / dab.radius) * (distance / dab.radius)
                touched[index, default: 0] = min(touched[index, default: 0] + dab.amount * falloff, 1)
            }
        }
        for (index, amount) in touched {
            var pairs: [Int: Double] = [:]
            for slot in 0 ..< 4 where weights.weights[index][slot] > 0 {
                pairs[Int(weights.joints[index][slot]), default: 0] += Double(weights.weights[index][slot])
            }
            let own = pairs[joint] ?? 0
            let target = erase ? own * (1 - amount) : own + (1 - own) * amount
            let others = 1 - own
            var updated: [(joint: Int, weight: Double)] = [(joint, target)]
            for (other, weight) in pairs where other != joint {
                // The rest share 1 - target in the proportions they had (erasing hands the weight to them).
                updated.append((other, others > 1e-9 ? weight / others * (1 - target) : 0))
            }
            if erase, pairs.count == 1 { continue }
            let (j, w) = SkinWeights.influence(updated)
            result.joints[index] = j
            result.weights[index] = w
        }
        return result
    }
}

/// Points bucketed in a uniform grid, for "which points are near here".
struct PointGrid {
    let cell: Double
    var buckets: [SIMD3<Int64>: [Int]] = [:]

    init(_ points: [Vec3], cell: Double) {
        self.cell = cell
        for (index, point) in points.enumerated() {
            buckets[key(point), default: []].append(index)
        }
    }

    func key(_ point: Vec3) -> SIMD3<Int64> {
        SIMD3<Int64>(Int64((point.x / cell).rounded(.down)), Int64((point.y / cell).rounded(.down)), Int64((point.z / cell).rounded(.down)))
    }

    /// Points in the cells around `point` (within one cell's size, and some a little further).
    func near(_ point: Vec3) -> [Int] {
        let centre = key(point)
        var result: [Int] = []
        for x in -1 ... 1 {
            for y in -1 ... 1 {
                for z in -1 ... 1 {
                    result += buckets[centre &+ SIMD3<Int64>(Int64(x), Int64(y), Int64(z))] ?? []
                }
            }
        }
        return result
    }
}
