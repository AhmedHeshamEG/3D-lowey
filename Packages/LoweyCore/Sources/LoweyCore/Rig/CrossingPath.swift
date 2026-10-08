import Foundation

/// Which part of the object a bone stroke runs through. Every Pencil sample is a ray into the object, and a ray can
/// pass through several parts on its way (an arm, then the body behind it). The stroke should stay inside one of them,
/// so the choice is made for the whole stroke at once: the sequence of crossings whose middles make the shortest path
/// in space, with a preference for the part in front (the one the tip is on).
enum CrossingPath {
    /// A stretch of a ray inside the object: where it enters and where it leaves (distances along the ray).
    struct Crossing: Hashable {
        var entry: Double
        var exit: Double

        var middle: Double { (entry + exit) / 2 }
        var thickness: Double { exit - entry }
    }

    /// One ray and its crossings, nearest first.
    struct Row {
        var origin: Vec3
        var direction: Vec3
        var crossings: [Crossing]

        func point(_ crossing: Crossing) -> Vec3 { origin + direction * crossing.middle }
    }

    /// A crossing this many times thicker than the stroke's usual one is the part running into something bigger: the
    /// centreline stays at the part's depth there.
    static let deepest = 2.5

    /// A ray's hits (nearest first) as the stretches it spends inside the object. Models are often several closed
    /// pieces pushed into each other (a tail into a body), so a stretch runs from where the ray first goes in to where
    /// it is out of every piece again. A hit repeated at the same distance (a ray through an edge two triangles share)
    /// counts once. When the faces don't say in and out consistently (an open or inside-out surface), hits pair up in
    /// order instead: in at one, out at the next, and a last hit with no way out is a crossing of no thickness.
    static func crossings(_ hits: [(distance: Double, entering: Bool)]) -> [Crossing] {
        var distinct: [(distance: Double, entering: Bool)] = []
        for hit in hits where !distinct.contains(where: { abs($0.distance - hit.distance) <= 1e-6 && $0.entering == hit.entering }) {
            distinct.append(hit)
        }
        var result: [Crossing] = []
        var inside = 0
        var entry = 0.0
        for hit in distinct {
            if hit.entering {
                if inside == 0 { entry = hit.distance }
                inside += 1
            } else {
                inside -= 1
                if inside < 0 { return paired(distinct.map(\.distance)) }
                if inside == 0 { result.append(Crossing(entry: entry, exit: hit.distance)) }
            }
        }
        return inside == 0 ? result.filter { $0.thickness > 1e-6 } : paired(distinct.map(\.distance))
    }

    private static func paired(_ hits: [Double]) -> [Crossing] {
        var distinct: [Double] = []
        for hit in hits where distinct.last.map({ hit > $0 + 1e-6 }) ?? true {
            distinct.append(hit)
        }
        return stride(from: 0, to: distinct.count, by: 2).map { index in
            Crossing(entry: distinct[index], exit: index + 1 < distinct.count ? distinct[index + 1] : distinct[index])
        }
    }

    /// The value nearest to `index` in a list with gaps.
    static func nearest(_ values: [Double?], to index: Int) -> Double? {
        for offset in 1 ..< max(values.count, 1) {
            if index - offset >= 0, let value = values[index - offset] { return value }
            if index + offset < values.count, let value = values[index + offset] { return value }
        }
        return nil
    }

    /// One crossing per row. The cost of a sequence is the length of the path through its middles, plus a little for
    /// every crossing that isn't the front one (more at the start: the stroke begins on what the tip touches).
    static func continuous(_ rows: [Row]) -> [Crossing] {
        guard let first = rows.first else { return [] }
        guard rows.contains(where: { $0.crossings.count > 1 }) else { return rows.map { $0.crossings[0] } }
        let steps = zip(rows, rows.dropFirst()).map { $0.origin.distance(to: $1.origin) + ($0.direction - $1.direction).length }
        let spacing = max(steps.isEmpty ? 0 : steps.reduce(0, +) / Double(steps.count), 1e-9)
        var costs = first.crossings.indices.map { Double($0) * spacing * 4 }
        var back: [[Int]] = []
        for index in 1 ..< rows.count {
            let row = rows[index]
            let previous = rows[index - 1]
            var next: [Double] = []
            var from: [Int] = []
            for (place, crossing) in row.crossings.enumerated() {
                let point = row.point(crossing)
                var best = 0
                var cost = Double.infinity
                for (before, other) in previous.crossings.enumerated() {
                    let candidate = costs[before] + previous.point(other).distance(to: point)
                    if candidate < cost {
                        cost = candidate
                        best = before
                    }
                }
                next.append(cost + Double(place) * spacing * 0.05)
                from.append(best)
            }
            costs = next
            back.append(from)
        }
        var place = costs.indices.min { costs[$0] < costs[$1] } ?? 0
        var chosen = [rows[rows.count - 1].crossings[place]]
        for index in stride(from: rows.count - 2, through: 0, by: -1) {
            place = back[index][place]
            chosen.append(rows[index].crossings[place])
        }
        return chosen.reversed()
    }
}
