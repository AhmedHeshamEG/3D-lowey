import Foundation

/// How a paint layer mixes with the layers under it (the W3C compositing formulas, in the stored sRGB values, as
/// Procreate mixes them).
public enum PaintBlend: String, Codable, Sendable, CaseIterable {
    case normal, multiply, screen, overlay, add

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .multiply: "Multiply"
        case .screen: "Screen"
        case .overlay: "Overlay"
        case .add: "Add"
        }
    }

    /// The blend function on one channel (backdrop, source).
    public func mix(_ backdrop: Double, _ source: Double) -> Double {
        switch self {
        case .normal: source
        case .multiply: backdrop * source
        case .screen: backdrop + source - backdrop * source
        case .overlay: backdrop <= 0.5 ? 2 * backdrop * source : 1 - 2 * (1 - backdrop) * (1 - source)
        case .add: min(backdrop + source, 1)
        }
    }
}

/// A square tile of a layer: `column`, `row` from the texture's top left, `PaintSurface.tileSize` pixels a side.
public struct PaintTileIndex: Hashable, Sendable, Comparable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }

    /// The key in `PaintLayer.tiles` ("column,row").
    public var key: String { "\(column),\(row)" }

    public init?(key: String) {
        let parts = key.split(separator: ",")
        guard parts.count == 2, let column = Int(parts[0]), let row = Int(parts[1]), column >= 0, row >= 0 else { return nil }
        self.init(column: column, row: row)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }
}

/// One layer of paint on an object. Its pixels are tiles: PNG files in the project's assets, named by their content,
/// so a stroke changes a few small names and undo swaps them back.
public struct PaintLayer: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var opacity: Double
    public var blend: PaintBlend
    public var visible: Bool
    /// "column,row" → the tile's file (`paint/<hash>.png` under assets). A missing tile is transparent.
    public var tiles: [String: String]

    public init(id: String, name: String, opacity: Double = 1, blend: PaintBlend = .normal, visible: Bool = true, tiles: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.opacity = min(max(opacity, 0), 1)
        self.blend = blend
        self.visible = visible
        self.tiles = tiles
    }

    public subscript(tile: PaintTileIndex) -> String? {
        get { tiles[tile.key] }
        set { tiles[tile.key] = newValue }
    }

    public var isEmpty: Bool { tiles.isEmpty }
}

/// The surface an object is painted on: its unwrap (a file under assets) and the mesh it was made for.
public struct PaintSurface: Codable, Hashable, Sendable {
    /// Pixels a side of every layer.
    public var size: Int
    /// The unwrap's file (`paint/<hash>.uv` under assets; `PaintUnwrap`'s binary form).
    public var unwrap: String
    /// The fingerprint of the mesh the unwrap was made for (`PaintMesh.fingerprint`). When the object's mesh changes
    /// (modelling, a bevel), the paint is carried onto the new one by position.
    public var mesh: String

    public static let tileSize = 256
    public static let defaultSize = 2048

    public init(size: Int = PaintSurface.defaultSize, unwrap: String, mesh: String) {
        self.size = max(Self.tileSize, size / Self.tileSize * Self.tileSize)
        self.unwrap = unwrap
        self.mesh = mesh
    }

    /// Tiles a side.
    public var tilesPerSide: Int { size / Self.tileSize }

    public var allTiles: [PaintTileIndex] {
        (0 ..< tilesPerSide).flatMap { row in (0 ..< tilesPerSide).map { PaintTileIndex(column: $0, row: row) } }
    }
}

/// Colour painted on an object (CONTEXT §10.4): a surface and layers, bottom first.
public struct ObjectPaint: Codable, Hashable, Sendable {
    public var surface: PaintSurface
    public var layers: [PaintLayer]

    public static let maximumLayers = 16

    public init(surface: PaintSurface, layers: [PaintLayer]) {
        self.surface = surface
        self.layers = layers
    }

    public func layer(_ id: String) -> PaintLayer? {
        layers.first { $0.id == id }
    }

    public func layerIndex(_ id: String) -> Int? {
        layers.firstIndex { $0.id == id }
    }

    /// Whether anything shows: a visible layer with a tile.
    public var showsPaint: Bool {
        layers.contains { $0.visible && $0.opacity > 0 && !$0.isEmpty }
    }

    /// Every file the paint refers to (the unwrap and every tile), for copying a project's paint along.
    public var files: Set<String> {
        Set(layers.flatMap(\.tiles.values)).union([surface.unwrap])
    }

    /// A new layer's id, unused in this paint.
    public func newLayerID() -> String {
        var number = layers.count + 1
        while layer("l\(number)") != nil {
            number += 1
        }
        return "l\(number)"
    }

    /// A new layer's name ("Layer 3").
    public func newLayerName() -> String {
        var number = layers.count + 1
        while layers.contains(where: { $0.name == "Layer \(number)" }) {
            number += 1
        }
        return "Layer \(number)"
    }
}

/// One tile of one layer set to a file (nil = transparent).
public struct PaintTileChange: Codable, Hashable, Sendable {
    public var layer: String
    public var tile: String
    public var file: String?

    public init(layer: String, tile: PaintTileIndex, file: String?) {
        self.layer = layer
        self.tile = tile.key
        self.file = file
    }
}

public extension SceneObject {
    /// Whether this kind of object can take paint: shapes, solid drawings, modelled meshes and placed models (not
    /// characters, ink, text or cards).
    var isPaintable: Bool {
        switch kind {
        case .primitive, .mesh: true
        case let .drawing(recipe): recipe.style != .ink
        case .asset: true
        default: false
        }
    }
}
