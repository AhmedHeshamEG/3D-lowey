import Foundation

/// Triangles on a pixel grid: every pixel whose centre lies inside, with its barycentric weights. The CPU side of
/// painting (coverage, carrying paint to a new shape, baking a model's own texture) walks the unwrap with it.
public enum PaintRaster {
    /// Visits the pixels of a triangle given in pixel coordinates (x right, y down). Weights are for a, b, c.
    public static func triangle(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>, width: Int, height: Int,
                                _ body: (_ x: Int, _ y: Int, _ weights: SIMD3<Float>) -> Void) {
        let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        guard abs(area) > 1e-12 else { return }
        let minX = max(Int((min(a.x, b.x, c.x) - 0.5).rounded(.down)), 0)
        let maxX = min(Int((max(a.x, b.x, c.x) - 0.5).rounded(.up)), width - 1)
        let minY = max(Int((min(a.y, b.y, c.y) - 0.5).rounded(.down)), 0)
        let maxY = min(Int((max(a.y, b.y, c.y) - 0.5).rounded(.up)), height - 1)
        guard minX <= maxX, minY <= maxY else { return }
        let inverse = 1 / area
        let epsilon: Float = -1e-5
        for y in minY ... maxY {
            let py = Float(y) + 0.5
            for x in minX ... maxX {
                let px = Float(x) + 0.5
                let wa = ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) * inverse
                let wb = ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) * inverse
                let wc = 1 - wa - wb
                guard wa >= epsilon, wb >= epsilon, wc >= epsilon else { continue }
                body(x, y, SIMD3<Float>(wa, wb, wc))
            }
        }
    }

    /// Which pixels of a `size` texture the unwrap's triangles cover (1) or leave empty (0).
    public static func coverage(_ unwrap: PaintUnwrap, size: Int) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: size * size)
        let scale = Float(size)
        for face in 0 ..< unwrap.triangleCount {
            let a = unwrap.uvs[Int(unwrap.indices[face * 3])] * scale
            let b = unwrap.uvs[Int(unwrap.indices[face * 3 + 1])] * scale
            let c = unwrap.uvs[Int(unwrap.indices[face * 3 + 2])] * scale
            triangle(a, b, c, width: size, height: size) { x, y, _ in mask[y * size + x] = 1 }
        }
        return mask
    }

    /// Pushes covered pixels outward into the empty ones around the charts, `passes` pixels deep, so bilinear
    /// sampling at a chart's edge never reaches an empty pixel (no seams on the model).
    public static func dilate(_ image: inout RGBAImage, coverage: [UInt8], passes: Int = 4) {
        let width = image.width, height = image.height
        guard coverage.count == width * height else { return }
        var filled = coverage
        for _ in 0 ..< passes {
            var next = filled
            var pixels = image.pixels
            for y in 0 ..< height {
                for x in 0 ..< width where filled[y * width + x] == 0 {
                    // Colours weighted by alpha (straight alpha: an unpainted neighbour adds no black).
                    var sum = SIMD3<Int>(0, 0, 0), alpha = 0, count = 0
                    for dy in -1 ... 1 {
                        for dx in -1 ... 1 where dx != 0 || dy != 0 {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < width, ny < height, filled[ny * width + nx] != 0 else { continue }
                            let index = (ny * width + nx) * 4
                            let a = Int(image.pixels[index + 3])
                            sum &+= SIMD3<Int>(Int(image.pixels[index]), Int(image.pixels[index + 1]), Int(image.pixels[index + 2])) &* a
                            alpha += a
                            count += 1
                        }
                    }
                    guard count > 0 else { continue }
                    let index = (y * width + x) * 4
                    if alpha > 0 {
                        for channel in 0 ..< 3 {
                            pixels[index + channel] = UInt8(sum[channel] / alpha)
                        }
                    }
                    pixels[index + 3] = UInt8(alpha / count)
                    next[y * width + x] = 1
                }
            }
            image.pixels = pixels
            filled = next
        }
    }
}
