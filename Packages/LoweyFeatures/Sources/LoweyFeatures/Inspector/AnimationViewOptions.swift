import HmmDesign
import LoweyCore
import SwiftUI

/// Motion helpers: the motion path and the 3D onion skin on the stage, and smears on fast moves.
struct AnimationViewOptions: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            Toggle("Motion path", isOn: $editor.animationView.motionPath)
                .accessibilityHint("Shows the arc the selection travels; drag a dot to move its key")
            Toggle("Onion skin", isOn: $editor.animationView.onionSkin)
                .accessibilityHint("Shows the selection at its neighbouring keys, earlier in red, later in green")
            if editor.animationView.onionSkin {
                Stepper("Keys before: \(editor.animationView.onionBefore)", value: $editor.animationView.onionBefore, in: 0 ... 4)
                Stepper("Keys after: \(editor.animationView.onionAfter)", value: $editor.animationView.onionAfter, in: 0 ... 4)
            }
            LabeledSlider(title: "Smear on fast moves", value: editor.singleSelection?[.smear]?.floatValue ?? 0, range: 0 ... 1,
                          format: { $0 < 0.01 ? "Off" : NumberFormat.percent($0) },
                          set: { editor.setSmear($0) }, done: { editor.endGesture() })
        }
        .font(.hmm(.body))
    }
}
