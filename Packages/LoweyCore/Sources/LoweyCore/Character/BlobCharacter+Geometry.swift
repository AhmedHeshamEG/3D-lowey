import Foundation

// MARK: - Geometry helpers

extension BlobCharacter {
    /// Radius of the body drop at a fraction of its height.
    static func dropRadius(at fraction: Double) -> Double {
        let profile = dropProfile()
        let y = fraction * bodyLength
        for index in 1 ..< profile.count where profile[index].y >= y {
            let a = profile[index - 1]
            let b = profile[index]
            let t = (y - a.y) / max(b.y - a.y, 1e-9)
            return a.x + (b.x - a.x) * t
        }
        return 0
    }

    /// A drop: round below its widest ring, tapering to a soft point above.
    static func dropProfile(length: Double = bodyLength, radius: Double = bodyRadius) -> [Vec3] {
        let n = 28
        let widest = 0.36
        return (0 ... n).map { index in
            let t = (1 - cos(.pi * Double(index) / Double(n))) / 2
            let r: Double
            if t <= widest {
                let u = (widest - t) / widest
                r = radius * pow(max(0, 1 - pow(u, 2.2)), 1 / 2.2)
            } else {
                let u = (t - widest) / (1 - widest)
                r = radius * pow(max(0, 1 - pow(u, 1.25)), 0.9)
            }
            return Vec3(r, t * length, 0)
        }
    }

    /// Half an ellipse, bottom to top (a sphere or ellipsoid when turned, centred on the origin).
    static func ellipseProfile(radius: Double, height: Double, n: Int = 14) -> [Vec3] {
        (0 ... n).map { index in
            let angle = -.pi / 2 + .pi * Double(index) / Double(n)
            return Vec3(cos(angle) * radius, sin(angle) * height, 0)
        }
    }

    static func lathe(_ profile: [Vec3], segments: Int) -> DrawingRecipe {
        DrawingRecipe(style: .lathe, strokes: [DrawingRecipe.Stroke(points: profile, widths: [0])], segments: segments)
    }

    /// A flat shape extruded towards +Z (the face's parts; thin enough to hug the head).
    static func slab(_ outline: [Vec2], depth: Double) -> DrawingRecipe {
        slabs([outline], depth: depth)
    }

    /// Several flat shapes in one object.
    static func slabs(_ outlines: [[Vec2]], depth: Double) -> DrawingRecipe {
        DrawingRecipe(style: .extrude, strokes: outlines.map { outline in
            DrawingRecipe.Stroke(points: outline.map { Vec3($0.x, $0.y, 0) }, widths: [0])
        }, normal: .unitZ, depth: depth)
    }

    static func ellipse(rx: Double, ry: Double, center: Vec2 = Vec2(0, 0), rotation: Double = 0, squareness: Double = 2, n: Int = 40) -> [Vec2] {
        (0 ..< n).map { index in
            let t = 2 * .pi * Double(index) / Double(n)
            let c = cos(t)
            let s = sin(t)
            let r = 1 / pow(pow(abs(c), squareness) + pow(abs(s), squareness), 1 / squareness)
            let x = c * r * rx
            let y = s * r * ry
            return center + Vec2(x * cos(rotation) - y * sin(rotation), x * sin(rotation) + y * cos(rotation))
        }
    }

    /// A painted line on the head: points (head x, y) put on the surface, relative to `origin`, smoothed (Catmull-Rom).
    static func surfaceStroke(_ points: [(Double, Double)], halfWidths: [Double], origin: Vec3, lift: Double, taper: Bool = false) -> DrawingRecipe.Stroke {
        let samples = max(points.count * 6, 12)
        var out: [Vec3] = []
        var widths: [Double] = []
        for index in 0 ... samples {
            let f = Double(index) / Double(samples) * Double(points.count - 1)
            let k = min(Int(f), points.count - 2)
            let t = f - Double(k)
            func pick(_ i: Int) -> (Double, Double) { points[min(max(i, 0), points.count - 1)] }
            let p0 = pick(k - 1), p1 = pick(k), p2 = pick(k + 1), p3 = pick(k + 2)
            func spline(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t * t * t)
            }
            let x = spline(p0.0, p1.0, p2.0, p3.0)
            let y = spline(p0.1, p1.1, p2.1, p3.1)
            out.append(onHead(x, y, lift: lift) - origin)
            let w0 = halfWidths[min(k, halfWidths.count - 1)]
            let w1 = halfWidths[min(k + 1, halfWidths.count - 1)]
            var width = w0 + (w1 - w0) * t
            if taper {
                // Soft ends, like a brush.
                let edge = min(Double(index), Double(samples - index)) / Double(samples)
                width *= min(1, 0.45 + edge * 4)
            }
            widths.append(width)
        }
        return DrawingRecipe.Stroke(points: out, widths: widths)
    }
}

extension CharacterBuilder.Assembler {
    /// A shape from a drawing recipe (lathes, slabs, painted lines), smooth-shaded, in `color`.
    @discardableResult
    mutating func shape(_ name: String, parent: ObjectID, recipe: DrawingRecipe, color: ColorValue) -> ObjectID {
        var object = SceneObject(id: ids.next(), name: name, kind: .drawing(recipe), parent: parent, transform: Transform())
        object[.color] = .color(color)
        object[.shading] = .enumeration(ShadingMode.smooth.rawValue)
        return add(object)
    }
}
