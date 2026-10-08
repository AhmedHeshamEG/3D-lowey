import Foundation
import HmmDocuments

/// Content keys: the same brush or picture always gets the same key, so a document stores each brush once however
/// many strokes use it, and an edited brush is a new key (old strokes keep the old one).
public enum BrushKey {
    /// The folder tip and grain pictures live in, in a brush library and under a document's assets.
    public static let imagesFolder = "brushes"

    public static func imageKey(for data: Data) -> String {
        "\(imagesFolder)/\(hex(fnv(data))).png"
    }

    /// The key a document stores a brush under (its settings and pictures, not its place in the library).
    public static func key(for brush: Brush) -> String {
        var frozen = brush.clamped
        frozen.id = ""
        let data = (try? HmmJSON.encode(frozen)) ?? Data(brush.id.utf8)
        return "b-" + hex(fnv(data))
    }

    public static func fnv(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    public static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: max(16 - digits.count, 0)) + digits
    }
}

/// The brush a stroke names, from the document's frozen copies (Ink Pen when it names none, or one that's missing).
public enum BrushResolver {
    public static func brush(_ key: String?, in brushes: [String: Brush]) -> Brush {
        key.flatMap { brushes[$0] } ?? BuiltInBrushes.inkPen
    }
}
