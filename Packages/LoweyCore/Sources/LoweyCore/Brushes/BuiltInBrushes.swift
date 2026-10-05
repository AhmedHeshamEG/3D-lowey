import Foundation

/// The brushes Maquette comes with, in three sets. Every one is built from the built-in tips and grains, so nothing
/// of anyone else's ships. Ink Pen is the default for ink and flipbooks and draws the line 2.0 drew.
public enum BuiltInBrushes {
    public static let inkPenID = "builtin.ink-pen"

    public static let sets: [BrushSet] = [
        BrushSet(id: "builtin.inking", name: "Inking",
                 brushes: [inkPenID, "builtin.technical-pen", "builtin.brush-pen", "builtin.marker"], builtIn: true),
        BrushSet(id: "builtin.sketching", name: "Sketching", brushes: ["builtin.pencil", "builtin.charcoal"], builtIn: true),
        BrushSet(id: "builtin.painting", name: "Painting",
                 brushes: ["builtin.dry-brush", "builtin.watercolour", "builtin.airbrush", "builtin.splatter"], builtIn: true)
    ]

    public static let all: [Brush] = [
        inkPen, technicalPen, brushPen, marker, pencil, charcoal, dryBrush, watercolour, airbrush, splatter
    ]

    public static func brush(_ id: String) -> Brush? {
        all.first { $0.id == id }
    }

    static func make(_ id: String, _ name: String, shape: BrushShape = BrushShape(), grain: BrushGrain = BrushGrain(),
                     stroke: BrushStrokeSettings, dynamics: BrushDynamics, rendering: BrushRendering = BrushRendering()) -> Brush {
        Brush(id: id, name: name, shape: shape, grain: grain, stroke: stroke, dynamics: dynamics, rendering: rendering,
              about: BrushAbout(origin: .builtIn, author: "studio h.", resetsTo: id))
    }

    public static let inkPen = make(
        inkPenID, "Ink Pen",
        stroke: BrushStrokeSettings(spacing: 0.06, streamline: 0.35, taperStart: 0.15, taperEnd: 0.2, taperSize: 0.88),
        dynamics: BrushDynamics(pressureSize: 1, minimumSize: 0.25)
    )

    public static let technicalPen = make(
        "builtin.technical-pen", "Technical Pen",
        stroke: BrushStrokeSettings(spacing: 0.06, streamline: 0.55),
        dynamics: BrushDynamics(pressureSize: 0, minimumSize: 1)
    )

    public static let brushPen = make(
        "builtin.brush-pen", "Brush Pen",
        shape: BrushShape(roundness: 0.32, angle: 45, followsStroke: false),
        stroke: BrushStrokeSettings(spacing: 0.04, streamline: 0.4, taperStart: 0.1, taperEnd: 0.25, taperSize: 0.95),
        dynamics: BrushDynamics(pressureSize: 1, pressureCurve: .soft, minimumSize: 0.15)
    )

    public static let marker = make(
        "builtin.marker", "Marker",
        shape: BrushShape(source: .builtIn(.flatTip), angle: 30, followsStroke: false),
        stroke: BrushStrokeSettings(spacing: 0.05, streamline: 0.2),
        dynamics: BrushDynamics(pressureSize: 0.2, minimumSize: 0.6),
        rendering: BrushRendering(flow: 0.55)
    )

    public static let pencil = make(
        "builtin.pencil", "Pencil",
        shape: BrushShape(source: .builtIn(.pencilTip), rotationJitter: 1),
        grain: BrushGrain(source: .builtIn(.paper), scale: 1, depth: 0.8, movement: .texturized),
        stroke: BrushStrokeSettings(spacing: 0.05, streamline: 0.15),
        dynamics: BrushDynamics(pressureSize: 0.3, pressureOpacity: 0.8, tiltSize: 0.7, tiltOpacity: 0.3, minimumSize: 0.5,
                                minimumOpacity: 0.15),
        rendering: BrushRendering(flow: 0.75)
    )

    public static let charcoal = make(
        "builtin.charcoal", "Charcoal",
        shape: BrushShape(source: .builtIn(.chalkTip), rotationJitter: 1),
        grain: BrushGrain(source: .builtIn(.charcoal), scale: 1.5, depth: 0.9, movement: .texturized),
        stroke: BrushStrokeSettings(spacing: 0.08, streamline: 0.1, jitter: 0.03),
        dynamics: BrushDynamics(pressureSize: 0.4, pressureOpacity: 0.6, tiltSize: 0.8, sizeJitter: 0.1, minimumSize: 0.4),
        rendering: BrushRendering(flow: 0.85)
    )

    public static let dryBrush = make(
        "builtin.dry-brush", "Dry Brush",
        shape: BrushShape(source: .builtIn(.bristleTip)),
        grain: BrushGrain(source: .builtIn(.canvas), scale: 0.8, depth: 0.4, movement: .rolling),
        stroke: BrushStrokeSettings(spacing: 0.03, streamline: 0.25, taperEnd: 0.1, taperSize: 0.3, taperOpacity: 0.6),
        dynamics: BrushDynamics(pressureSize: 0.5, pressureOpacity: 0.3, minimumSize: 0.4),
        rendering: BrushRendering(flow: 0.9, wetEdges: 0.2)
    )

    public static let watercolour = make(
        "builtin.watercolour", "Watercolour",
        shape: BrushShape(source: .builtIn(.softRound)),
        grain: BrushGrain(source: .builtIn(.paper), scale: 1.4, depth: 0.5, movement: .texturized),
        stroke: BrushStrokeSettings(spacing: 0.08, streamline: 0.3),
        dynamics: BrushDynamics(pressureSize: 0.4, pressureOpacity: 0.5, minimumSize: 0.5, minimumOpacity: 0.3),
        rendering: BrushRendering(flow: 0.25, wetEdges: 0.6)
    )

    public static let airbrush = make(
        "builtin.airbrush", "Soft Airbrush",
        shape: BrushShape(source: .builtIn(.softRound)),
        stroke: BrushStrokeSettings(spacing: 0.04, streamline: 0.2),
        dynamics: BrushDynamics(pressureSize: 0, pressureOpacity: 1, minimumSize: 1, minimumOpacity: 0),
        rendering: BrushRendering(flow: 0.08)
    )

    public static let splatter = make(
        "builtin.splatter", "Splatter",
        shape: BrushShape(source: .builtIn(.splatterTip), rotationJitter: 1, flipXJitter: true, flipYJitter: true, count: 2),
        stroke: BrushStrokeSettings(spacing: 1.2, streamline: 0, jitter: 0.5),
        dynamics: BrushDynamics(pressureSize: 0.5, sizeJitter: 0.6, opacityJitter: 0.2, minimumSize: 0.4)
    )
}
