import Foundation
import HmmDiagnostics

/// Keeps the stage inside its frame budget by lowering the shaded image's resolution (0.66…1) before frames drop,
/// and raising it again when there's room. Lines and overlays stay native, so edges stay crisp. Under a serious
/// thermal state it caps the scale; export never uses it (always 1).
public struct DynamicScale: Sendable, Equatable {
    public static let minimum: Float = 0.66
    public var scale: Float = 1
    /// Frame budget in seconds (1/120 on ProMotion, 1/60 elsewhere).
    public var budget: Double
    /// Where the scale moves (the device tier's preview range; `PreviewQuality`).
    public var range: ClosedRange<Float>
    /// Off: always 1, whatever the tier (Settings ▸ Full-resolution stage, and tests).
    public var enabled = true
    private var calm = 0

    public init(budget: Double = 1.0 / 120.0, range: ClosedRange<Float> = DynamicScale.minimum ... 1) {
        self.budget = budget
        self.range = range
        scale = range.upperBound
    }

    /// Feeds one GPU frame time; returns the scale for the next frame.
    public mutating func update(gpuTime: Double, thermal: ThermalLevel) -> Float {
        guard enabled else {
            scale = 1
            return scale
        }
        // Thermal `.serious` lowers the preview before frames drop (CONTEXT §6).
        let span = range.upperBound - range.lowerBound
        let cap: Float = thermal >= .critical ? range.lowerBound : (thermal >= .serious ? range.lowerBound + span * 0.25 : range.upperBound)
        if gpuTime > budget * 0.92 {
            scale = max(scale - 0.05, range.lowerBound)
            calm = 0
        } else if gpuTime < budget * 0.7 {
            calm += 1
            if calm >= 30 {
                scale = min(scale + 0.05, range.upperBound)
                calm = 0
            }
        } else {
            calm = 0
        }
        scale = min(scale, cap)
        return scale
    }
}
