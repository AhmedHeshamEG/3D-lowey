import Foundation
import HmmDiagnostics
import LoweyEngine
import QuartzCore

/// The silent load meter (CONTEXT §6): near what this iPad keeps smooth, the preview lightens by itself and comes
/// back when there's room. Nothing is shown on the stage; the numbers are in Diagnostics. Only the preview changes:
/// exports always render at full quality.
extension EditorModel {
    /// Called with the stage's frames: follows the meter with the preview's render-scale range.
    func adaptPreview() {
        guard let stage, stage.dynamicScale.enabled else { return }
        guard let tier = adaptivePreview.update(level: performance.load, at: CACurrentMediaTime()) else { return }
        let range = PreviewQuality(tier: tier).renderScale
        stage.dynamicScale.range = range
        stage.dynamicScale.scale = min(max(stage.dynamicScale.scale, range.lowerBound), range.upperBound)
        // The frames measured so far were drawn in the old range.
        performance.settle()
    }

    /// Diagnostics ▸ Smoothness: how full this iPad's frame is, and what the preview is doing about it.
    var loadSummary: LoadSummary {
        LoadSummary(percent: Int((performance.pressure * 100).rounded()), lightened: adaptivePreview.lightened,
                    scale: Int((performance.renderScale * 100).rounded()))
    }
}

struct LoadSummary: Equatable {
    var percent: Int
    var lightened: Bool
    var scale: Int
}
