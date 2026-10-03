import Foundation

/// Which labelled things really pass through each other. Boxes alone would call a chair tucked under a desk an
/// intersection, so where two boxes overlap by more than a couple of centimetres the surfaces themselves are sampled
/// into 4 cm cells: surfaces that cross share cells; things that merely rest on each other don't overlap that deep.
struct ContactCheck {
    var scene: Scene
    var library: LibraryManifest
    var units: [ObjectID]
    var triangles: [[Vec3]]
    var cell = 0.04
    /// Overlap (metres, on every axis) before surfaces are compared.
    var depth = 0.025

    func intersecting(_ index: Int) -> [Int] {
        guard let box = Bounds(points: triangles[index]) else { return [] }
        return units.indices.filter { other in
            guard other != index, let otherBox = Bounds(points: triangles[other]), !related(units[index], units[other]) else { return false }
            guard let overlap = Self.overlap(box, otherBox), overlap.size.x > depth, overlap.size.y > depth, overlap.size.z > depth else {
                return false
            }
            if isResting(index, on: other, overlap: overlap) || isResting(other, on: index, overlap: overlap) { return false }
            let shared = cells(triangles[index], in: overlap).intersection(cells(triangles[other], in: overlap))
            return shared.count >= 3
        }
    }

    func related(_ a: ObjectID, _ b: ObjectID) -> Bool {
        scene.isAncestor(a, of: b) || scene.isAncestor(b, of: a)
    }

    /// `index` stands on one of `other`'s Kit surfaces (a book on a shelf inside a bookcase's box).
    func isResting(_ index: Int, on other: Int, overlap _: Bounds) -> Bool {
        guard let box = Bounds(points: triangles[index]), let kit = scene.objects[units[other]]?.kind.assetID.flatMap({ library.asset($0)?.kit }),
              !kit.surfaces.isEmpty else { return false }
        let world = scene.worldTransform(of: units[other])
        return kit.surfaces.contains { surface in abs(world.apply(to: surface.center).y - box.min.y) < 0.03 }
    }

    static func overlap(_ a: Bounds, _ b: Bounds) -> Bounds? {
        let low = Vec3.max(a.min, b.min)
        let high = Vec3.min(a.max, b.max)
        guard high.x > low.x, high.y > low.y, high.z > low.z else { return nil }
        return Bounds(min: low, max: high)
    }

    struct Cell: Hashable {
        var x: Int
        var y: Int
        var z: Int
    }

    /// Cells touched by the surface inside `region` (its bottom 2 cm left out: that's where things rest).
    func cells(_ triangles: [Vec3], in region: Bounds) -> Set<Cell> {
        let inner = Bounds(min: region.min + Vec3(0, 0.02, 0), max: region.max)
        var result = Set<Cell>()
        var index = 0
        while index + 2 < triangles.count {
            let a = triangles[index]
            let b = triangles[index + 1]
            let c = triangles[index + 2]
            index += 3
            guard let box = Bounds(points: [a, b, c]), Self.overlap(box.expanded(cell), inner) != nil else { continue }
            let area = (b - a).cross(c - a).length / 2
            let steps = min(max(Int((area.squareRoot() / (cell * 0.5)).rounded(.up)), 1), 40)
            for i in 0 ... steps {
                for j in 0 ... steps - i {
                    let u = Double(i) / Double(steps)
                    let v = Double(j) / Double(steps)
                    let point = a + (b - a) * u + (c - a) * v
                    guard inner.contains(point) else { continue }
                    result.insert(Cell(x: Int((point.x / cell).rounded(.down)), y: Int((point.y / cell).rounded(.down)),
                                       z: Int((point.z / cell).rounded(.down))))
                }
            }
        }
        return result
    }
}

extension Bounds {
    func expanded(_ amount: Double) -> Bounds {
        Bounds(min: min - Vec3(amount, amount, amount), max: max + Vec3(amount, amount, amount))
    }
}
