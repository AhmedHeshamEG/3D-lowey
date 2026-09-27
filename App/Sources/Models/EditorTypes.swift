import Foundation
import LoweyCore
import LoweyRender

/// Top-right mode switcher.
enum EditorMode: String, CaseIterable, Identifiable {
    case build, animate, camera, look, export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .build: "Build"
        case .animate: "Animate"
        case .camera: "Camera"
        case .look: "Look"
        case .export: "Export"
        }
    }

    var systemImage: String {
        switch self {
        case .build: "cube.transparent"
        case .animate: "timeline.selection"
        case .camera: "video"
        case .look: "paintpalette"
        case .export: "square.and.arrow.up"
        }
    }
}

/// Left tool rail tools.
enum Tool: String, CaseIterable, Identifiable {
    case select, lasso, draw, scatter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select & move"
        case .lasso: "Lasso select"
        case .draw: "Draw in 3D"
        case .scatter: "Scatter"
        }
    }

    var systemImage: String {
        switch self {
        case .select: "hand.point.up.left"
        case .lasso: "lasso"
        case .draw: "pencil.tip"
        case .scatter: "circle.hexagongrid"
        }
    }
}

/// What the drawing tool draws on.
enum GuideKind: String, CaseIterable, Identifiable {
    case plane, box, cylinder, sphere, object

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plane: "Plane"
        case .box: "Box"
        case .cylinder: "Cylinder"
        case .sphere: "Sphere"
        case .object: "On object"
        }
    }

    var systemImage: String {
        switch self {
        case .plane: "square.grid.3x3"
        case .box: "cube"
        case .cylinder: "cylinder"
        case .sphere: "circle"
        case .object: "hand.draw"
        }
    }
}

/// Which way the locked drawing plane faces.
enum PlaneLock: String, CaseIterable, Identifiable {
    case view, ground, front, side

    var id: String { rawValue }

    var title: String {
        switch self {
        case .view: "Facing me"
        case .ground: "Ground"
        case .front: "Front"
        case .side: "Side"
        }
    }
}

struct DrawSettings: Equatable {
    var guide: GuideKind = .plane
    var planeLock: PlaneLock = .view
    var style: DrawingRecipe.Style = .tube
    /// Stroke width in meters at full pressure.
    var width: Double = 0.05
    var smoothing: Double = 0.5
    var mirror = false
    var extrudeDepth: Double = 0.3
    var segments = 7
    /// Offset of the guide along its normal (move the plane back and forth).
    var planeOffset: Double = 0
    var guideSize: Double = 1.5
    var pencilOnly = true
}

extension DrawingRecipe.Style {
    var title: String {
        switch self {
        case .tube: "Tube"
        case .ribbon: "Ribbon"
        case .extrude: "Extrude"
        case .lathe: "Lathe"
        }
    }

    var systemImage: String {
        switch self {
        case .tube: "scribble.variable"
        case .ribbon: "wave.3.right"
        case .extrude: "square.stack.3d.up"
        case .lathe: "rotate.3d"
        }
    }

    var hint: String {
        switch self {
        case .tube: "Draw lines that become round tubes"
        case .ribbon: "Draw flat strips on the surface"
        case .extrude: "Draw a closed outline, it becomes a solid"
        case .lathe: "Draw half a profile, it spins into a vase, trunk or tower"
        }
    }
}

struct ScatterPanelSettings: Equatable {
    var count = 20
    var scaleVariation = 0.25
    var spacing = 0.8
}
