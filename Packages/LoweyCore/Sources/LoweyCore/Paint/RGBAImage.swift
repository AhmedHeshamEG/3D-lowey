import Foundation

/// A colour picture: four bytes per pixel (red, green, blue in sRGB, straight alpha), rows from the top. Paint tiles,
/// layers and the textures exports carry are these.
public struct RGBAImage: Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels.count == width * height * 4 ? pixels : [UInt8](repeating: 0, count: width * height * 4)
    }

    /// Every pixel one colour.
    public init(width: Int, height: Int, color: RGBA) {
        let bytes = Self.bytes(color)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0 ..< width * height {
            pixels[index * 4] = bytes.0
            pixels[index * 4 + 1] = bytes.1
            pixels[index * 4 + 2] = bytes.2
            pixels[index * 4 + 3] = bytes.3
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    /// Transparent.
    public static func clear(width: Int, height: Int) -> RGBAImage {
        RGBAImage(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height * 4))
    }

    public var isClear: Bool {
        stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 0 }
    }

    public static func bytes(_ color: RGBA) -> (UInt8, UInt8, UInt8, UInt8) {
        func byte(_ value: Double) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
        return (byte(color.r), byte(color.g), byte(color.b), byte(color.a))
    }

    public func pixel(_ x: Int, _ y: Int) -> RGBA {
        let index = (y * width + x) * 4
        return RGBA(Double(pixels[index]) / 255, Double(pixels[index + 1]) / 255, Double(pixels[index + 2]) / 255,
                    Double(pixels[index + 3]) / 255)
    }

    public mutating func setPixel(_ x: Int, _ y: Int, _ color: RGBA) {
        let index = (y * width + x) * 4
        let bytes = Self.bytes(color)
        pixels[index] = bytes.0
        pixels[index + 1] = bytes.1
        pixels[index + 2] = bytes.2
        pixels[index + 3] = bytes.3
    }

    /// Bilinear sample at a uv (0…1 across the picture, v down), repeating past the edges as glTF textures do; colours
    /// are weighted by alpha so transparent pixels don't darken an edge.
    public func sample(u: Double, v: Double) -> RGBA {
        guard width > 0, height > 0 else { return RGBA(0, 0, 0, 0) }
        let x = u * Double(width) - 0.5
        let y = v * Double(height) - 0.5
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Double(x0), fy = y - Double(y0)
        var sum = (r: 0.0, g: 0.0, b: 0.0, a: 0.0)
        for (dx, dy, weight) in [(0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)] where weight > 0 {
            let px = ((x0 + dx) % width + width) % width
            let py = ((y0 + dy) % height + height) % height
            let index = (py * width + px) * 4
            let alpha = Double(pixels[index + 3]) / 255 * weight
            sum.r += Double(pixels[index]) / 255 * alpha
            sum.g += Double(pixels[index + 1]) / 255 * alpha
            sum.b += Double(pixels[index + 2]) / 255 * alpha
            sum.a += alpha
        }
        guard sum.a > 1e-6 else { return RGBA(0, 0, 0, 0) }
        return RGBA(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a, sum.a)
    }

    /// The `size` × `size` square at a tile's place (transparent beyond the picture).
    public func tile(_ index: PaintTileIndex, size: Int) -> RGBAImage {
        var result = RGBAImage.clear(width: size, height: size)
        for row in 0 ..< size {
            let y = index.row * size + row
            guard y < height else { break }
            let columns = min(size, width - index.column * size)
            guard columns > 0 else { break }
            let from = (y * width + index.column * size) * 4
            result.pixels.replaceSubrange(row * size * 4 ..< (row * size + columns) * 4, with: pixels[from ..< from + columns * 4])
        }
        return result
    }

    /// Copies a picture in with its top left at (x, y).
    public mutating func place(_ image: RGBAImage, x: Int, y: Int) {
        for row in 0 ..< image.height {
            let ty = y + row
            guard ty >= 0, ty < height else { continue }
            let first = max(0, -x), last = min(image.width, width - x)
            guard first < last else { continue }
            let from = (row * image.width + first) * 4
            let to = (ty * width + x + first) * 4
            pixels.replaceSubrange(to ..< to + (last - first) * 4, with: image.pixels[from ..< from + (last - first) * 4])
        }
    }
}

/// PNG for paint: decodes any 8-bit, non-interlaced PNG (grey, RGB, palette, with or without alpha); encodes RGBA with
/// stored deflate blocks (the app encodes its tiles with ImageIO; this is the portable path tests and Linux use).
public enum PNGCodec {
    public enum Failure: Error, Equatable {
        case notPNG, unsupported(String), corrupt
    }

    public static func encode(_ image: RGBAImage) -> Data {
        var raw = [UInt8]()
        raw.reserveCapacity((image.width * 4 + 1) * image.height)
        for row in 0 ..< image.height {
            raw.append(0)
            raw += image.pixels[row * image.width * 4 ..< (row + 1) * image.width * 4]
        }
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.appendBigEndian(UInt32(image.width))
        header.appendBigEndian(UInt32(image.height))
        header += Data([8, 6, 0, 0, 0])
        data += GreyPNG.chunk("IHDR", header)
        data += GreyPNG.chunk("IDAT", GreyPNG.zlibStored(raw))
        data += GreyPNG.chunk("IEND", Data())
        return data
    }

    private struct Header {
        var width = 0, height = 0, colorType = 0
        var palette: [UInt8] = []
        var transparency: [UInt8] = []

        var channels: Int {
            switch colorType {
            case 0, 3: 1
            case 4: 2
            case 2: 3
            default: 4
            }
        }
    }

    public static func decode(_ data: Data) throws(Failure) -> RGBAImage {
        let bytes = [UInt8](data)
        guard bytes.count > 8, bytes[0 ..< 8] == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] else { throw .notPNG }
        var header = Header()
        var compressed = Data()
        var offset = 8
        while offset + 8 <= bytes.count {
            let length = Int(UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3]))
            let type = String(decoding: bytes[offset + 4 ..< offset + 8], as: UTF8.self)
            let body = offset + 8
            guard length >= 0, body + length <= bytes.count else { throw .corrupt }
            let chunk = bytes[body ..< body + length]
            switch type {
            case "IHDR": try readHeader(Array(chunk), into: &header)
            case "PLTE": header.palette = Array(chunk)
            case "tRNS": header.transparency = Array(chunk)
            case "IDAT": compressed.append(contentsOf: chunk)
            case "IEND": offset = bytes.count
            default: break
            }
            offset = body + length + 4
        }
        guard header.width > 0, header.height > 0, compressed.count > 2 else { throw .corrupt }
        let stride = header.width * header.channels
        let raw: Data
        do {
            raw = try Inflate.decompress(compressed.dropFirst(2), expectedSize: (stride + 1) * header.height)
        } catch {
            throw .corrupt
        }
        let rows = try unfilter([UInt8](raw), stride: stride, height: header.height, bytesPerPixel: header.channels)
        return expand(rows, header: header)
    }

    private static func readHeader(_ chunk: [UInt8], into header: inout Header) throws(Failure) {
        guard chunk.count >= 13 else { throw .corrupt }
        header.width = Int(UInt32(chunk[0]) << 24 | UInt32(chunk[1]) << 16 | UInt32(chunk[2]) << 8 | UInt32(chunk[3]))
        header.height = Int(UInt32(chunk[4]) << 24 | UInt32(chunk[5]) << 16 | UInt32(chunk[6]) << 8 | UInt32(chunk[7]))
        guard chunk[8] == 8 else { throw .unsupported("\(chunk[8])-bit") }
        header.colorType = Int(chunk[9])
        guard [0, 2, 3, 4, 6].contains(header.colorType) else { throw .unsupported("colour type \(header.colorType)") }
        guard chunk[12] == 0 else { throw .unsupported("interlaced") }
        guard header.width <= 16384, header.height <= 16384 else { throw .unsupported("larger than 16384") }
    }

    private static func unfilter(_ raw: [UInt8], stride: Int, height: Int, bytesPerPixel: Int) throws(Failure) -> [UInt8] {
        guard raw.count >= (stride + 1) * height else { throw .corrupt }
        var out = [UInt8](repeating: 0, count: stride * height)
        for row in 0 ..< height {
            let filter = raw[row * (stride + 1)]
            let source = row * (stride + 1) + 1
            let target = row * stride
            for column in 0 ..< stride {
                let x = Int(raw[source + column])
                let a = column >= bytesPerPixel ? Int(out[target + column - bytesPerPixel]) : 0
                let b = row > 0 ? Int(out[target - stride + column]) : 0
                let c = row > 0 && column >= bytesPerPixel ? Int(out[target - stride + column - bytesPerPixel]) : 0
                let value: Int
                switch filter {
                case 0: value = x
                case 1: value = x + a
                case 2: value = x + b
                case 3: value = x + (a + b) / 2
                case 4:
                    let p = a + b - c
                    let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
                    value = x + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)
                default: throw .corrupt
                }
                out[target + column] = UInt8(truncatingIfNeeded: value)
            }
        }
        return out
    }

    private static func expand(_ rows: [UInt8], header: Header) -> RGBAImage {
        let count = header.width * header.height
        var pixels = [UInt8](repeating: 255, count: count * 4)
        for index in 0 ..< count {
            switch header.colorType {
            case 0:
                let grey = rows[index]
                pixels[index * 4] = grey
                pixels[index * 4 + 1] = grey
                pixels[index * 4 + 2] = grey
                if header.transparency.count >= 2, header.transparency[1] == grey { pixels[index * 4 + 3] = 0 }
            case 4:
                pixels[index * 4] = rows[index * 2]
                pixels[index * 4 + 1] = rows[index * 2]
                pixels[index * 4 + 2] = rows[index * 2]
                pixels[index * 4 + 3] = rows[index * 2 + 1]
            case 2:
                pixels[index * 4] = rows[index * 3]
                pixels[index * 4 + 1] = rows[index * 3 + 1]
                pixels[index * 4 + 2] = rows[index * 3 + 2]
            case 3:
                let entry = Int(rows[index])
                if entry * 3 + 2 < header.palette.count {
                    pixels[index * 4] = header.palette[entry * 3]
                    pixels[index * 4 + 1] = header.palette[entry * 3 + 1]
                    pixels[index * 4 + 2] = header.palette[entry * 3 + 2]
                }
                if entry < header.transparency.count { pixels[index * 4 + 3] = header.transparency[entry] }
            default:
                pixels.replaceSubrange(index * 4 ..< index * 4 + 4, with: rows[index * 4 ..< index * 4 + 4])
            }
        }
        return RGBAImage(width: header.width, height: header.height, pixels: pixels)
    }
}

/// Content names for paint files: the same pixels always get the same name.
public enum PaintFiles {
    public static let folder = "paint"

    public static func tileName(for png: Data) -> String {
        "\(folder)/\(BrushKey.hex(BrushKey.fnv(png))).png"
    }

    public static func unwrapName(for data: Data) -> String {
        "\(folder)/\(BrushKey.hex(BrushKey.fnv(data))).uv"
    }
}
