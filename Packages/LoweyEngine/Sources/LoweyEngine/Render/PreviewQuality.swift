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

/// What the silent load meter does about load (CONTEXT §6): one tier lighter each time the meter says the device is
/// near its limit, one tier back after a calm stretch. A recovery that doesn't hold doubles the next wait, so a scene
/// on the edge settles on the lighter preview instead of going back and forth.
public struct AdaptivePreview: Sendable, Equatable {
    /// The device's own tier: the preview never gets better than this.
    public let home: DeviceTier
    public private(set) var tier: DeviceTier
    /// Seconds of calm before the preview goes one tier back.
    public private(set) var recoverAfter: Double
    private let firstWait: Double
    private var calmSince: Double?
    private var recoveredAt: Double?

    public init(home: DeviceTier, recoverAfter: Double = 20) {
        self.home = home
        tier = home
        self.recoverAfter = recoverAfter
        firstWait = recoverAfter
    }

    public var lightened: Bool { tier != home }

    /// Feeds the meter's level; returns the tier to preview at when it changes.
    public mutating func update(level: LoadMeter.Level, at time: Double) -> DeviceTier? {
        guard level == .comfortable else {
            calmSince = nil
            guard let lighter = Self.lighter(than: tier) else { return nil }
            if let recoveredAt, time - recoveredAt < firstWait { recoverAfter = min(recoverAfter * 2, 320) }
            recoveredAt = nil
            tier = lighter
            return tier
        }
        guard lightened else {
            if let recoveredAt, time - recoveredAt >= firstWait {
                self.recoveredAt = nil
                recoverAfter = firstWait
            }
            return nil
        }
        guard let since = calmSince else {
            calmSince = time
            return nil
        }
        guard time - since >= recoverAfter else { return nil }
        calmSince = nil
        recoveredAt = time
        tier = Self.heavier(than: tier) ?? home
        return tier
    }

    private static func lighter(than tier: DeviceTier) -> DeviceTier? {
        switch tier {
        case .a: .b
        case .b: .c
        case .c: nil
        }
    }

    private static func heavier(than tier: DeviceTier) -> DeviceTier? {
        switch tier {
        case .a: nil
        case .b: .a
        case .c: .b
        }
    }
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
