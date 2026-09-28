import Foundation

/// A 2D element drawn over the shot (titles, labels, arrows, the big X, the question mark…).
/// Overlays are ordinary scene objects, so presets, keys, Perform, stagger and scripts all work on them.
/// Their transform lives in *frame space*: position x/y in −1…1 across the frame (y up), z = layer;
/// rotation turns them in the frame; scale x/y stretches them.
public struct OverlayRecipe: Codable, Hashable, Sendable {
    public enum Shape: String, Codable, Sendable, CaseIterable, Identifiable {
        case title, label, arrow, highlight, cross, question, exclamation, check, circle, rectangle, triangle, star, image

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .title: "Title"
            case .label: "Label"
            case .arrow: "Arrow"
            case .highlight: "Highlight"
            case .cross: "Big X"
            case .question: "Question mark"
            case .exclamation: "Exclamation"
            case .check: "Tick"
            case .circle: "Circle"
            case .rectangle: "Box"
            case .triangle: "Triangle"
            case .star: "Star"
            case .image: "Image"
            }
        }

        public var systemImage: String {
            switch self {
            case .title: "textformat.size"
            case .label: "tag"
            case .arrow: "arrow.up.right"
            case .highlight: "highlighter"
            case .cross: "xmark"
            case .question: "questionmark"
            case .exclamation: "exclamationmark"
            case .check: "checkmark"
            case .circle: "circle"
            case .rectangle: "rectangle"
            case .triangle: "triangle"
            case .star: "star"
            case .image: "photo"
            }
        }

        public var hasText: Bool { self == .title || self == .label }

        /// Default colour (few decisions: the X is red, the question mark yellow, text white).
        public var defaultColor: RGBA {
            switch self {
            case .cross: RGBA(0.9, 0.16, 0.14)
            case .question, .exclamation, .star: RGBA(1, 0.8, 0.2)
            case .check: RGBA(0.3, 0.85, 0.4)
            case .highlight: RGBA(1, 0.85, 0.2)
            default: RGBA(1, 1, 1)
            }
        }
    }

    public enum Font: String, Codable, Sendable, CaseIterable, Identifiable {
        case rounded, bold, serif, mono, marker

        public var id: String { rawValue }
    }

    public var shape: Shape
    public var text: String
    public var font: Font
    /// Image file inside the project's `assets/` folder (for `.image`).
    public var image: String?
    /// Line width in overlay units (arrows, outlines, highlight).
    public var stroke: Double
    public var filled: Bool
    /// Base width ÷ height for boxes, highlights, arrows (length).
    public var aspect: Double
    /// Arrow curvature (−1…1).
    public var bend: Double
    /// Follow a 3D object: the overlay sits where the object is in the shot (plus its own position as an offset).
    public var anchor: ObjectID?

    public init(
        shape: Shape, text: String = "", font: Font = .rounded, image: String? = nil, stroke: Double = 0.12, filled: Bool = true,
        aspect: Double = 1, bend: Double = 0, anchor: ObjectID? = nil
    ) {
        self.shape = shape
        self.text = text
        self.font = font
        self.image = image
        self.stroke = stroke
        self.filled = filled
        self.aspect = aspect
        self.bend = bend
        self.anchor = anchor
    }

    public static func `default`(_ shape: Shape) -> OverlayRecipe {
        switch shape {
        case .title: OverlayRecipe(shape: .title, text: "Title", font: .bold)
        case .label: OverlayRecipe(shape: .label, text: "Label")
        case .arrow: OverlayRecipe(shape: .arrow, stroke: 0.14, aspect: 3, bend: 0.25)
        case .highlight: OverlayRecipe(shape: .highlight, stroke: 0.1, filled: false, aspect: 2.4)
        case .rectangle: OverlayRecipe(shape: .rectangle, stroke: 0.1, filled: false, aspect: 1.6)
        default: OverlayRecipe(shape: shape)
        }
    }
}

/// Where an overlay is drawn in a frame of `width × height` pixels.
public struct OverlayPlacement: Hashable, Sendable {
    public var id: ObjectID
    public var recipe: OverlayRecipe
    /// Centre in pixels (y down, like images).
    public var center: SIMD2<Double>
    /// One overlay unit in pixels (a tenth of the frame's short side).
    public var unit: Double
    public var scale: SIMD2<Double>
    /// Radians, counter-clockwise on screen.
    public var angle: Double
    public var opacity: Double
    /// 0…1 how much is revealed (typewriter text, an arrow drawing itself).
    public var reveal: Double
    public var color: RGBA
    public var accent: RGBA?
    public var layer: Double
}

public enum OverlayLayout {
    /// Visible overlays of `scene`, back to front. `project` maps a world point to frame space (−1…1, y up)
    /// for anchored overlays, or nil when it's behind the camera.
    public static func placements(
        in scene: Scene, palette: Palette, width: Double, height: Double, project: ((Vec3) -> (Double, Double)?)? = nil
    ) -> [OverlayPlacement] {
        var result: [OverlayPlacement] = []
        let unit = min(width, height) / 10
        for id in scene.orderedIDs() {
            guard let object = scene.objects[id], case let .overlay(recipe) = object.kind, scene.isEffectivelyVisible(id) else { continue }
            let transform = object.transform
            var x = transform.position.x
            var y = transform.position.y
            if let anchor = recipe.anchor, scene.objects[anchor] != nil {
                guard let projected = project?(scene.worldTransform(of: anchor).position) else { continue }
                x += projected.0
                y += projected.1
            }
            let opacity = min(max(object.opacity, 0), 1)
            guard opacity > 0.001 else { continue }
            let color = object.color?.resolved(in: palette) ?? recipe.shape.defaultColor
            let accent = object[.accentColor]?.colorValue?.resolved(in: palette)
            result.append(OverlayPlacement(
                id: id, recipe: recipe,
                center: SIMD2(width / 2 + x * width / 2, height / 2 - y * height / 2),
                unit: unit, scale: SIMD2(transform.scale.x, transform.scale.y), angle: angle(of: transform.rotation),
                opacity: opacity, reveal: min(max(object[.reveal]?.floatValue ?? 1, 0), 1), color: color, accent: accent,
                layer: transform.position.z
            ))
        }
        return result.enumerated().sorted { lhs, rhs in
            lhs.element.layer != rhs.element.layer ? lhs.element.layer < rhs.element.layer : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// In-frame angle of a rotation (how far it turns the x axis in the XY plane).
    public static func angle(of rotation: Quat) -> Double {
        let axis = rotation.act(Vec3(1, 0, 0))
        return atan2(axis.y, axis.x)
    }

    /// Pinhole projection into frame space (−1…1, y up) for a camera at `camera` with vertical field of view
    /// `fieldOfView` (degrees) and `aspect` = width ÷ height. Nil behind the camera.
    public static func project(_ point: Vec3, camera: Transform, fieldOfView: Double, aspect: Double) -> (Double, Double)? {
        let local = camera.rotation.inverse.act(point - camera.position)
        guard local.z < -1e-4 else { return nil }
        let f = 1 / tan(fieldOfView * .pi / 360)
        let x = local.x / -local.z * f / aspect
        let y = local.y / -local.z * f
        return (x, y)
    }

    /// Frame-space position of a pixel (for dragging overlays with a finger).
    public static func framePosition(pixel: SIMD2<Double>, width: Double, height: Double) -> (Double, Double) {
        ((pixel.x - width / 2) / (width / 2), (height / 2 - pixel.y) / (height / 2))
    }
}
