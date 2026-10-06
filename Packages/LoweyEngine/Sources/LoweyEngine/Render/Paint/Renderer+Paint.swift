import Foundation
import LoweyCore
import Metal
import simd

/// Painting on models, as the stage reaches it: the stroke drawn in the frame that shows it, and what a finished stroke
/// changed read back for the document.
public extension LoweyRenderer {
    /// The stage streams paint tiles a few per frame; snapshots and exports load every tile before drawing.
    var streamsPaint: Bool {
        get { paints.streams }
        set { paints.streams = newValue }
    }

    /// Paint tiles are still on their way (the stage should draw again).
    var wantsAnotherFrame: Bool { paints.wantsAnotherFrame }

    /// Called when paint carried onto a changed shape is ready (any thread).
    var onNeedsFrame: (@Sendable () -> Void)? {
        get { paints.onNeedsFrame }
        set { paints.onNeedsFrame = newValue }
    }

    /// Drops every painted layer the GPU holds (they load again from the document's tiles): a cancelled stroke.
    func forgetPaint() {
        paints.forget()
    }

    /// The tiles a stroke wrote are in its layer already: the document's next state needs no decoding.
    func adoptPaint(object: ObjectID, layer: String, changes: [PaintTileChange]) {
        paints.adopt(object: object, layer: layer, changes: changes)
    }

    internal func encodeLivePaint(_ live: LivePaint, request: FrameRequest, scene: RenderScene, camera: RenderCamera, viewProjection: simd_float4x4,
                                  targets: FrameTargets, commandBuffer: MTLCommandBuffer) {
        guard let item = scene.items.first(where: { $0.painted == live.object && !$0.ghost }) else { return }
        // The index the ID buffer holds for this object (`ObjectUniforms.ids.x`).
        let view = PaintTextures.StrokeView(item: item, objectIndex: item.uniforms.ids.x, camera: camera, viewProjection: viewProjection,
                                            ids: targets.ids, depth: targets.depth)
        paints.encodeStroke(live, view: view, stamper: stamper, image: request.input.mediaImage, commandBuffer: commandBuffer)
    }

    /// Encodes reading the last stroke back (its layer now and before it); nil when nothing was painted.
    internal func paintStrokeReadback() -> PaintTextures.StrokeReadback? {
        paints.strokeReadback(queue: device.queue)
    }
}
