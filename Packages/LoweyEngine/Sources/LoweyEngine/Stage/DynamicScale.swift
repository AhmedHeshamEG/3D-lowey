import Foundation
import HmmDiagnostics

/// Keeps the stage inside its frame budget by lowering the shaded image's resolution (0.66…1) before frames drop,
/// and raising it again when there's room. Lines and overlays stay native, so edges stay crisp. Under a serious
/// thermal state it caps the scale; export never uses it (always 1).
public struct DynamicScale: Sendable, Equatable {
    public static let minimum: Float = 0.66
    public var scale: Float = 1
    /// Frame budget in seconds (1/120 on ProMotion).
    public var budget: Double
    /// Off: always 1 (Settings ▸ Full-resolution stage, and tests).
    public var enabled = true
    private var calm = 0

    public init(budget: Double = 1.0 / 120.0) {
        self.budget = budget
    }

    /// Feeds one GPU frame time; returns the scale for the next frame.
    public mutating func update(gpuTime: Double, thermal: ThermalLevel) -> Float {
        guard enabled else {
            scale = 1
            return scale
        }
        let cap: Float = thermal >= .critical ? Self.minimum : (thermal >= .serious ? 0.75 : 1)
        if gpuTime > budget * 0.92 {
            scale = max(scale - 0.05, Self.minimum)
            calm = 0
        } else if gpuTime < budget * 0.7 {
            calm += 1
            if calm >= 30 {
                scale = min(scale + 0.05, 1)
                calm = 0
            }
        } else {
            calm = 0
        }
        scale = min(scale, cap)
        return scale
    }
}
