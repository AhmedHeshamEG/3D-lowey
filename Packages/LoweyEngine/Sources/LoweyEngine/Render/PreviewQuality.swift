import HmmDiagnostics

/// What the stage's preview costs on this device (CONTEXT §6). Tiers lower preview quality, never features: every
/// tier has the same tools and Looks, and exports always render with `.full`, just slower on a smaller iPad.
///
/// - Render scale: the range the dynamic scale moves in (lines and overlays always stay native, so edges stay crisp).
/// - Shadows: the sun's shadow map.
/// - Frame budget: the screen's own refresh (8.3 ms on ProMotion, 16.7 ms elsewhere), set by the stage.
public struct PreviewQuality: Sendable, Equatable {
    public var tier: DeviceTier
    public var renderScale: ClosedRange<Float>
    public var shadowMapSize: Int

    public init(tier: DeviceTier) {
        self.tier = tier
        switch tier {
        case .a:
            renderScale = DynamicScale.minimum ... 1
            shadowMapSize = 2048
        case .b:
            renderScale = 0.6 ... 0.85
            shadowMapSize = 1536
        case .c:
            renderScale = 0.5 ... 0.7
            shadowMapSize = 1024
        }
    }

    /// Exports, stills, thumbnails and tests: everything at full quality.
    public static let full = PreviewQuality(tier: .a)

    /// This device's preview (or the tier forced with `-device-tier`).
    public static let current = PreviewQuality(tier: DeviceTier.current())
}

/// A scene's estimated cost for a tier: 1 = what that tier draws comfortably inside its frame. The comfortable
/// amounts are first estimates from the Night Market on an M3 iPad; the device benchmarks of each phase refine them.
public enum SceneCost {
    public static func comfortable(_ tier: DeviceTier) -> (triangles: Double, drawCalls: Double) {
        switch tier {
        case .a: (2_000_000, 2000)
        case .b: (800_000, 900)
        case .c: (350_000, 450)
        }
    }

    public static func estimate(_ report: FrameReport, tier: DeviceTier) -> Double {
        let comfortable = comfortable(tier)
        return max(Double(report.triangles) / comfortable.triangles, Double(report.drawCalls) / comfortable.drawCalls)
    }
}
