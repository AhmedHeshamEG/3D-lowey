import Foundation

/// Ink strokes: Pencil lines living in 3D, drawn as flat ribbons that always turn to face the camera (Grease
/// Pencil-style). Width comes from pressure and tapers at both ends, so a stroke reads as a brush line from any
/// angle. They are line art: hair strands, cracks, clouds, speed marks, scribbled props.
public enum InkMesher {
    /// How much of a stroke's length tapers in at each end (a fraction of its length, at most a few widths).
    static let taperFraction = 0.18

    /// The ribbons of every stroke facing `eye` (a point in the drawing's local space), cut to the first `reveal`
    /// (0…1) of the total drawn length so a drawing can write itself on. Without an eye the ribbons lie across the
    /// recipe's plane normal (bounds, picking rays, 3D export).
    public static func mesh(for recipe: DrawingRecipe, eye: Vec3? = nil, reveal: Double = 1) -> MeshData {
        var mesh = MeshData()
        guard reveal > 0 else { return mesh }
        let lengths = recipe.strokes.map { length(of: $0.points) }
        var remaining = lengths.reduce(0, +) * min(reveal, 1)
        for (index, stroke) in recipe.strokes.enumerated() {
            guard remaining > 0 || lengths[index] == 0 else { break }
            let shown = trimmed(stroke, to: remaining)
            remaining -= lengths[index]
            mesh.append(ribbon(shown, fullLength: lengths[index], eye: eye, planeNormal: recipe.normal))
        }
        return mesh
    }

    /// One stroke as a camera-facing ribbon (a dot becomes a small diamond).
    public static func ribbon(_ stroke: DrawingRecipe.Stroke, fullLength: Double? = nil, eye: Vec3?, planeNormal: Vec3) -> MeshData {
        var mesh = MeshData()
        let points = stroke.points
        guard let first = points.first else { return mesh }
        guard points.count >= 2 else {
            return dot(at: first, radius: max(stroke.widths.first ?? 0.02, 0.002), eye: eye, planeNormal: planeNormal)
        }
        let total = fullLength ?? length(of: points)
        let taper = min(total * taperFraction, (stroke.widths.max() ?? 0.02) * 6)
        var travelled = 0.0
        for index in points.indices {
            if index > 0 { travelled += points[index].distance(to: points[index - 1]) }
            let previous = points[max(index - 1, 0)]
            let next = points[min(index + 1, points.count - 1)]
            let tangent = (next - previous).normalized
            let facing = eye.map { ($0 - points[index]).normalized } ?? planeNormal.normalized
            var side = tangent.cross(facing).normalized
            if side.lengthSquared < 0.5 { side = DrawingMesher.basis(for: tangent.lengthSquared > 0.5 ? tangent : .unitY).0 }
            let width = max(stroke.widths[index], 0.0005) * endTaper(at: travelled, length: total, taper: taper)
            let normal = (facing.lengthSquared > 0.5 ? facing : planeNormal.normalized).float3
            let v = Float(total > 0 ? travelled / total : 0)
            _ = mesh.addVertex((points[index] + side * width).float3, normal: normal, uv: SIMD2<Float>(0, v))
            _ = mesh.addVertex((points[index] - side * width).float3, normal: normal, uv: SIMD2<Float>(1, v))
        }
        for index in 0 ..< UInt32(points.count - 1) {
            let l0 = index * 2, r0 = l0 + 1, l1 = l0 + 2, r1 = l0 + 3
            mesh.addTriangle(l0, r0, l1)
            mesh.addTriangle(r0, r1, l1)
        }
        return mesh
    }

    /// 1 in the middle of a stroke, easing to a point at both ends.
    static func endTaper(at distance: Double, length: Double, taper: Double) -> Double {
        guard taper > 1e-6 else { return 1 }
        func ease(_ x: Double) -> Double {
            let t = min(max(x / taper, 0), 1)
            return t * t * (3 - 2 * t)
        }
        return 0.12 + 0.88 * min(ease(distance), ease(length - distance))
    }

    static func dot(at point: Vec3, radius: Double, eye: Vec3?, planeNormal: Vec3) -> MeshData {
        let facing = eye.map { ($0 - point).normalized } ?? planeNormal.normalized
        let (u, v) = DrawingMesher.basis(for: facing.lengthSquared > 0.5 ? facing : .unitY)
        var mesh = MeshData()
        let normal = facing.float3
        let corners = [u, v, -u, -v].map { mesh.addVertex((point + $0 * radius).float3, normal: normal) }
        mesh.addTriangle(corners[0], corners[1], corners[2])
        mesh.addTriangle(corners[0], corners[2], corners[3])
        return mesh
    }

    /// Polyline length.
    public static func length(of points: [Vec3]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// The first `length` metres of a stroke (the last point interpolated).
    static func trimmed(_ stroke: DrawingRecipe.Stroke, to length: Double) -> DrawingRecipe.Stroke {
        guard stroke.points.count >= 2 else { return stroke }
        let alphas = stroke.path.alphas
        var points = [stroke.points[0]]
        var widths = [stroke.widths[0]]
        var kept = [alphas[0]]
        var travelled = 0.0
        for index in 1 ..< stroke.points.count {
            let segment = stroke.points[index].distance(to: stroke.points[index - 1])
            if travelled + segment >= length {
                let t = segment > 0 ? (length - travelled) / segment : 0
                points.append(stroke.points[index - 1].lerp(to: stroke.points[index], t))
                widths.append(stroke.widths[index - 1] + (stroke.widths[index] - stroke.widths[index - 1]) * t)
                kept.append(alphas[index - 1] + (alphas[index] - alphas[index - 1]) * t)
                return stroke.with(points: points, widths: widths, alphas: kept)
            }
            travelled += segment
            points.append(stroke.points[index])
            widths.append(stroke.widths[index])
            kept.append(alphas[index])
        }
        return stroke
    }
}

/// Editing the strokes of an ink drawing: every function returns a new recipe (the editor applies it with one
/// `setKind` command, so each edit is one undo step).
public enum InkEditing {
    /// Adds a stroke at the end (strokes are drawn, revealed and listed in this order).
    public static func appending(_ stroke: DrawingRecipe.Stroke, to recipe: DrawingRecipe) -> DrawingRecipe {
        var result = recipe
        result.strokes.append(stroke)
        return result
    }

    /// Removes the points `isErased` picks, splitting strokes where the eraser crossed them. Pieces shorter than two
    /// points disappear.
    public static func erasing(_ recipe: DrawingRecipe, where isErased: (_ stroke: Int, _ point: Int) -> Bool) -> DrawingRecipe {
        var result = recipe
        result.strokes = []
        for (strokeIndex, stroke) in recipe.strokes.enumerated() {
            let allAlphas = stroke.path.alphas
            var points: [Vec3] = []
            var widths: [Double] = []
            var alphas: [Double] = []
            func flush() {
                if points.count >= 2 { result.strokes.append(stroke.with(points: points, widths: widths, alphas: alphas)) }
                points = []
                widths = []
                alphas = []
            }
            for pointIndex in stroke.points.indices {
                if isErased(strokeIndex, pointIndex) {
                    flush()
                } else {
                    points.append(stroke.points[pointIndex])
                    widths.append(stroke.widths[pointIndex])
                    alphas.append(allAlphas[pointIndex])
                }
            }
            flush()
        }
        return result
    }

    /// The strokes that have at least one point `matches` picks (a tap or a lasso on screen).
    public static func strokes(of recipe: DrawingRecipe, where matches: (Vec3) -> Bool) -> Set<Int> {
        Set(recipe.strokes.indices.filter { recipe.strokes[$0].points.contains(where: matches) })
    }

    public static func removing(_ strokes: Set<Int>, from recipe: DrawingRecipe) -> DrawingRecipe {
        var result = recipe
        result.strokes = recipe.strokes.indices.filter { !strokes.contains($0) }.map { recipe.strokes[$0] }
        return result
    }

    public static func moving(_ strokes: Set<Int>, by offset: Vec3, in recipe: DrawingRecipe) -> DrawingRecipe {
        updating(strokes, in: recipe) { stroke in
            stroke.with(points: stroke.points.map { $0 + offset }, widths: stroke.widths, alphas: stroke.alphas)
        }
    }

    /// Smooths the chosen strokes (0 = untouched, 1 = very smooth), keeping their ends where they were.
    public static func smoothing(_ strokes: Set<Int>, by amount: Double, in recipe: DrawingRecipe) -> DrawingRecipe {
        updating(strokes, in: recipe) { stroke in
            let smoothed = StrokeFilter.process(points: stroke.points, widths: stroke.widths, smoothing: amount, minSpacing: 0)
            let alphas = smoothed.points.count == stroke.points.count ? stroke.alphas : nil
            return stroke.with(points: smoothed.points, widths: smoothed.widths, alphas: alphas)
        }
    }

    /// Scales the chosen strokes' widths (pressure shape kept).
    public static func scalingWidths(_ strokes: Set<Int>, by factor: Double, in recipe: DrawingRecipe) -> DrawingRecipe {
        let factor = min(max(factor, 0.05), 20)
        return updating(strokes, in: recipe) { stroke in
            stroke.with(points: stroke.points, widths: stroke.widths.map { min(max($0 * factor, 0.0005), 1) }, alphas: stroke.alphas)
        }
    }

    static func updating(_ strokes: Set<Int>, in recipe: DrawingRecipe,
                         _ change: (DrawingRecipe.Stroke) -> DrawingRecipe.Stroke) -> DrawingRecipe {
        var result = recipe
        for index in strokes where recipe.strokes.indices.contains(index) {
            result.strokes[index] = change(recipe.strokes[index])
        }
        return result
    }
}

public extension SceneObject {
    /// An ink drawing (line art: unlit, no outlines of its own).
    var isInk: Bool {
        if case let .drawing(recipe) = kind { return recipe.style == .ink }
        return false
    }
}
