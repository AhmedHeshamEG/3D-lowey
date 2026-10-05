import Foundation

/// Rooms and buildings from a few taps: walls along a path, openings cut through them, floor slabs and stairs. Each
/// makes an editable mesh, so everything else in Model (push/pull, booleans, bevels) works on it afterwards.
public enum Architecture {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case tooShort
        case notAWall

        public var description: String {
            switch self {
            case .tooShort: "Tap at least two points for a wall."
            case .notAWall: "Openings go into walls: tap the side of a wall."
            }
        }
    }

    /// Wall defaults: a storey's height and an inside wall's thickness.
    public static let wallHeight = 2.7
    public static let wallThickness = 0.2

    /// Walls along a path on the ground (or a floor): `thickness` wide, centred on the path, `height` tall. Corners
    /// are mitred so the walls join into one solid; a closed path makes a ring of walls (a room).
    public static func walls(along path: [Vec3], closed: Bool, height: Double = wallHeight,
                             thickness: Double = wallThickness) throws(Failure) -> EditableMesh {
        var points = path
        if closed, points.count > 2, let first = points.first, let last = points.last, first.distance(to: last) < 1e-9 { points.removeLast() }
        guard points.count >= 2, zip(points, points.dropFirst()).allSatisfy({ $0.distance(to: $1) > 1e-6 }) else { throw .tooShort }
        let base = points[0].y
        let flat = points.map { Vec2($0.x, $0.z) }
        let half = thickness / 2
        let left = offset(flat, by: half, closed: closed), right = offset(flat, by: -half, closed: closed)
        func lift(_ loop: [Vec2]) -> [Vec3] { loop.map { Vec3($0.x, base, $0.y) } }
        if closed {
            // A ring: the outer side is the outline, the inner side its hole.
            var outer = lift(left), inner = lift(right)
            if area(outer) < area(inner) { swap(&outer, &inner) }
            return Prism.make(outline: upward(outer), holes: [downward(inner)], normal: .unitY, from: 0, to: height)
        }
        let outline = lift(left) + lift(right).reversed()
        return Prism.make(outline: upward(outline), holes: [], normal: .unitY, from: 0, to: height)
    }

    /// A polyline moved sideways (positive to the left of its direction, seen from above) with mitred corners; very
    /// sharp corners are capped at four times the distance so they don't spike.
    static func offset(_ points: [Vec2], by distance: Double, closed: Bool) -> [Vec2] {
        let count = points.count
        func normal(_ index: Int) -> Vec2 {
            let a = points[index], b = points[(index + 1) % count]
            let d = b - a
            let length = max(d.length, 1e-12)
            // Left of the direction, seen from above (+y up, x right, z toward you): (dz, -dx) in (x, z).
            return Vec2(d.y / length, -d.x / length)
        }
        return (0 ..< count).map { index in
            let hasPrevious = closed || index > 0, hasNext = closed || index < count - 1
            if !hasPrevious { return points[index] + normal(index) * distance }
            if !hasNext { return points[index] + normal(index - 1) * distance }
            let incoming = normal((index + count - 1) % count), outgoing = normal(index % count)
            let bend = 1 + incoming.x * outgoing.x + incoming.y * outgoing.y
            let mitre = (incoming + outgoing) * (distance / max(bend, 1e-9))
            let limit = abs(distance) * 4
            return points[index] + (mitre.length > limit ? mitre * (limit / mitre.length) : mitre)
        }
    }

    static func area(_ loop: [Vec3]) -> Double {
        abs(EditableMesh.newellVector(loop).y)
    }

    /// The loop counter-clockwise seen from above (what a prism's outline wants).
    static func upward(_ loop: [Vec3]) -> [Vec3] {
        EditableMesh.newellVector(loop).y >= 0 ? loop : loop.reversed()
    }

    /// Clockwise seen from above (a prism's hole).
    static func downward(_ loop: [Vec3]) -> [Vec3] {
        EditableMesh.newellVector(loop).y <= 0 ? loop : loop.reversed()
    }

    // MARK: Openings

    public enum Opening: String, Codable, Sendable, CaseIterable {
        case door, window

        public var label: String { self == .door ? "Door" : "Window" }

        /// Width, height and the height of its bottom above the wall's base (metres).
        public var size: (width: Double, height: Double, sill: Double) {
            switch self {
            case .door: (0.9, 2.1, 0)
            case .window: (1.2, 1.2, 0.9)
            }
        }
    }

    /// The block an opening cuts out of a wall: centred where the side of the wall was tapped, square to the wall,
    /// reaching through it (and a little past on both sides), its bottom `sill` above the wall's base.
    public static func openingBlock(at point: Vec3, facing normal: Vec3, wallBase: Double, wallDepth: Double, width: Double,
                                    height: Double, sill: Double) throws(Failure) -> EditableMesh {
        let out = Vec3(normal.x, 0, normal.z)
        guard out.length > 0.5 else { throw .notAWall }
        let n = out.normalized
        let along = Vec3.unitY.cross(n).normalized
        let reach = wallDepth + 0.1
        let centre = Vec3(point.x, wallBase + sill, point.z) - n * (wallDepth / 2)
        let outline = [
            centre - along * (width / 2) - n * reach, centre + along * (width / 2) - n * reach,
            centre + along * (width / 2) + n * reach, centre - along * (width / 2) + n * reach
        ]
        return Prism.make(outline: upward(outline), holes: [], normal: .unitY, from: 0, to: height)
    }

    // MARK: Slabs and stairs

    /// A floor slab under a closed outline: its top at the outline's height, `thickness` deep.
    public static func slab(outline: [Vec3], thickness: Double = 0.2) throws(Failure) -> EditableMesh {
        guard outline.count >= 3, area(outline) > 1e-9 else { throw .tooShort }
        let top = outline[0].y
        let flat = outline.map { Vec3($0.x, top, $0.z) }
        return Prism.make(outline: upward(flat), holes: [], normal: .unitY, from: -thickness, to: 0)
    }

    /// Comfortable stairs: steps about 17.5 cm high and 28 cm deep, filled underneath.
    public struct Stairs: Hashable, Sendable {
        public var rise: Double
        public var width: Double
        public var stepHeight: Double
        public var stepDepth: Double

        public init(rise: Double = 2.8, width: Double = 1.0, stepHeight: Double = 0.175, stepDepth: Double = 0.28) {
            self.rise = rise
            self.width = width
            self.stepHeight = stepHeight
            self.stepDepth = stepDepth
        }

        /// Steps needed to reach the rise, each as close to `stepHeight` as whole steps allow.
        public var steps: Int { max(1, Int((rise / stepHeight).rounded())) }
        public var run: Double { Double(steps) * stepDepth }
    }

    /// Stairs climbing from `start` along `direction` (on the ground), the side profile swept across the width.
    public static func stairs(_ stairs: Stairs, from start: Vec3, direction: Vec3) -> EditableMesh {
        let forward = Vec3(direction.x, 0, direction.z).length > 1e-9 ? Vec3(direction.x, 0, direction.z).normalized : Vec3(0, 0, -1)
        let side = forward.cross(.unitY).normalized
        let step = stairs.rise / Double(stairs.steps)
        var profile: [Vec3] = [start]
        for index in 0 ..< stairs.steps {
            let along = forward * (Double(index) * stairs.stepDepth)
            profile.append(start + along + Vec3(0, Double(index + 1) * step, 0))
            profile.append(start + along + forward * stairs.stepDepth + Vec3(0, Double(index + 1) * step, 0))
        }
        profile.append(start + forward * stairs.run)
        let origin = start - side * (stairs.width / 2)
        let shifted = profile.map { $0 - side * (stairs.width / 2) }
        let frame = PlaneFrame(normal: side, origin: origin)
        let counterClockwise = PolygonTriangulator.signedArea(shifted.map { frame.project($0) }) > 0
        return Prism.make(outline: counterClockwise ? shifted : shifted.reversed(), holes: [], normal: side, from: 0, to: stairs.width)
    }
}

public extension ModelingOperations {
    /// New walls along a path (one object, its pivot under the first corner).
    static func addWalls(along path: [Vec3], closed: Bool, height: Double, thickness: Double, id: ObjectID) throws(Architecture.Failure) -> EditCommand {
        let mesh = try Architecture.walls(along: path, closed: closed, height: height, thickness: thickness)
        var object = newSolid(mesh, id: id)
        object.name = "Walls"
        return .batch("Walls", [.insert(SceneFragment(object: object), parent: nil, index: nil)])
    }

    /// Cuts a door or a window through a wall where its side was tapped.
    static func cutOpening(_ opening: Architecture.Opening, in id: ObjectID, at point: Vec3, facing normal: Vec3,
                           in scene: Scene) throws(Failure) -> EditCommand {
        guard let object = scene.objects[id], let local = editableMesh(of: object) else { throw .notEditable }
        let world = scene.worldTransform(of: id)
        let solid = local.transformed(by: world)
        let bounds = solid.bounds ?? Bounds(min: .zero, max: .zero)
        let depth = wallDepth(of: solid, at: point, facing: normal) ?? Architecture.wallThickness
        let size = opening.size
        let block: EditableMesh
        do throws(Architecture.Failure) {
            block = try Architecture.openingBlock(at: point, facing: normal, wallBase: bounds.min.y, wallDepth: depth, width: size.width,
                                                  height: size.height, sill: size.sill)
        } catch {
            throw .shape(.architecture(error))
        }
        do throws(MeshBoolean.Failure) {
            let cut = try MeshBoolean.combine(solid, block, .subtract)
            return .batch(opening.label, [.setKind(id, .mesh(cut.untransformed(by: world)))])
        } catch {
            throw .boolean(error)
        }
    }

    /// How thick the wall is behind a point on its side (straight through it).
    internal static func wallDepth(of solid: EditableMesh, at point: Vec3, facing normal: Vec3) -> Double? {
        let inward = -Vec3(normal.x, 0, normal.z).normalized
        let triangles = solid.triangulated().triangles.map { (solid.vertices[$0.0], solid.vertices[$0.1], solid.vertices[$0.2]) }
        let start = point + inward * 1e-6
        let hits = triangles.compactMap { PrintCheck.intersect(Ray(origin: start, direction: inward), $0) }
        return hits.min().map { $0 + 1e-6 }
    }

    static func addSlab(outline: [Vec3], thickness: Double, id: ObjectID) throws(Architecture.Failure) -> EditCommand {
        var object = try newSolid(Architecture.slab(outline: outline, thickness: thickness), id: id)
        object.name = "Floor"
        return .batch("Floor", [.insert(SceneFragment(object: object), parent: nil, index: nil)])
    }

    static func addStairs(_ stairs: Architecture.Stairs, from start: Vec3, direction: Vec3, id: ObjectID) -> EditCommand {
        var object = newSolid(Architecture.stairs(stairs, from: start, direction: direction), id: id)
        object.name = "Stairs"
        return .batch("Stairs", [.insert(SceneFragment(object: object), parent: nil, index: nil)])
    }
}
