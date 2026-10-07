import Foundation
import LoweyCore
import LoweyEngine

/// What a touch on the stage does (fingers always navigate unless a tool says otherwise).
public enum StageTool: String, CaseIterable, Identifiable, Sendable {
    /// Tap to select, drag a selection to move it, gizmo handles.
    case select
    /// Draw a loop around things to select them.
    case lasso
    /// Ink strokes: pressure lines in 3D that always face the camera (draw, erase, select strokes).
    case ink
    /// Solid shapes drawn in 3D (tube, ribbon, extrude, lathe) on a guide.
    case draw
    /// Paint shadow shapes onto a surface (push the shadow in or pull it out).
    case shadowBrush
    /// Frame-by-frame 2D drawing over the shot (flipbook tracks).
    case flipbook
    /// Drag on the ground to scatter copies of the selection.
    case scatter
    /// Model ▸ Edit: pick faces, edges and corners, push/pull, sketch on surfaces (`ModelingState`).
    case model
    /// Paint ▸ Colour: colour painted on models with the brush engine (`ColourPaintSettings`).
    case paint
    /// Cast ▸ Rig: bones drawn through an object, weights painted, the person rig's dots (`RigSettings`).
    case rig

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .select: "Select"
        case .lasso: "Lasso"
        case .ink: "Ink"
        case .draw: "Solid shape"
        case .shadowBrush: "Shadow Brush"
        case .flipbook: "Flipbook"
        case .scatter: "Scatter"
        case .model: "Shape"
        case .paint: "Colour"
        case .rig: "Rig"
        }
    }

    public var systemImage: String {
        switch self {
        case .select: "hand.point.up.left"
        case .lasso: "lasso"
        case .ink: "pencil.tip"
        case .draw: "scribble.variable"
        case .shadowBrush: "circle.lefthalf.striped.horizontal"
        case .flipbook: "book.pages"
        case .scatter: "circle.hexagongrid"
        case .model: "cube.transparent"
        case .paint: "paintbrush.pointed"
        case .rig: "figure.walk.motion"
        }
    }

    /// Tools where the Pencil (and, if allowed, a finger) paints instead of navigating.
    public var paints: Bool { self == .ink || self == .draw || self == .shadowBrush || self == .flipbook || self == .paint || self == .rig }

    /// The Draw tools (top right: Draw).
    public var draws: Bool { self == .ink || self == .draw || self == .flipbook }

    /// The Paint tools (top right: Paint): on objects and over the ground.
    public var paintsSurfaces: Bool { self == .shadowBrush || self == .scatter || self == .paint }

    /// Tools whose strokes take the colour in the hand (the sidebar shows its colour well for them). The Shadow
    /// Brush isn't one: it moves the Look's own shadow.
    public var putsColourDown: Bool { self == .ink || self == .draw || self == .flipbook || self == .paint }

    /// Tools that draw on a guide surface.
    public var usesGuide: Bool { self == .ink || self == .draw }
}

/// The floating panels the corner clusters open. One at a time; tapping its button again closes it. Animate, the
/// fourth making tool, has no panel: it calls the timeline (docs/LAYOUT.md).
public enum ClusterPanel: String, Identifiable, Sendable {
    // Top-left: document and app.
    case actions, look, select
    // Top-right: making.
    case model, draw, paint, cast

    public var id: String { rawValue }

    public var isLeading: Bool {
        switch self {
        case .actions, .look, .select: true
        default: false
        }
    }
}

/// The Model panel's pages: things to add, shaping (sketch, push/pull, booleans), the library of models, snapping.
public enum ModelPage: String, CaseIterable, Identifiable, Sendable {
    case add, shape, library, precision

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .add: "Add"
        case .shape: "Edit"
        case .library: "Library"
        case .precision: "Precision"
        }
    }

    public var systemImage: String {
        switch self {
        case .add: "plus"
        case .shape: "cube.transparent"
        case .library: "books.vertical"
        case .precision: "ruler"
        }
    }
}

/// Sheets over the editor (one at a time).
public enum EditorSheet: String, Identifiable, Sendable {
    case export, audio, transcript, scripts, bridge, blobBuilder, characterBuilder, settings, diagnostics, gestures, timelineSettings
    /// The brush library (and Brush Studio) for the drawing tool in `EditorModel.brushTool`.
    case brushes

    public var id: String { rawValue }
}

/// What the solid-shape tool draws on.
public enum GuideKind: String, CaseIterable, Identifiable, Sendable {
    case plane, box, cylinder, sphere, object

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plane: "Plane"
        case .box: "Box"
        case .cylinder: "Cylinder"
        case .sphere: "Sphere"
        case .object: "On object"
        }
    }

    public var systemImage: String {
        switch self {
        case .plane: "square.grid.3x3"
        case .box: "cube"
        case .cylinder: "cylinder"
        case .sphere: "circle"
        case .object: "hand.draw"
        }
    }
}

/// Which way the drawing plane faces.
public enum PlaneLock: String, CaseIterable, Identifiable, Sendable {
    case view, ground, front, side

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .view: "Facing me"
        case .ground: "Ground"
        case .front: "Front"
        case .side: "Side"
        }
    }
}

public struct DrawSettings: Equatable, Sendable {
    public var guide: GuideKind = .plane
    public var planeLock: PlaneLock = .view
    public var style: DrawingRecipe.Style = .tube
    /// Stroke width in metres at full pressure.
    public var width: Double = 0.05
    public var smoothing: Double = 0.5
    public var mirror = false
    public var extrudeDepth: Double = 0.3
    public var segments = 7
    /// The guide moved along its normal.
    public var planeOffset: Double = 0
    public var guideSize: Double = 1.5
    /// The Pencil draws and fingers navigate (off: a finger draws too).
    public var pencilOnly = true

    public init() {}
}

/// What the Pencil does with ink: draw strokes, erase them, or pick strokes to edit.
public enum InkMode: String, CaseIterable, Identifiable, Sendable {
    case draw, erase, select

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .draw: "Draw"
        case .erase: "Erase"
        case .select: "Select strokes"
        }
    }

    public var systemImage: String {
        switch self {
        case .draw: "pencil.tip"
        case .erase: "eraser"
        case .select: "lasso"
        }
    }
}

/// Ink strokes: width at full pressure, opacity and smoothing of new strokes, the eraser's size.
public struct InkSettings: Equatable, Sendable {
    public var mode: InkMode = .draw
    /// Half-width in metres at full pressure.
    public var width: Double = 0.006
    public var opacity: Double = 1
    public var smoothing: Double = 0.35
    /// Eraser radius in points.
    public var eraserRadius: Double = 14

    public init() {}
}

/// The Shadow Brush: how big, how strong, and which way.
public struct ShadowBrushSettings: Equatable, Sendable {
    /// Radius in metres.
    public var radius: Double = 0.15
    /// Bias per dab at full pressure (0…1).
    public var strength: Double = 0.35
    /// Push the shadow in (darker) or pull it out (lighter).
    public var pushesShadow = true

    public init() {}
}

public struct ScatterPanelSettings: Equatable, Sendable {
    public var count = 20
    public var scaleVariation = 0.25
    public var spacing = 0.8

    public init() {}
}

public enum TimelineMode: String, CaseIterable, Identifiable, Sendable {
    case compose, perform, keyframe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compose: "Compose"
        case .perform: "Perform"
        case .keyframe: "Keyframe"
        }
    }

    public var systemImage: String {
        switch self {
        case .compose: "rectangle.split.3x1"
        case .perform: "record.circle"
        case .keyframe: "diamond"
        }
    }
}

public enum PerformPhase: Equatable, Sendable {
    case idle
    case countdown(Int)
    case recording
}

public struct PerformSettings: Equatable, Sendable {
    /// Motion filtering 0…1 (0 keeps every wobble).
    public var smoothing = 0.3
    /// How far a finger movement moves the performed object (1 = under the finger).
    public var sensitivity = 1.0
    /// Apple Pencil Pro barrel roll turns the object while it moves.
    public var barrelRoll = true

    public init() {}
}

/// One performed property of one object.
public struct PerformChannel: Hashable, Sendable {
    public var object: ObjectID
    public var property: PropertyKey
}

public enum StaggerChoice: String, CaseIterable, Identifiable, Sendable {
    case selection, leftToRight, rightToLeft, frontToBack, wave

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .selection: "Selection order"
        case .leftToRight: "Left → right"
        case .rightToLeft: "Right → left"
        case .frontToBack: "Front → back"
        case .wave: "Wave from centre"
        }
    }
}

public struct StaggerPanelSettings: Equatable, Sendable {
    public var delay = 0.08
    public var order: StaggerChoice = .leftToRight
    public var randomTiming = 0.0
    public var randomStrength = 0.0

    public init() {}
}

/// Ways to pick many keys at once.
public enum KeyQuery: String, CaseIterable, Identifiable, Sendable {
    case all, afterPlayhead, beforePlayhead, atPlayhead, loop, invert, none

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All keys"
        case .afterPlayhead: "Everything after the playhead"
        case .beforePlayhead: "Everything before the playhead"
        case .atPlayhead: "Keys at the playhead"
        case .loop: "Keys in the loop"
        case .invert: "Invert selection"
        case .none: "Select none"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: "checkmark.circle"
        case .afterPlayhead: "arrow.right.to.line"
        case .beforePlayhead: "arrow.left.to.line"
        case .atPlayhead: "line.3.horizontal"
        case .loop: "repeat"
        case .invert: "circle.lefthalf.filled"
        case .none: "xmark.circle"
        }
    }
}

/// Where a puppet joint's pivot goes.
public enum PivotPlace: String, CaseIterable, Sendable {
    case top, center, bottom

    public var title: String {
        switch self {
        case .top: "Joint at the top (arm, leg)"
        case .center: "Joint in the middle"
        case .bottom: "Joint at the bottom"
        }
    }
}

/// A picture or video in the shot: standing in the world, or flat over the frame.
public enum MediaPlacement: String, Sendable {
    case card
    case overlay
}

/// What the library is open for.
public enum LibraryPurpose: Equatable, Sendable {
    case place
    case swap(ObjectID)
}

/// Easing presets offered for selected keys.
public enum EasingChoice: String, CaseIterable, Identifiable, Sendable {
    case linear, easeIn, easeOut, easeInOut, backOut, bounce, elastic, step

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .linear: "Linear"
        case .easeIn: "Ease in"
        case .easeOut: "Ease out"
        case .easeInOut: "Ease in & out"
        case .backOut: "Overshoot"
        case .bounce: "Bounce"
        case .elastic: "Elastic"
        case .step: "Step (hold)"
        }
    }

    public var easing: Easing {
        switch self {
        case .linear: .linear
        case .easeIn: .easeIn
        case .easeOut: .easeOut
        case .easeInOut: .easeInOut
        case .backOut: .backOut
        case .bounce: .bounce
        case .elastic: .elastic
        case .step: .step
        }
    }

    /// Bezier handles that approximate the preset (where a custom curve starts).
    public var bezier: (Double, Double, Double, Double) {
        switch self {
        case .linear, .step: (0.25, 0.25, 0.75, 0.75)
        case .easeIn: (0.55, 0, 1, 0.45)
        case .easeOut: (0, 0.55, 0.45, 1)
        case .easeInOut: (0.65, 0, 0.35, 1)
        case .backOut: (0.34, 1.56, 0.64, 1)
        case .bounce, .elastic: (0.2, 1.4, 0.4, 0.9)
        }
    }
}
