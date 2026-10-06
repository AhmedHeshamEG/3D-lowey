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

    /// Ends the painted stroke: its layer is copied for reading now (before any later frame paints on it), and the
    /// task yields the tiles it changed (nil when it changed nothing). Call after the stroke's last frame was drawn.
    func finishPaintStroke() -> Task<PaintedTiles?, Never>? {
        livePaint = nil
        guard let readback = renderer.paintStrokeReadback() else { return nil }
        let (done, signal) = AsyncStream<Void>.makeStream()
        readback.commandBuffer.addCompletedHandler { _ in
            signal.yield()
            signal.finish()
        }
        readback.commandBuffer.commit()
        return Task { @MainActor in
            for await _ in done {}
            let after = readback.bytes(readback.after), before = readback.bytes(readback.before)
            let size = readback.size, object = readback.object, layer = readback.layer
            return await Task.detached(priority: .userInitiated) {
                let tiles = PaintPixels.changedTiles(after: after, before: before, size: size)
                return tiles.isEmpty ? nil : PaintedTiles(object: object, layer: layer, tiles: tiles)
            }.value
        }
    }
}
