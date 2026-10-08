import Foundation
import HmmBrush

/// The canvas keeps the board drawn in one picture (the layer) a little larger than the screen, and shows that
/// picture moved and scaled while fingers pan and pinch. This decides when the picture still serves and when it must
/// be drawn again, so a board of thousands of strokes moves as smoothly as an empty one.
public struct BoardLayerPlan: Hashable, Sendable {
    /// The part of the board the layer holds.
    public var region: BoardRect
    public var pixelsPerUnit: Double

    public init(region: BoardRect, pixelsPerUnit: Double) {
        self.region = region
        self.pixelsPerUnit = pixelsPerUnit
    }

    /// How much more than the screen a layer holds on every side (a quarter of the screen).
    public static let margin = 0.25

    /// A fresh layer for a view: what is visible and the margin around it.
    public init(visible: BoardRect, pixelsPerUnit: Double) {
        region = BoardRect(center: visible.center, width: visible.width * (1 + Self.margin * 2), height: visible.height * (1 + Self.margin * 2))
        self.pixelsPerUnit = pixelsPerUnit
    }

    /// Whether this layer can show `visible` at `pixelsPerUnit`. At rest it must be exactly as sharp as the screen;
    /// while fingers move it may be stretched up to twice or shrunk to half.
    public func serves(visible: BoardRect, pixelsPerUnit: Double, interacting: Bool) -> Bool {
        guard region.contains(visible), self.pixelsPerUnit > 0 else { return false }
        let ratio = pixelsPerUnit / self.pixelsPerUnit
        return interacting ? (0.5 ... 2).contains(ratio) : abs(ratio - 1) < 0.001
    }

    /// The layer's size in pixels.
    public var pixelWidth: Int { max(Int((region.width * pixelsPerUnit).rounded(.up)), 1) }
    public var pixelHeight: Int { max(Int((region.height * pixelsPerUnit).rounded(.up)), 1) }
}
