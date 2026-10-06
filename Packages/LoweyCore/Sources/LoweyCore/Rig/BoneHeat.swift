import Foundation

/// Automatic skin weights by bone heat (Baran & Popović, "Automatic Rigging and Animation of 3D Characters", 2007):
/// each bone heats the surface where it is the nearest bone that can be seen, the heat diffuses over the surface, and
/// a vertex's weights are how warm each bone left it. Weights fall off smoothly across joints and never jump between
/// parts that only happen to be close in space.
///
/// For every joint j: (L + A·H) w_j = A·H·p_j, with L the surface's cotangent Laplacian, A each vertex's area, H = 1/d²
/// (d: the distance to the nearest visible bone) and p_j = 1 where that bone is j's. The matrix is symmetric positive
/// definite; each joint is one preconditioned conjugate-gradient solve.
public enum BoneHeat {
    /// A surface to weight: positions, and triangles or plain edges (a drawing's strokes are chains of points).
    public struct Surface: Sendable {
        public var positions: [Vec3]
        public var triangles: [UInt32]
        public var edges: [(Int, Int)]

        public init(positions: [Vec3], triangles: [UInt32] = [], edges: [(Int, Int)] = []) {
            self.positions = positions
            self.triangles = triangles
            self.edges = edges
        }

        public init(_ mesh: MeshData) {
            self.init(positions: mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }, triangles: mesh.indices)
        }
    }

    /// Weights for every vertex of `surface` (in its order) from the rig's bones. `visibility` tells whether a bone point
    /// can be seen from a surface point (nil: every bone can).
    public static func weights(_ surface: Surface, segments: [BoneSegment], jointCount: Int,
                               visibility: TriangleBVH? = nil) -> SkinWeights {
        guard !surface.positions.isEmpty, !segments.isEmpty else { return SkinWeights() }
        let welded = Weld(surface.positions)
        let system = System(welded: welded, surface: surface)
        let heat = Heat(points: welded.points, segments: segments, visibility: visibility, scale: welded.scale)
        // One solve per joint that is the nearest bone somewhere.
        var columns: [Int: [Double]] = [:]
        for joint in Set(heat.nearest.flatMap { $0.map(\.joint) }) where joint < jointCount {
            var rhs = [Double](repeating: 0, count: welded.points.count)
            var guess = rhs
            for index in rhs.indices {
                let share = heat.nearest[index].filter { $0.joint == joint }.reduce(0) { $0 + $1.share }
                rhs[index] = system.area[index] * heat.heat[index] * share
                guess[index] = share
            }
            columns[joint] = system.solve(rhs: rhs, diagonal: heat.heat, guess: guess)
        }
        var joints: [SIMD4<UInt16>] = []
        var weights: [SIMD4<Float>] = []
        joints.reserveCapacity(surface.positions.count)
        weights.reserveCapacity(surface.positions.count)
        for original in surface.positions.indices {
            let point = welded.map[original]
            let pairs = columns.map { (joint: $0.key, weight: max($0.value[point], 0)) }
            var (j, w) = SkinWeights.influence(pairs)
            if pairs.allSatisfy({ $0.weight <= 1e-4 }), let near = heat.nearest[point].first {
                (j, w) = SkinWeights.influence([(near.joint, 1)])
            }
            joints.append(j)
            weights.append(w)
        }
        return SkinWeights(joints: joints, weights: weights)
    }

    /// Vertices at the same place become one point (models split vertices along seams; the heat must cross them).
    struct Weld {
        var points: [Vec3] = []
        var map: [Int] = []
        var scale: Double

        init(_ positions: [Vec3]) {
            let bounds = Bounds(points: positions) ?? Bounds(min: .zero, max: .one)
            scale = max(bounds.size.length, 1e-6)
            let step = scale * 1e-6
            var lookup: [SIMD3<Int64>: Int] = [:]
            map.reserveCapacity(positions.count)
            for position in positions {
                let key = SIMD3<Int64>(Int64((position.x / step).rounded()), Int64((position.y / step).rounded()),
                                       Int64((position.z / step).rounded()))
                if let index = lookup[key] {
                    map.append(index)
                } else {
                    lookup[key] = points.count
                    map.append(points.count)
                    points.append(position)
                }
            }
        }
    }

    /// Where each point's heat comes from: its nearest visible bones (ties share) and H = 1/d².
    struct Heat {
        var heat: [Double]
        var nearest: [[(joint: Int, share: Double)]]

        init(points: [Vec3], segments: [BoneSegment], visibility: TriangleBVH?, scale: Double) {
            heat = []
            nearest = []
            heat.reserveCapacity(points.count)
            nearest.reserveCapacity(points.count)
            let floor = scale * 1e-3
            let margin = scale * 1e-4
            for point in points {
                let candidates = segments.map { segment in
                    let closest = segment.closest(to: point)
                    return (joint: segment.joint, closest: closest, distance: closest.distance(to: point))
                }.sorted { $0.distance < $1.distance }
                // The nearest bone that can be seen (the nearest of all when none can), and any as near as it.
                func visible(_ index: Int) -> Bool {
                    visibility.map { !$0.blocks(point, candidates[index].closest, margin: margin) } ?? true
                }
                let first = candidates.indices.first(where: visible) ?? 0
                let best = max(candidates[first].distance, floor)
                var ties = [candidates[first].joint]
                for index in candidates.indices where index > first && candidates[index].distance <= best * 1.0001 + 1e-12 && visible(index) {
                    ties.append(candidates[index].joint)
                }
                heat.append(1 / (best * best))
                nearest.append(ties.map { ($0, 1 / Double(ties.count)) })
            }
        }
    }

    /// The Laplacian (compressed rows, the diagonal apart) and each point's area.
    struct System {
        var rowStart: [Int]
        var columns: [Int]
        var values: [Double]
        var laplaceDiagonal: [Double]
        var area: [Double]

        init(welded: Weld, surface: Surface) {
            let count = welded.points.count
            var pairs: [Int: [Int: Double]] = [:]
            var area = [Double](repeating: 0, count: count)
            func add(_ a: Int, _ b: Int, _ weight: Double) {
                guard a != b else { return }
                pairs[min(a, b), default: [:]][max(a, b), default: 0] += weight
            }
            let points = welded.points
            for tri in stride(from: 0, to: surface.triangles.count - 2, by: 3) {
                let corners = [Int(surface.triangles[tri]), Int(surface.triangles[tri + 1]), Int(surface.triangles[tri + 2])]
                    .map { welded.map[$0] }
                let (a, b, c) = (points[corners[0]], points[corners[1]], points[corners[2]])
                let doubled = (b - a).cross(c - a).length
                guard doubled > 1e-18 else { continue }
                for corner in corners {
                    area[corner] += doubled / 6
                }
                // The cotangent of each corner weighs the edge across from it (clamped: thin triangles don't explode).
                for (k, (i, j)) in [(0, (1, 2)), (1, (2, 0)), (2, (0, 1))] {
                    let p = points[corners[k]]
                    let u = points[corners[i]] - p
                    let v = points[corners[j]] - p
                    let cot = u.dot(v) / max(u.cross(v).length, 1e-18)
                    add(corners[i], corners[j], min(max(cot / 2, 1e-3), 5))
                }
            }
            // Plain edges (strokes): unit weights, each point owning the square of its neighbours' spacing.
            for (a, b) in surface.edges {
                let i = welded.map[a]
                let j = welded.map[b]
                add(i, j, 1)
                let length = points[i].distance(to: points[j])
                area[i] += length * length / 2
                area[j] += length * length / 2
            }
            let floor = welded.scale * welded.scale * 1e-10
            self.area = area.map { max($0, floor) }
            var rowStart = [0]
            var columns: [Int] = []
            var values: [Double] = []
            var diagonal = [Double](repeating: 0, count: count)
            var neighbours = [[(Int, Double)]](repeating: [], count: count)
            for (a, row) in pairs {
                for (b, weight) in row {
                    neighbours[a].append((b, weight))
                    neighbours[b].append((a, weight))
                    diagonal[a] += weight
                    diagonal[b] += weight
                }
            }
            for row in neighbours {
                for (column, weight) in row.sorted(by: { $0.0 < $1.0 }) {
                    columns.append(column)
                    values.append(-weight)
                }
                rowStart.append(columns.count)
            }
            self.rowStart = rowStart
            self.columns = columns
            self.values = values
            laplaceDiagonal = diagonal
        }

        /// Solves (L + A·H) x = rhs by conjugate gradients with a Jacobi preconditioner.
        func solve(rhs: [Double], diagonal heat: [Double], guess: [Double]) -> [Double] {
            let count = rhs.count
            let diagonal = (0 ..< count).map { laplaceDiagonal[$0] + area[$0] * heat[$0] }
            func multiply(_ x: [Double]) -> [Double] {
                var result = [Double](repeating: 0, count: count)
                for row in 0 ..< count {
                    var sum = diagonal[row] * x[row]
                    for entry in rowStart[row] ..< rowStart[row + 1] {
                        sum += values[entry] * x[columns[entry]]
                    }
                    result[row] = sum
                }
                return result
            }
            var x = guess
            var residual = zip(rhs, multiply(x)).map { $0 - $1 }
            var z = zip(residual, diagonal).map { $0 / $1 }
            var direction = z
            var rz = zip(residual, z).reduce(0) { $0 + $1.0 * $1.1 }
            let target = max(rhs.reduce(0) { $0 + $1 * $1 }, 1e-30) * 1e-12
            for _ in 0 ..< 600 {
                if zip(residual, residual).reduce(0, { $0 + $1.0 * $1.1 }) <= target { break }
                let product = multiply(direction)
                let curvature = zip(direction, product).reduce(0) { $0 + $1.0 * $1.1 }
                guard curvature > 0 else { break }
                let step = rz / curvature
                for index in 0 ..< count {
                    x[index] += step * direction[index]
                    residual[index] -= step * product[index]
                }
                z = zip(residual, diagonal).map { $0 / $1 }
                let next = zip(residual, z).reduce(0) { $0 + $1.0 * $1.1 }
                let beta = next / max(rz, 1e-300)
                rz = next
                for index in 0 ..< count {
                    direction[index] = z[index] + beta * direction[index]
                }
            }
            return x
        }
    }
}
