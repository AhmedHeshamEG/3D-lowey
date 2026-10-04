import HmmDesign
import HmmDiagnostics
import SwiftUI

/// The hidden load meter's chip: nothing at all while the iPad keeps up; near the limit, a calm line with the fixes
/// that help, before frames drop.
struct LoadChip: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        if editor.performance.load != .comfortable {
            HStack(spacing: HmmSpacing.s) {
                Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(theme.warning)
                Group {
                    if editor.performance.load == .over {
                        Text("This scene is more than this iPad keeps smooth")
                    } else {
                        Text("Close to what this iPad keeps smooth")
                    }
                }
                .font(.hmm(.footnote, weight: .semibold))
                if editor.fullResolutionStage {
                    HmmPillButton("Adaptive resolution") { editor.useAdaptiveResolution() }
                } else if !editor.previewIsLightest {
                    HmmPillButton("Lighter preview") { editor.lightenPreview() }
                        .accessibilityIdentifier("lighter-preview")
                }
            }
            .padding(.horizontal, HmmSpacing.m)
            .padding(.vertical, HmmSpacing.xs)
            .hmmGlass(in: Capsule(), interactive: false)
            .transition(.opacity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("load-chip")
        }
    }
}
