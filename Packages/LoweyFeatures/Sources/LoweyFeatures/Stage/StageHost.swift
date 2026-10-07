import LoweyEngine
import SwiftUI
import UIKit

/// The Metal stage inside SwiftUI, with its touch handling. One stage per open project.
struct StageHost: UIViewRepresentable {
    let editor: EditorModel

    func makeCoordinator() -> Holder { Holder() }

    func makeUIView(context: Context) -> UIView {
        guard let stage = try? StageView(device: RenderDevice.sharedDevice()) else {
            let fallback = UILabel()
            fallback.text = "This device can't run the 3D stage (no Metal GPU)."
            fallback.textAlignment = .center
            fallback.textColor = .secondaryLabel
            return fallback
        }
        stage.accessibilityIdentifier = "stage"
        stage.isAccessibilityElement = true
        stage.accessibilityLabel = "Stage"
        editor.attach(stage)
        context.coordinator.gestures = StageGestures(editor: editor, stage: stage)
        return stage
    }

    func updateUIView(_: UIView, context: Context) {
        // Touch routing follows the tool (the Pencil paints only with a painting tool).
        _ = editor.tool
        context.coordinator.gestures?.updateTouchTypes()
    }

    final class Holder {
        var gestures: StageGestures?
    }
}
