import Foundation

/// RGBA color with components in 0...1 (sRGB, as people pick them).
/// Encodes as a hex string: `"#RRGGBB"` or `"#RRGGBBAA"`.
///
/// Components are quantized to 8-bit steps on creation, so a color always survives
/// save → load bit-for-bit (a saved scene reopens *identical*).
public struct RGBA: Hashable, Sendable {
    public private(set) var r: Double
    public private(set) var g: Double
    public private(set) var b: Double
    public private(set) var a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = Self.quantize(r)
        self.g = Self.quantize(g)
        self.b = Self.quantize(b)
        self.a = Self.quantize(a)
    }

    private static func quantize(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (Swift.min(Swift.max(value, 0), 1) * 255).rounded() / 255
    }

    /// A colour written in code as "#RRGGBB" (a literal checked by the tests; a typo shows as magenta, never a crash).
    public static func hex(_ literal: StaticString) -> RGBA {
        RGBA(hex: "\(literal)") ?? RGBA(1, 0, 1)
    }

    public init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6 || string.count == 8, let value = UInt64(string, radix: 16) else { return nil }
        if string.count == 6 {
            self.init(
                Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255
            )
        } else {
            self.init(
                Double((value >> 24) & 0xFF) / 255,
                Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255
            )
        }
    }

    public var hex: String {
        func byte(_ value: Double) -> Int { Int((Swift.min(Swift.max(value, 0), 1) * 255).rounded()) }
        if byte(a) == 255 {
            return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        }
        return String(format: "#%02X%02X%02X%02X", byte(r), byte(g), byte(b), byte(a))
    }

    public func lerp(to other: RGBA, _ t: Double) -> RGBA {
        RGBA(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a + (other.a - a) * t)
    }

    /// Perceived brightness (Rec. 709 luma).
    public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    public func scaled(_ factor: Double) -> RGBA { RGBA(r * factor, g * factor, b * factor, a) }

    public static let white = RGBA(1, 1, 1)
    public static let black = RGBA(0, 0, 0)
    /// The neutral blockout grey.
    public static let blockout = RGBA.hex("#C7C7C2")
}

extension RGBA: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = RGBA(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid color \(string)")
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

/// A color that is either literal or bound to a slot of the project palette.
/// Change the palette and every bound object updates.
///
/// JSON: `"#FFAA00"` for literal, `"palette:3"` for slot 3.
public enum ColorValue: Hashable, Sendable {
    case rgba(RGBA)
    case palette(Int)

    public func resolved(in palette: Palette) -> RGBA {
        switch self {
        case let .rgba(color):
            color
        case let .palette(slot):
            palette.color(at: slot)
        }
    }

    public var paletteSlot: Int? {
        if case let .palette(slot) = self { return slot }
        return nil
    }
}

extension ColorValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if string.hasPrefix("palette:"), let slot = Int(string.dropFirst("palette:".count)) {
            self = .palette(slot)
        } else if let color = RGBA(hex: string) {
            self = .rgba(color)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid color value \(string)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .rgba(color):
            try container.encode(color.hex)
        case let .palette(slot):
            try container.encode("palette:\(slot)")
        }
    }
}
