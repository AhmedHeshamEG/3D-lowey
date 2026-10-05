import Foundation
import LoweyCore

/// What a tap does with the Model tool on the stage: pick faces, edges or corners, or draw a sketch shape.
enum ModelingMode: Hashable, Sendable {
    case pick(MeshSelection.Mode)
    case sketch(SketchKind)

    var sketchKind: SketchKind? {
        if case let .sketch(kind) = self { return kind }
        return nil
    }

    var pickMode: MeshSelection.Mode? {
        if case let .pick(mode) = self { return mode }
        return nil
    }
}

/// The sketch shapes, in the order the bar shows them.
enum SketchKind: String, CaseIterable, Identifiable, Sendable {
    case line, rectangle, circle, arc, spline, offset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .circle: "Circle"
        case .arc: "Arc"
        case .spline: "Spline"
        case .offset: "Offset"
        }
    }

    var systemImage: String {
        switch self {
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .circle: "circle"
        case .arc: "circle.bottomhalf.filled"
        case .spline: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .offset: "square.on.square"
        }
    }

    /// What to do next, in a few words (shown while drawing), after `points` taps.
    func hint(points: Int) -> String {
        switch points {
        case 0: hint
        case 1: caption
        default: explanation
        }
    }

    /// Before the first tap.
    var hint: String {
        switch self {
        case .line: "Tap where the line starts"
        case .rectangle: "Tap one corner"
        case .circle: "Tap the centre"
        case .arc: "Tap where the arc starts"
        case .spline: "Tap where the curve starts"
        case .offset: "Tap a line of a sketch to offset it"
        }
    }

    /// After the first tap.
    var caption: String {
        switch self {
        case .line: "Tap the next corner. Tap the first one to close"
        case .rectangle: "Tap the opposite corner"
        case .circle: "Tap the edge"
        case .arc: "Tap where it ends"
        case .spline: "Tap through the curve. Tap the start to close"
        case .offset: "Tap a line of a sketch to offset it"
        }
    }

    /// After the second tap.
    var explanation: String {
        switch self {
        case .arc: "Tap how far it bends"
        default: caption
        }
    }
}

/// A region of a sketch object (by index into `Sketch.regions`).
struct SketchRegionRef: Hashable, Sendable {
    var sketch: ObjectID
    var index: Int
}

/// A curve of a sketch object (by index into `Sketch.curves`).
struct SketchCurveRef: Hashable, Sendable {
    var sketch: ObjectID
    var index: Int
}

/// The shape being drawn: its plane, what it's drawn on, the sketch it joins and the taps so far.
struct PendingSketch: Sendable {
    var plane: PlaneFrame
    var target: ObjectID?
    /// An existing sketch on the same plane and object (new curves join it, so their regions combine).
    var sketch: ObjectID?
    var points: [Vec2]
}

/// A number on the stage you can tap to type.
enum DimensionField: Hashable, Sendable {
    /// How far the picked face or region is pulled (or pushed, negative).
    case pull
    /// A side of the rectangle just drawn (`horizontal` is its first side).
    case rectangleSide(horizontal: Bool)
    case diameter
    case lineLength
    case offset
}

/// The Model tool's state on the stage. View state, not the document: none of it is undone or saved.
struct ModelingState: Sendable {
    var mode: ModelingMode = .pick(.face)
    /// The object whose faces, edges or corners are picked.
    var target: ObjectID?
    var elements: MeshSelection?
    var region: SketchRegionRef?
    var pending: PendingSketch?
    /// The curve just drawn: its sizes float beside it, ready to type.
    var lastCurve: SketchCurveRef?
    /// The curve picked to offset.
    var offsetSource: SketchCurveRef?
    /// The push/pull distance while dragging (metres along the normal).
    var pull: Double?
    var editing: DimensionField?

    /// What the stage's marks depend on (they're rebuilt when it changes).
    var overlayKey: [AnyHashable] {
        [AnyHashable(mode), AnyHashable(target), AnyHashable(elements), AnyHashable(region), AnyHashable(pending?.points),
         AnyHashable(pull), AnyHashable(offsetSource)]
    }

    var hasPick: Bool { region != nil || (elements.map { !$0.isEmpty } ?? false) }

    mutating func clearPick() {
        elements = nil
        region = nil
        pull = nil
        editing = nil
    }
}
