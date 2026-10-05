import Foundation

/// A grey picture: one byte per pixel, rows from the top, white paints.
public struct GreyImage: Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, value: (_ x: Double, _ y: Double) -> Double) {
        self.width = width
        self.height = height
        var pixels = [UInt8](repeating: 0, count: width * height)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let v = value((Double(column) + 0.5) / Double(width), (Double(row) + 0.5) / Double(height))
                pixels[row * width + column] = UInt8((v.clamped(0, 1) * 255).rounded())
            }
        }
        self.pixels = pixels
    }

    /// Box-filtered down so neither side passes `maximum` (tips larger than that only cost memory).
    public func fitting(_ maximum: Int) -> GreyImage {
        let factor = Int((Double(max(width, height)) / Double(maximum)).rounded(.up))
        guard factor > 1 else { return self }
        let w = max(width / factor, 1), h = max(height / factor, 1)
        var result = [UInt8](repeating: 0, count: w * h)
        for row in 0 ..< h {
            for column in 0 ..< w {
                var sum = 0
                for dy in 0 ..< factor {
                    let base = (row * factor + dy) * width + column * factor
                    for dx in 0 ..< factor {
                        sum += Int(pixels[base + dx])
                    }
                }
                result[row * w + column] = UInt8(sum / (factor * factor))
            }
        }
        return GreyImage(width: w, height: h, pixels: result)
    }

    /// The mean coverage, 0…1 (tests, and spotting an empty tip).
    public var coverage: Double {
        pixels.isEmpty ? 0 : Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count * 255)
    }
}

/// The built-in tips and grains, drawn by code (so no bitmap of anyone else's ships with the app). The same bytes
/// on every device: the renderer uploads them as textures, Brush Studio shows them, tests check them.
public enum BrushImages {
    /// Tips are this many pixels square, grains this many and tile seamlessly.
    public static let tipSize = 128
    public static let grainSize = 256

    public static func image(_ builtIn: BuiltInBrushImage) -> GreyImage {
        let tip = tipSize
        switch builtIn {
        case .hardRound:
            return GreyImage(width: tip, height: tip) { x, y in disc(x, y, edge: 1.5 / Double(tip)) }
        case .softRound:
            return GreyImage(width: tip, height: tip) { x, y in
                let r = min(radius(x, y) / 0.5, 1)
                return pow(1 - r * r, 2)
            }
        case .pencilTip:
            let noise = ValueNoise(seed: 11, cells: 24)
            return GreyImage(width: tip, height: tip) { x, y in
                disc(x, y, edge: 0.08 + 0.06 * noise.value(x, y)) * (0.75 + 0.25 * noise.value(x * 3, y * 3))
            }
        case .chalkTip:
            let noise = ValueNoise(seed: 23, cells: 16)
            return GreyImage(width: tip, height: tip) { x, y in
                let rough = noise.fractal(x, y, octaves: 3)
                return disc(x, y, edge: 0.04) * smooth(0.32, 0.55, rough)
            }
        case .bristleTip:
            return bristles()
        case .flatTip:
            return GreyImage(width: tip, height: tip) { x, y in
                let dx = abs(x - 0.5) / 0.48, dy = abs(y - 0.5) / 0.16
                let d = pow(pow(dx, 6) + pow(dy, 6), 1.0 / 6)
                return 1 - smooth(0.92, 1, d)
            }
        case .splatterTip:
            return splatter()
        case .paper, .canvas, .noise, .charcoal:
            return grain(builtIn)
        }
    }

    static func grain(_ builtIn: BuiltInBrushImage) -> GreyImage {
        let size = grainSize
        switch builtIn {
        case .canvas:
            let noise = ValueNoise(seed: 5, cells: 64)
            return GreyImage(width: size, height: size) { x, y in
                let weave = 0.5 + 0.25 * (sin(x * .pi * 2 * 32) + sin(y * .pi * 2 * 32))
                return 0.35 + 0.5 * weave * (0.7 + 0.3 * noise.value(x, y))
            }
        case .noise:
            let noise = ValueNoise(seed: 7, cells: 128)
            return GreyImage(width: size, height: size) { x, y in noise.value(x, y) }
        case .charcoal:
            let streaks = ValueNoise(seed: 13, cells: 8)
            let fine = ValueNoise(seed: 17, cells: 96)
            return GreyImage(width: size, height: size) { x, y in
                smooth(0.25, 0.75, 0.6 * streaks.value(x * 0.25, y * 8) + 0.4 * fine.value(x, y))
            }
        default:
            let noise = ValueNoise(seed: 3, cells: 32)
            return GreyImage(width: size, height: size) { x, y in 0.25 + 0.75 * smooth(0.2, 0.8, noise.fractal(x, y, octaves: 4)) }
        }
    }

    private static func bristles() -> GreyImage {
        var random = SeededRandom(seed: 31)
        let hairs = (0 ..< 28).map { _ in (x: 0.08 + random.unit() * 0.84, width: 0.006 + random.unit() * 0.012, ink: 0.45 + random.unit() * 0.55) }
        return GreyImage(width: tipSize, height: tipSize) { x, y in
            let body = 1 - smooth(0.42, 0.5, abs(y - 0.5) * (1 + 0.3 * abs(x - 0.5)))
            var ink = 0.0
            for hair in hairs {
                ink = max(ink, hair.ink * (1 - smooth(hair.width * 0.5, hair.width, abs(x - hair.x))))
            }
            return ink * body
        }
    }

    private static func splatter() -> GreyImage {
        var random = SeededRandom(seed: 41)
        let drops = (0 ..< 18).map { _ -> (Double, Double, Double) in
            let angle = random.unit() * 2 * .pi, distance = pow(random.unit(), 0.7) * 0.4
            return (0.5 + cos(angle) * distance, 0.5 + sin(angle) * distance, 0.02 + random.unit() * 0.07 * (1 - distance))
        }
        return GreyImage(width: tipSize, height: tipSize) { x, y in
            drops.reduce(0.0) { ink, drop in
                let d = ((x - drop.0) * (x - drop.0) + (y - drop.1) * (y - drop.1)).squareRoot()
                return max(ink, 1 - smooth(drop.2 * 0.85, drop.2, d))
            }
        }
    }

    static func radius(_ x: Double, _ y: Double) -> Double {
        ((x - 0.5) * (x - 0.5) + (y - 0.5) * (y - 0.5)).squareRoot()
    }

    /// A disc filling the square, its edge softened over `edge`.
    static func disc(_ x: Double, _ y: Double, edge: Double) -> Double {
        1 - smooth(0.5 - edge, 0.5, radius(x, y))
    }

    static func smooth(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
        let t = ((value - lower) / max(upper - lower, 1e-9)).clamped(0, 1)
        return t * t * (3 - 2 * t)
    }
}

/// Value noise on a lattice that wraps, so grains tile.
struct ValueNoise {
    var cells: Int
    private var lattice: [Double]

    init(seed: UInt64, cells: Int) {
        var random = SeededRandom(seed: seed)
        self.cells = cells
        lattice = (0 ..< cells * cells).map { _ in random.unit() }
    }

    /// 0…1 over x, y in 0…1 (any real value wraps).
    func value(_ x: Double, _ y: Double) -> Double {
        let fx = x * Double(cells), fy = y * Double(cells)
        let x0 = Int(floor(fx)), y0 = Int(floor(fy))
        let tx = fx - Double(x0), ty = fy - Double(y0)
        func at(_ i: Int, _ j: Int) -> Double {
            let a = ((i % cells) + cells) % cells, b = ((j % cells) + cells) % cells
            return lattice[b * cells + a]
        }
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
        let top = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * sx
        let bottom = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * sx
        return top + (bottom - top) * sy
    }

    /// Octaves at doubling frequencies (each still wraps).
    func fractal(_ x: Double, _ y: Double, octaves: Int) -> Double {
        var sum = 0.0, weight = 0.5, total = 0.0, frequency = 1.0
        for _ in 0 ..< octaves {
            sum += value(x * frequency, y * frequency) * weight
            total += weight
            weight *= 0.5
            frequency *= 2
        }
        return sum / total
    }
}

/// Grey PNGs without a compressor: stored deflate blocks (imported tips are box-filtered to ≤ 512 px first, so a
/// file stays under a quarter of a megabyte).
public enum GreyPNG {
    public static func encode(_ image: GreyImage) -> Data {
        var raw = [UInt8]()
        raw.reserveCapacity((image.width + 1) * image.height)
        for row in 0 ..< image.height {
            raw.append(0)
            raw += image.pixels[row * image.width ..< (row + 1) * image.width]
        }
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.appendBigEndian(UInt32(image.width))
        header.appendBigEndian(UInt32(image.height))
        header += Data([8, 0, 0, 0, 0])
        data += chunk("IHDR", header)
        data += chunk("IDAT", zlibStored(raw))
        data += chunk("IEND", Data())
        return data
    }

    static func chunk(_ type: String, _ body: Data) -> Data {
        var data = Data()
        data.appendBigEndian(UInt32(body.count))
        let typed = Data(type.utf8) + body
        data += typed
        data.appendBigEndian(CRC32.checksum(typed))
        return data
    }

    static func zlibStored(_ bytes: [UInt8]) -> Data {
        var data = Data([0x78, 0x01])
        var offset = 0
        repeat {
            let count = min(65535, bytes.count - offset)
            let last: UInt8 = offset + count >= bytes.count ? 1 : 0
            data.append(last)
            data.append(UInt8(count & 0xFF))
            data.append(UInt8(count >> 8))
            data.append(UInt8(~count & 0xFF))
            data.append(UInt8((~count >> 8) & 0xFF))
            data += bytes[offset ..< offset + count]
            offset += count
        } while offset < bytes.count
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        data.appendBigEndian(b << 16 | a)
        return data
    }
}

extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
}
