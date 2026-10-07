#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation

/// Which side of a target a floating panel sits on, in screen space (left and right as the glass shows them).
public enum HmmFloatingSide: String, Sendable, Codable {
    case left, right

    public var flipped: HmmFloatingSide { self == .left ? .right : .left }
}

/// Where a floating panel goes so it sits beside what it's about without covering it: an inspector beside the
/// selection, a popover beside a tapped thing. Pure geometry in screen points, so it's tested anywhere.
///
/// The panel keeps the side it's on while it fits there (no flapping as the target moves) and flips when the edge of
/// the screen leaves no room. When neither side fits, it takes the side with more room and covers as little of the
/// target as it can. Vertically it centres on the target and stays inside the bounds.
public enum HmmFloatingPlacement {
    public struct Result: Equatable, Sendable {
        public var frame: CGRect
        public var side: HmmFloatingSide
        /// How much of the target the panel covers, 0 … 1 (zero whenever one side had room).
        public var coverage: Double
    }

    public static func place(_ size: CGSize, beside target: CGRect, in bounds: CGRect, current: HmmFloatingSide = .right,
                             gap: CGFloat = 12) -> Result {
        let width = min(size.width, bounds.width)
        let height = min(size.height, bounds.height)
        let roomRight = bounds.maxX - target.maxX - gap
        let roomLeft = target.minX - bounds.minX - gap
        let side: HmmFloatingSide = if room(on: current, left: roomLeft, right: roomRight) >= width {
            current
        } else if room(on: current.flipped, left: roomLeft, right: roomRight) >= width {
            current.flipped
        } else {
            roomRight >= roomLeft ? .right : .left
        }
        let preferredX = side == .right ? target.maxX + gap : target.minX - gap - width
        let x = clamp(preferredX, bounds.minX, bounds.maxX - width)
        let y = clamp(target.midY - height / 2, bounds.minY, bounds.maxY - height)
        let frame = CGRect(x: x, y: y, width: width, height: height)
        return Result(frame: frame, side: side, coverage: coverage(of: target, by: frame))
    }

    /// With nothing to sit beside (the target is off screen or unknown): against the edge of `side`, from the top.
    public static func docked(_ size: CGSize, in bounds: CGRect, side: HmmFloatingSide = .right) -> CGRect {
        let width = min(size.width, bounds.width)
        let height = min(size.height, bounds.height)
        return CGRect(x: side == .right ? bounds.maxX - width : bounds.minX, y: bounds.minY, width: width, height: height)
    }

    /// The box around projected points (a selection's corners on screen); nil when none landed on screen.
    public static func bounds(of points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var box = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() {
            box = box.union(CGRect(origin: point, size: .zero))
        }
        return box
    }

    private static func room(on side: HmmFloatingSide, left: CGFloat, right: CGFloat) -> CGFloat {
        side == .right ? right : left
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        max(low, min(value, max(low, high)))
    }

    private static func coverage(of target: CGRect, by frame: CGRect) -> Double {
        let area = target.width * target.height
        guard area > 0 else { return frame.contains(CGPoint(x: target.midX, y: target.midY)) ? 1 : 0 }
        let overlap = target.intersection(frame)
        guard !overlap.isNull else { return 0 }
        return Double(overlap.width * overlap.height / area)
    }
}
