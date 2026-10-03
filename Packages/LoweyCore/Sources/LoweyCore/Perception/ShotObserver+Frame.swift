import Foundation
import HmmPerception

// MARK: - The frame

extension ShotObserver {
    func frameRead(_ measured: [Measured], subject: ObjectID?, declared: Bool, camera: ObserveCamera, scene: Scene) -> FrameRead {
        let unit = subject.flatMap { id in measured.first { $0.id == id } }
        var thirds: String?
        var thirdsError: Double?
        var headroom: Double?
        if let unit {
            let middle = unit.object.box.midX
            let lines: [(Double, String)] = [(1.0 / 3.0, "left third"), (0.5, "centre"), (2.0 / 3.0, "right third")]
            let nearest = lines.min { abs($0.0 - middle) < abs($1.0 - middle) } ?? lines[1]
            // Frame heights, so 16:9 and 9:16 read alike.
            thirdsError = abs(nearest.0 - middle) * camera.aspect
            thirds = (thirdsError ?? 1) <= 0.09 * max(camera.aspect, 1) ? nearest.1 : "off the grid"
            headroom = unit.extent.y
        }
        var tangents: [String] = []
        for item in measured where !item.object.isSet && item.object.coverage > 0.5 {
            let e = item.extent
            let edges: [(Double, String)] = [(e.x, "left"), (1 - e.maxX, "right"), (e.y, "top"), (1 - e.maxY, "bottom")]
            for (distance, edge) in edges where distance >= 0 && distance < 0.01 {
                tangents.append("“\(item.object.name)” \(edge)")
            }
        }
        let empty: Double = measured.isEmpty ? 100 : emptyArea(measured)
        return FrameRead(
            subject: unit?.object.name, subjectDeclared: declared && unit != nil, subjectX: unit?.object.box.midX, subjectY: unit?.object.box.midY,
            thirds: thirds, thirdsError: thirdsError, headroom: headroom, emptyArea: empty, contrast: nil, silhouetteSeparation: nil,
            clutter: Self.clutter(measured, scene: scene), horizonTilt: camera.roll, tangents: tangents,
            palette: nil, light: LightRead(keyFrom: keyFrom(camera: camera, scene: scene), subjectInShadow: nil, subjectLightness: nil, worldLightness: nil)
        )
    }

    /// Significant elements (over 1% of the frame, the set aside). Copies of one thing (nine desks, a row of screens)
    /// read as one pattern, so they count once.
    static func clutter(_ measured: [Measured], scene: Scene) -> Int {
        Set(measured.filter { !$0.object.isSet && $0.object.coverage > 1 }.map { unit -> String in
            if let asset = scene.objects[unit.id]?.kind.assetID { return asset.raw }
            return unit.object.name.replacingOccurrences(of: #"\s*\d+$"#, with: "", options: .regularExpression).lowercased()
        }).count
    }

    /// % of the frame showing nothing but sky, ground or the set.
    func emptyArea(_ measured: [Measured]) -> Double {
        let filled = measured.filter { !$0.object.isSet }.reduce(0.0) { $0 + $1.object.coverage }
        return max(100 - filled, 0)
    }

    /// Where the key light comes from, as the camera sees it: the sun, or the brightest light near the subject.
    func keyFrom(camera: ObserveCamera, scene: Scene) -> String {
        let toLight = (-document.effectiveLook.lighting.sunDirection).normalized
        let across = toLight.dot(camera.right)
        let upward = toLight.dot(camera.up)
        let toward = -toLight.dot(camera.forward)
        if toward < -0.5 { return "behind the subject (rim light)" }
        let side = across < -0.3 ? "left" : across > 0.3 ? "right" : ""
        let height = upward > 0.7 ? "above" : upward > 0.25 ? "upper" : upward < -0.2 ? "below" : ""
        let words = [height, side].filter { !$0.isEmpty }.joined(separator: " ")
        let lights = scene.objects.values.filter { if case .light = $0.kind { return $0.isVisible } else { return false } }.count
        let extra = lights > 0 ? " + \(lights) lamp\(lights == 1 ? "" : "s")" : ""
        return (words.isEmpty ? "the camera's side (flat front light)" : words) + extra
    }

    static func summary(objects: [ObservedObject], frame: FrameRead, checks: [RubricCheck], camera: String) -> String {
        var parts: [String] = []
        if let subject = frame.subject, let object = objects.first(where: { $0.name == subject }) {
            let contrast = frame.contrast.map { ", ΔL* \(Int($0.rounded()))" } ?? ""
            parts.append("Through “\(camera)”: “\(subject)” (mark \(object.mark)) is the \(frame.subjectDeclared ? "declared" : "likely") subject, "
                + "\(frame.thirds ?? "?"), \(ShotRubric.percent(object.coverage)) of the frame\(contrast).")
        } else {
            parts.append("Through “\(camera)”: no subject in frame.")
        }
        parts.append("\(objects.count) labelled thing\(objects.count == 1 ? "" : "s"), \(frame.clutter) significant; key from \(frame.light.keyFrom).")
        let fails = checks.filter { $0.result == .fail }
        parts.append(fails.isEmpty ? "Passes the rubric." : "Fails " + fails.map { "\($0.name) (\($0.detail))" }.joined(separator: "; ") + ".")
        let skipped = checks.filter { $0.result == .skipped }.map(\.name)
        if !skipped.isEmpty { parts.append("Not measured here: \(skipped.joined(separator: ", ")).") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Pixels

extension ShotObserver {
    /// Contrast, silhouette, palette and light from the rendered frame, sampled at the raster's resolution.
    func readPixels(_ pixels: ObservePixels, raster: CoverageRaster, units: [Measured], subject: ObjectID?, objects: inout [ObservedObject],
                    frame: inout FrameRead) {
        let width = raster.width
        let height = raster.height
        var lightness = [Double](repeating: 0, count: width * height)
        var colors: [(red: Double, green: Double, blue: Double)] = []
        colors.reserveCapacity(width * height)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let color = pixels.color(x: (Double(column) + 0.5) / Double(width), y: (Double(row) + 0.5) / Double(height))
                colors.append(color)
                lightness[row * width + column] = ValueImage.lightness(red: color.red, green: color.green, blue: color.blue)
            }
        }
        frame.palette = Self.palette(colors)
        let squint = ValueImage(width: width, height: height, lightness: lightness).blurred(radius: 1)
        for index in objects.indices where objects[index].coverage > 0 {
            guard let unit = units.first(where: { $0.object.id == objects[index].id }) else { continue }
            let read = Self.valueRead(squint, raster: raster, label: unit.label, box: unit.object.box)
            objects[index].lightness = read.lightness.map { ($0 * 10).rounded() / 10 }
            objects[index].contrast = read.contrast.map { ($0 * 10).rounded() / 10 }
        }
        guard let subject, let unit = units.first(where: { $0.id == subject }) else { return }
        let label = unit.label
        frame.contrast = objects.first { $0.id == subject.raw }?.contrast
        frame.silhouetteSeparation = separation(lightness, raster: raster, label: label)
        let subjectValues = lightness.indices.filter { raster.labels[$0] == label }.map { lightness[$0] }.sorted()
        let world = lightness.indices.filter { raster.labels[$0] != label }.map { lightness[$0] }
        if !subjectValues.isEmpty {
            let bright = subjectValues[min(Int(Double(subjectValues.count) * 0.9), subjectValues.count - 1)]
            let shadowed = subjectValues.filter { $0 < bright - 20 }.count
            frame.light.subjectInShadow = Double(shadowed) / Double(subjectValues.count) * 100
            frame.light.subjectLightness = subjectValues.reduce(0, +) / Double(subjectValues.count)
        }
        if !world.isEmpty { frame.light.worldLightness = world.reduce(0, +) / Double(world.count) }
    }

    /// Mean L* of a label's pixels and its difference from the pixels around it (a box half as big again).
    static func valueRead(_ squint: ValueImage, raster: CoverageRaster, label: Int32, box: PerceptionRect) -> (lightness: Double?, contrast: Double?) {
        let width = Double(raster.width)
        let height = Double(raster.height)
        let ring = PerceptionRect(x: box.x - box.width * 0.25, y: box.y - box.height * 0.25, width: box.width * 1.5, height: box.height * 1.5)
        let mean = squint.meanLightness { raster.shows(label, x: $0, y: $1) }
        let around = squint.meanLightness { x, y in
            let nx = (Double(x) + 0.5) / width
            let ny = (Double(y) + 0.5) / height
            return nx >= ring.x && nx <= ring.maxX && ny >= ring.y && ny <= ring.maxY && !raster.shows(label, x: x, y: y)
        }
        guard let mean else { return (nil, nil) }
        return (mean, around.map { abs(mean - $0) })
    }

    /// % of the subject's outline pixels whose outside neighbour differs by ΔL* ≥ 12.
    func separation(_ lightness: [Double], raster: CoverageRaster, label: Int32) -> Double? {
        var edges = 0
        var separated = 0
        for row in 0 ..< raster.height {
            for column in 0 ..< raster.width where raster.shows(label, x: column, y: row) {
                let outside = [(column - 1, row), (column + 1, row), (column, row - 1), (column, row + 1)].filter { x, y in
                    x >= 0 && y >= 0 && x < raster.width && y < raster.height && !raster.shows(label, x: x, y: y)
                }
                guard !outside.isEmpty else { continue }
                edges += 1
                let own = lightness[row * raster.width + column]
                if outside.contains(where: { abs(lightness[$0.1 * raster.width + $0.0] - own) >= 12 }) { separated += 1 }
            }
        }
        return edges > 0 ? Double(separated) / Double(edges) * 100 : nil
    }

    /// Up to five dominant colours (distinct from each other) and the saturation spread.
    static func palette(_ colors: [(red: Double, green: Double, blue: Double)]) -> PaletteRead {
        struct Bucket {
            var count = 0
            var red = 0.0
            var green = 0.0
            var blue = 0.0
        }
        var buckets: [Int: Bucket] = [:]
        var saturations: [Double] = []
        saturations.reserveCapacity(colors.count)
        for color in colors {
            let key = Int(color.red * 15.99) << 8 | Int(color.green * 15.99) << 4 | Int(color.blue * 15.99)
            buckets[key, default: Bucket()].count += 1
            buckets[key]?.red += color.red
            buckets[key]?.green += color.green
            buckets[key]?.blue += color.blue
            let high = max(color.red, color.green, color.blue)
            saturations.append(high > 0 ? (high - min(color.red, color.green, color.blue)) / high : 0)
        }
        var picked: [(RGBA, Int)] = []
        for bucket in buckets.values.sorted(by: { $0.count > $1.count }) where picked.count < 5 {
            let n = Double(bucket.count)
            let color = RGBA(bucket.red / n, bucket.green / n, bucket.blue / n)
            let distinct = picked.allSatisfy { other, _ in
                let dr = other.r - color.r
                let dg = other.g - color.g
                let db = other.b - color.b
                return (dr * dr + dg * dg + db * db).squareRoot() > 0.15
            }
            if distinct { picked.append((color, bucket.count)) }
        }
        let total = Double(max(colors.count, 1))
        let mean = saturations.reduce(0, +) / Double(max(saturations.count, 1))
        let variance = saturations.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(saturations.count, 1))
        return PaletteRead(colors: picked.map(\.0.hex), shares: picked.map { (Double($0.1) / total * 1000).rounded() / 10 },
                           saturationSpread: (variance.squareRoot() * 1000).rounded() / 1000)
    }
}
