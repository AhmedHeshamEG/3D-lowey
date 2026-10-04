import CoreGraphics
import Foundation
import LoweyCore

/// Flipbook drawing: which track the Pencil draws into, draw or erase, the line, new drawings' hold and the onion
/// skin around the drawing at the playhead.
public struct FlipbookSettings: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case draw, erase

        public var id: String { rawValue }
        public var title: String { self == .draw ? "Draw" : "Erase" }
        public var systemImage: String { self == .draw ? "pencil.tip" : "eraser" }
    }

    /// The track the Pencil draws into (nil: the first stroke makes one).
    public var track: String?
    public var mode: Mode = .draw
    /// Half-width in points at full pressure.
    public var width: Double = 2.5
    public var opacity: Double = 1
    /// Frames a new drawing holds (2 = on twos).
    public var hold: Int = 2
    public var onionSkin = true
    public var onionBefore = 1
    public var onionAfter = 1
    /// Eraser radius in points.
    public var eraserRadius: Double = 14
    /// The stroke being drawn (stage points), shown until it lands in the drawing.
    public var livePoints: [CGPoint] = []

    public init() {}
}

/// The animation helpers drawn over the stage for the selection: its motion path with editable keys and the 3D onion
/// skin of its neighbouring keyed poses.
public struct AnimationViewSettings: Equatable, Sendable {
    public var motionPath = true
    public var onionSkin = false
    /// Keyed poses shown before and after the playhead.
    public var onionBefore = 2
    public var onionAfter = 1

    public init() {}
}
