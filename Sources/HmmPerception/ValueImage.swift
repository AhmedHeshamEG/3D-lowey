import Foundation

/// A greyscale "squint" image: CIE L* (0…100) per pixel, optionally blurred. The value view that shows whether the
/// subject reads against the background.
public struct ValueImage: Hashable, Sendable {
    public var width: Int
    public var height: Int
    /// L* per pixel, row-major, top row first.
    public var lightness: [Double]

    public init(width: Int, height: Int, lightness: [Double]) {
        self.width = width
        self.height = height
        self.lightness = lightness
    }

    /// From 8-bit sRGB pixels (`bytesPerPixel` 4, channel order given by `redIndex`… e.g. BGRA = 2, 1, 0).
    public init(pixels: [UInt8], width: Int, height: Int, redIndex: Int = 0, greenIndex: Int = 1, blueIndex: Int = 2) {
        self.width = width
        self.height = height
        var values = [Double](repeating: 0, count: width * height)
        for index in 0 ..< width * height {
            let base = index * 4
            guard base + 3 < pixels.count else { break }
            values[index] = Self.lightness(red: Double(pixels[base + redIndex]) / 255, green: Double(pixels[base + greenIndex]) / 255,
                                           blue: Double(pixels[base + blueIndex]) / 255)
        }
        lightness = values
    }

    /// CIE L* of an sRGB colour.
    public static func lightness(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let y = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return y > 216.0 / 24389.0 ? 116 * cbrt(y) - 16 : y * 24389.0 / 27.0
    }

    /// Box blur of `radius` pixels (a squint).
    public func blurred(radius: Int) -> ValueImage {
        guard radius > 0, width > 0, height > 0 else { return self }
        var horizontal = [Double](repeating: 0, count: lightness.count)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let low = max(column - radius, 0)
                let high = min(column + radius, width - 1)
                var sum = 0.0
                for x in low ... high {
                    sum += lightness[row * width + x]
                }
                horizontal[row * width + column] = sum / Double(high - low + 1)
            }
        }
        var result = horizontal
        for column in 0 ..< width {
            for row in 0 ..< height {
                let low = max(row - radius, 0)
                let high = min(row + radius, height - 1)
                var sum = 0.0
                for y in low ... high {
                    sum += horizontal[y * width + column]
                }
                result[row * width + column] = sum / Double(high - low + 1)
            }
        }
        return ValueImage(width: width, height: height, lightness: result)
    }

    /// Mean L* over a region (pixels where `mask` is true, or a normalised rect).
    public func meanLightness(in rect: PerceptionRect) -> Double? {
        let left = max(Int(rect.x * Double(width)), 0)
        let top = max(Int(rect.y * Double(height)), 0)
        let right = min(Int((rect.maxX * Double(width)).rounded(.up)), width)
        let bottom = min(Int((rect.maxY * Double(height)).rounded(.up)), height)
        guard right > left, bottom > top else { return nil }
        var sum = 0.0
        for row in top ..< bottom {
            for column in left ..< right {
                sum += lightness[row * width + column]
            }
        }
        return sum / Double((right - left) * (bottom - top))
    }

    /// Mean L* of the pixels where `mask(x, y)` is true (nil when none are).
    public func meanLightness(where mask: (Int, Int) -> Bool) -> Double? {
        var sum = 0.0
        var count = 0
        for row in 0 ..< height {
            for column in 0 ..< width where mask(column, row) {
                sum += lightness[row * width + column]
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : nil
    }
}

/// A report for an AI client: a one-paragraph plain-English summary first, then the measured data.
public struct PerceptionReport<Payload: Codable & Sendable>: Codable, Sendable {
    public var summary: String
    public var data: Payload

    public init(summary: String, data: Payload) {
        self.summary = summary
        self.data = data
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
