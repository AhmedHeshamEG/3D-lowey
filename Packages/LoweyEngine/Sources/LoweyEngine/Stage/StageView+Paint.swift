import Foundation
import LoweyCore
import Metal

/// Painting on models from the stage: the stroke drawn by the frame that shows it, and what it changed read back.
public extension StageView {
    /// The stroke being painted on a model, drawn into its layer by the next frame (nil when it stops).
    func showLivePaint(_ paint: LivePaint?) {
        livePaint = paint
        if paint != nil { liveStrokeTouch = nil }
        redraw()
    }

    /// The tiles the last painted stroke changed, read back from the GPU after its last frame (nil when it changed
    /// nothing). The stroke must have stopped (`showLivePaint(nil)`) first.
    func finishPaintStroke() async -> PaintedTiles? {
        guard let readback = renderer.paintStrokeReadback() else { return nil }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            readback.commandBuffer.addCompletedHandler { _ in continuation.resume() }
            readback.commandBuffer.commit()
        }
        let after = readback.bytes(readback.after), before = readback.bytes(readback.before)
        let size = readback.size, object = readback.object, layer = readback.layer
        return await Task.detached(priority: .userInitiated) {
            let tiles = PaintPixels.changedTiles(after: after, before: before, size: size)
            return tiles.isEmpty ? nil : PaintedTiles(object: object, layer: layer, tiles: tiles)
        }.value
    }
}
