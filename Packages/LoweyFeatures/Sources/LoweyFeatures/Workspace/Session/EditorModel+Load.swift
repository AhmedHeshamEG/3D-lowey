import Foundation
import HmmDiagnostics
import LoweyEngine

/// The load meter's one-tap fixes (CONTEXT §6). They change only the preview: exports always render at full quality.
extension EditorModel {
    /// The preview is already as light as it gets.
    var previewIsLightest: Bool {
        guard let stage else { return true }
        return stage.dynamicScale.range.upperBound <= PreviewQuality(tier: .c).renderScale.upperBound
    }

    /// Full-resolution stage (Settings) is on: turning it off is the biggest saving.
    var fullResolutionStage: Bool { UserDefaults.standard.bool(forKey: AppSettings.fullResolutionStage) }

    /// One tier lighter for the rest of this session.
    func lightenPreview() {
        guard let stage else { return }
        let lighter: DeviceTier = stage.dynamicScale.range.upperBound > PreviewQuality(tier: .b).renderScale.upperBound ? .b : .c
        stage.dynamicScale.range = PreviewQuality(tier: lighter).renderScale
        stage.dynamicScale.scale = min(stage.dynamicScale.scale, stage.dynamicScale.range.upperBound)
        performance.reset()
        app.show("Lighter preview for this session. Exports stay at full quality.")
    }

    func useAdaptiveResolution() {
        UserDefaults.standard.set(false, forKey: AppSettings.fullResolutionStage)
        stage?.dynamicScale.enabled = true
        performance.reset()
        app.show("The stage now adapts its resolution to stay smooth.")
    }
}
