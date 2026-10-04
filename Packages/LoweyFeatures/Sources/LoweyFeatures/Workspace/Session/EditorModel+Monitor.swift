import CoreGraphics
import LoweyCore
import LoweyEngine

/// The monitor: the shot exactly as it will export (shot camera, overlays, flipbooks, screen effects), live, in a
/// window of its own — beside the editor in Stage Manager, or on an external display.
extension EditorModel {
    func monitorFrame(for view: StageView) -> StageFrame? {
        let scale = view.contentScaleFactor
        let size = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
        guard size.width > 1, size.height > 1 else { return nil }
        let builder = ShotBuilder(document: displayDocument, catalog: library.catalog, models: library.models)
        builder.mediaImage = { [weak self] key in self?.mediaImage(key) }
        let framing: Framing = size.width >= size.height ? .landscape : .portrait
        let request = builder.request(at: time, framing: framing, size: size, frameIndex: timeline.frame(for: time), animated: displayed)
        return StageFrame(request: request, shotCamera: request.camera)
    }

    /// The name of the camera the monitor looks through now.
    var monitorCaption: String {
        shotCamera.flatMap { displayed.scene.objects[$0]?.name } ?? baseScene.name
    }
}
