import Foundation

/// The hmm. design tokens as plain values (no UI framework), so every platform and every test sees the same numbers.
/// `Color`/`Font`/`Animation` wrappers live in the SwiftUI files.

/// An sRGB colour as 0…1 components.
public struct HmmRGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `0xRRGGBB`.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha)
    }

    /// Relative luminance (WCAG), for contrast checks.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// HSB saturation (0 = grey).
    public var saturation: Double {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        return high <= 0 ? 0 : (high - low) / high
    }

    /// WCAG contrast ratio between two colours (1…21).
    public static func contrast(_ a: HmmRGB, _ b: HmmRGB) -> Double {
        let high = max(a.luminance, b.luminance)
        let low = min(a.luminance, b.luminance)
        return (high + 0.05) / (low + 0.05)
    }
}

/// Light or dark neutrals.
public enum HmmAppearance: String, Sendable, CaseIterable, Identifiable {
    case dark, light

    public var id: String { rawValue }
}

/// The neutral ramp for one appearance.
public struct HmmNeutrals: Hashable, Sendable {
    public var background: HmmRGB
    public var surface: HmmRGB
    public var surface2: HmmRGB
    public var line: HmmRGB
    public var text: HmmRGB
    public var text2: HmmRGB
    public var text3: HmmRGB

    public static let dark = HmmNeutrals(
        background: HmmRGB(hex: 0x0E0F11), surface: HmmRGB(hex: 0x16171A), surface2: HmmRGB(hex: 0x1E1F23), line: HmmRGB(hex: 0x2A2B30),
        text: HmmRGB(hex: 0xEDEDEF), text2: HmmRGB(hex: 0x9A9AA3), text3: HmmRGB(hex: 0x5E5F66)
    )

    public static let light = HmmNeutrals(
        background: HmmRGB(hex: 0xF5F5F7), surface: HmmRGB(hex: 0xFFFFFF), surface2: HmmRGB(hex: 0xEDEDF0), line: HmmRGB(hex: 0xD9D9DE),
        text: HmmRGB(hex: 0x1D1D1F), text2: HmmRGB(hex: 0x6E6E73), text3: HmmRGB(hex: 0xA1A1A6)
    )

    public static func `for`(_ appearance: HmmAppearance) -> HmmNeutrals {
        appearance == .dark ? dark : light
    }
}

/// Semantic colours shared by every app. Record and danger are the same red on purpose: both mean "careful".
public enum HmmSemantic {
    public static let record = HmmRGB(hex: 0xFF453A)
    public static let success = HmmRGB(hex: 0x30D158)
    public static let warning = HmmRGB(hex: 0xFF9F0A)
    public static let danger = HmmRGB(hex: 0xFF453A)
}

/// One accent per app. It marks the active thing and nothing else.
public enum HmmAccent: String, Sendable, CaseIterable {
    case lowey, retake, editoro

    public var rgb: HmmRGB {
        switch self {
        case .lowey: HmmRGB(hex: 0xFFB847)
        case .retake: HmmRGB(hex: 0xFF6B4A)
        case .editoro: HmmRGB(hex: 0x8B7CFF)
        }
    }
}

/// 4-point grid.
public enum HmmSpacing {
    public static let xxs: Double = 4
    public static let xs: Double = 8
    public static let s: Double = 12
    public static let m: Double = 16
    public static let l: Double = 24
    public static let xl: Double = 32
    public static let xxl: Double = 48
    public static let all: [Double] = [xxs, xs, s, m, l, xl, xxl]
}

/// Corner radii (always drawn with the continuous curve).
public enum HmmRadius {
    public static let control: Double = 8
    public static let card: Double = 14
    public static let panel: Double = 22
}

/// Minimum touch targets.
public enum HmmTarget {
    public static let minimum: Double = 44
    public static let primary: Double = 52
}

/// The type scale in points.
public enum HmmTypeScale: Double, Sendable, CaseIterable {
    case caption = 11
    case footnote = 13
    case body = 15
    case headline = 17
    case title3 = 22
    case title2 = 28
    case title1 = 34
}

/// Spring parameters of the three motion tokens. Heavy things move slowly, light things snap.
public struct HmmSpring: Hashable, Sendable {
    public var response: Double
    public var damping: Double

    /// Toggles, selection.
    public static let snappy = HmmSpring(response: 0.25, damping: 0.90)
    /// Panels, sheets.
    public static let standard = HmmSpring(response: 0.35, damping: 0.86)
    /// Large layout changes.
    public static let gentle = HmmSpring(response: 0.50, damping: 0.90)
    /// With Reduce Motion every token becomes a cross-fade of this length.
    public static let reducedMotionFade = 0.2
}
