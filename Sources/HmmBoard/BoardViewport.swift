import Foundation
import HmmBrush

/// Where on the endless board the screen is looking, and how closely. Screen sizes and points are in points, from
/// the view's top left.
public struct BoardViewport: Hashable, Sendable, Codable {
    /// The board point in the middle of the screen.
    public var center: Vec2
    /// Screen points per board unit (1 = 100 %).
    public var scale: Double

    /// From a whole wall of sketches (5 %) down to a detail (3200 %).
    public static let scaleRange = 0.05 ... 32.0

    public init(center: Vec2 = .zero, scale: Double = 1) {
        self.center = center
        self.scale = scale.clamped(Self.scaleRange.lowerBound, Self.scaleRange.upperBound)
    }

    public func toScreen(_ point: Vec2, size: Vec2) -> Vec2 {
        (point - center) * scale + size * 0.5
    }

    public func toBoard(_ point: Vec2, size: Vec2) -> Vec2 {
        (point - size * 0.5) * (1 / scale) + center
    }

    /// The part of the board a view of `size` shows.
    public func visibleRect(size: Vec2) -> BoardRect {
        BoardRect(center: center, width: size.x / scale, height: size.y / scale)
    }

    /// The board follows the fingers: dragging right brings what was on the left into view.
    public func panned(byScreen delta: Vec2) -> BoardViewport {
        BoardViewport(center: center - delta * (1 / scale), scale: scale)
    }

    /// Zooms by `factor`, keeping the board point under `screenPoint` (between the fingers) where it is.
    public func zoomed(by factor: Double, around screenPoint: Vec2, size: Vec2) -> BoardViewport {
        let anchor = toBoard(screenPoint, size: size)
        var zoomed = BoardViewport(center: center, scale: scale * factor)
        zoomed.center = anchor - (screenPoint - size * 0.5) * (1 / zoomed.scale)
        return zoomed
    }

    /// The view that shows all of `rect` with `padding` points around it (never closer than 100 % for something
    /// small, so framing a single note doesn't blow it up).
    public static func fitting(_ rect: BoardRect, size: Vec2, padding: Double = 64) -> BoardViewport {
        let room = Vec2(max(size.x - padding * 2, 1), max(size.y - padding * 2, 1))
        let scale = min(room.x / max(rect.width, 1e-6), room.y / max(rect.height, 1e-6), 1)
        return BoardViewport(center: rect.center, scale: scale)
    }

    /// "100 %".
    public var percentText: String { "\(Int((scale * 100).rounded())) %" }
}
