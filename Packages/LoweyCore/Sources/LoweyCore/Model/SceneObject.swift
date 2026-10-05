import Foundation

/// Blockout primitives. Each is a unit-sized low-poly shape with its pivot at the
/// center of its base, so it sits on the ground and scales upward like a Lego brick.
public enum PrimitiveShape: String, Codable, Sendable, CaseIterable {
    case cube, sphere, cylinder, cone, plane, torus, ramp

    public var displayName: String {
        switch self {
        case .cube: "Cube"
        case .sphere: "Sphere"
        case .cylinder: "Cylinder"
        case .cone: "Cone"
        case .plane: "Plane"
        case .torus: "Torus"
        case .ramp: "Ramp"
        }
    }
}

public enum LightType: String, Codable, Sendable, CaseIterable {
    case directional, point, spot
}

/// A drawn object stores the *recipe* (strokes + style), not the triangles.
/// The mesh is regenerated deterministically, so files stay small and editable.
public struct DrawingRecipe: Codable, Hashable, Sendable {
    public enum Style: String, Codable, Sendable, CaseIterable {
        /// Round low-poly tube following the stroke; width = radius.
        case tube
        /// Flat strip lying on the guide surface; width = half-width.
        case ribbon
        /// Closed outline extruded along the plane normal by `depth`.
        case extrude
        /// Profile revolved around the local Y axis.
        case lathe
        /// Pressure ribbons that always face the camera: line art in 3D (see `InkMesher`).
        case ink
    }

    public struct Stroke: Codable, Hashable, Sendable {
        /// Points in the object's local space.
        public var points: [Vec3]
        /// Per-point width (from Pencil pressure). Same count as `points`.
        public var widths: [Double]
        /// Ink: per-point opacity from the brush's dynamics (nil = opaque).
        public var alphas: [Double]?
        /// Ink: the project brush it was drawn with (`ProjectInfo.brushes`; nil = Ink Pen).
        public var brush: String?
        /// Ink: the seed of the brush's jitter, so the stroke draws the same every time.
        public var seed: UInt64?

        public init(points: [Vec3], widths: [Double], alphas: [Double]? = nil, brush: String? = nil, seed: UInt64? = nil) {
            self.points = points
            self.widths = widths.count == points.count ? widths : Array(repeating: widths.first ?? 0.05, count: points.count)
            self.alphas = alphas.map { $0.count == points.count ? $0 : Array(repeating: $0.first ?? 1, count: points.count) }
            self.brush = brush
            self.seed = seed
        }

        /// The same stroke (brush, seed) over other points.
        public func with(points: [Vec3], widths: [Double], alphas: [Double]?) -> Stroke {
            Stroke(points: points, widths: widths, alphas: self.alphas == nil ? nil : alphas, brush: brush, seed: seed)
        }

        /// The stored path the brush engine draws.
        public var path: BrushPath<Vec3> {
            BrushPath(points: points, widths: widths, alphas: alphas ?? Array(repeating: 1, count: points.count))
        }
    }

    public var style: Style
    public var strokes: [Stroke]
    /// Guide-plane normal in local space (ribbon facing, extrude direction).
    public var normal: Vec3
    /// Extrusion depth for `.extrude`.
    public var depth: Double
    /// Radial segments: tube sides, lathe segments.
    public var segments: Int

    public init(style: Style, strokes: [Stroke], normal: Vec3 = .unitY, depth: Double = 0.2, segments: Int = 6) {
        self.style = style
        self.strokes = strokes
        self.normal = normal
        self.depth = depth
        self.segments = segments
    }
}

/// What an object *is*. Everything else about it lives in typed properties.
public enum ObjectKind: Hashable, Sendable {
    case group
    case primitive(PrimitiveShape)
    case asset(AssetID)
    case prefab(PrefabID)
    case drawing(DrawingRecipe)
    case light(LightType)
    case camera
    /// 3D text in the world (Phase 3).
    case text(TextRecipe)
    /// A 2D element over the shot: title, label, arrow, the big X… (frame-space transform).
    case overlay(OverlayRecipe)
    /// A particle effect: fire, sparks, rain… (deterministic in time).
    case particles(ParticleRecipe)
    /// A picture or video standing in the world as a thin card.
    case card(CardRecipe)
    /// A polygon mesh made or edited with the Model tools (push/pull, sketches, booleans), in metres.
    case mesh(EditableMesh)
    /// Construction lines on a plane (drawn on the stage only; pulled into solids).
    case sketch(Sketch)
    /// A kept measurement (drawn on the stage only).
    case dimension(DimensionRecipe)

    public var typeName: String {
        switch self {
        case .group: "group"
        case .primitive: "primitive"
        case .asset: "asset"
        case .prefab: "prefab"
        case .drawing: "drawing"
        case .light: "light"
        case .camera: "camera"
        case .text: "text"
        case .overlay: "overlay"
        case .particles: "particles"
        case .card: "card"
        case .mesh: "mesh"
        case .sketch: "sketch"
        case .dimension: "dimension"
        }
    }

    /// Lives in the frame, not the world (no 3D entity, no picking in the stage).
    public var isOverlay: Bool {
        if case .overlay = self { return true }
        return false
    }

    public var assetID: AssetID? {
        if case let .asset(id) = self { return id }
        return nil
    }

    public var prefabID: PrefabID? {
        if case let .prefab(id) = self { return id }
        return nil
    }

    /// Objects that render a surface (can take color, shading, glow).
    public var hasSurface: Bool {
        switch self {
        case .primitive, .asset, .prefab, .drawing, .text, .card, .mesh: true
        case .group, .light, .camera, .overlay, .particles, .sketch, .dimension: false
        }
    }
}

extension ObjectKind: Codable {
    private enum Key: String, CodingKey {
        case type, shape, asset, prefab, drawing, light, text, overlay, particles, card, mesh, sketch, dimension
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "group": self = .group
        case "primitive": self = try .primitive(container.decode(PrimitiveShape.self, forKey: .shape))
        case "asset": self = try .asset(container.decode(AssetID.self, forKey: .asset))
        case "prefab": self = try .prefab(container.decode(PrefabID.self, forKey: .prefab))
        case "drawing": self = try .drawing(container.decode(DrawingRecipe.self, forKey: .drawing))
        case "light": self = try .light(container.decode(LightType.self, forKey: .light))
        case "camera": self = .camera
        case "text": self = try .text(container.decode(TextRecipe.self, forKey: .text))
        case "overlay": self = try .overlay(container.decode(OverlayRecipe.self, forKey: .overlay))
        case "particles": self = try .particles(container.decode(ParticleRecipe.self, forKey: .particles))
        case "card": self = try .card(container.decode(CardRecipe.self, forKey: .card))
        case "mesh": self = try .mesh(container.decode(EditableMesh.self, forKey: .mesh))
        case "sketch": self = try .sketch(container.decode(Sketch.self, forKey: .sketch))
        case "dimension": self = try .dimension(container.decode(DimensionRecipe.self, forKey: .dimension))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown object type \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(typeName, forKey: .type)
        switch self {
        case .group, .camera: break
        case let .primitive(shape): try container.encode(shape, forKey: .shape)
        case let .asset(id): try container.encode(id, forKey: .asset)
        case let .prefab(id): try container.encode(id, forKey: .prefab)
        case let .drawing(recipe): try container.encode(recipe, forKey: .drawing)
        case let .light(type): try container.encode(type, forKey: .light)
        case let .text(recipe): try container.encode(recipe, forKey: .text)
        case let .overlay(recipe): try container.encode(recipe, forKey: .overlay)
        case let .particles(recipe): try container.encode(recipe, forKey: .particles)
        case let .card(recipe): try container.encode(recipe, forKey: .card)
        case let .mesh(mesh): try container.encode(mesh, forKey: .mesh)
        case let .sketch(sketch): try container.encode(sketch, forKey: .sketch)
        case let .dimension(recipe): try container.encode(recipe, forKey: .dimension)
        }
    }
}

/// A node of the scene graph: id, name, type, parent, children, properties.
public struct SceneObject: Codable, Hashable, Sendable, Identifiable {
    public var id: ObjectID
    public var name: String
    public var kind: ObjectKind
    public var parent: ObjectID?
    public var children: [ObjectID]
    public var properties: [PropertyKey: PropertyValue]
    /// Shadow Brush dabs (nil = none; see `shadowDabs`).
    public var shadowPaint: [ShadowDab]?

    public init(
        id: ObjectID,
        name: String,
        kind: ObjectKind,
        parent: ObjectID? = nil,
        children: [ObjectID] = [],
        transform: Transform = .identity,
        properties: [PropertyKey: PropertyValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.parent = parent
        self.children = children
        self.properties = properties
        self.transform = transform
    }

    // MARK: Typed accessors

    public subscript(key: PropertyKey) -> PropertyValue? {
        get { properties[key] }
        set { properties[key] = newValue }
    }

    /// Local transform, stored as the three animatable properties.
    public var transform: Transform {
        get {
            Transform(
                position: properties[.position]?.vec3Value ?? .zero,
                rotation: properties[.rotation]?.quatValue ?? .identity,
                scale: properties[.scale]?.vec3Value ?? .one
            )
        }
        set {
            properties[.position] = .vec3(newValue.position)
            properties[.rotation] = .quat(newValue.rotation)
            properties[.scale] = .vec3(newValue.scale)
        }
    }

    public var isVisible: Bool { properties[.visible]?.boolValue ?? true }
    public var isLocked: Bool { properties[.locked]?.boolValue ?? false }
    public var color: ColorValue? { properties[.color]?.colorValue }
    public var emissive: ColorValue? { properties[.emissive]?.colorValue }
    public var emissiveIntensity: Double { properties[.emissiveIntensity]?.floatValue ?? 0 }

    public var shading: ShadingMode {
        properties[.shading]?.stringValue.flatMap(ShadingMode.init(rawValue:)) ?? .inherit
    }
}
