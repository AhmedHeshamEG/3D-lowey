import Foundation

/// The mesh an object is painted on: exactly the one the renderer draws, in the object's own space (placed models'
/// meshes come from the renderer's loaded copy, so they aren't here).
public enum PaintSource {
    public static func mesh(of object: SceneObject) -> MeshData? {
        switch object.kind {
        case let .primitive(shape):
            if let bevel = BevelSpec(object), BevelSpec.applies(to: shape) {
                // Built at the object's size, as the renderer builds it (its scale leaves the matrix).
                let scale = object.transform.scale
                let size = SIMD3<Float>(Float(abs(scale.x)), Float(abs(scale.y)), Float(abs(scale.z)))
                return BevelMesh.make(shape, size: size, bevel: bevel) ?? PrimitiveMesh.make(shape, shading: .smooth)
            }
            return PrimitiveMesh.make(shape, shading: .smooth)
        case let .drawing(recipe) where recipe.style != .ink:
            return DrawingMesher.mesh(for: recipe).shaded(.smooth)
        case let .mesh(editable):
            return editable.renderMesh()
        default:
            return nil
        }
    }

    /// What brings the mesh into the object's own space when it isn't there already: a bevelled shape is built at its
    /// size, so its scale comes out (as the renderer does).
    public static func toObjectSpace(of object: SceneObject) -> SIMD3<Float>? {
        guard case let .primitive(shape) = object.kind, BevelSpec(object) != nil, BevelSpec.applies(to: shape) else { return nil }
        let scale = object.transform.scale
        let size = SIMD3<Float>(Float(scale.x), Float(scale.y), Float(scale.z))
        return SIMD3<Float>(1 / max(abs(size.x), 1e-4), 1 / max(abs(size.y), 1e-4), 1 / max(abs(size.z), 1e-4))
            * SIMD3<Float>(size.x < 0 ? -1 : 1, size.y < 0 ? -1 : 1, size.z < 0 ? -1 : 1)
    }

    /// How much the renderer stretches the mesh (a scaled primitive), so the unwrap gives each side the pixels it
    /// shows. Bevelled shapes are built at their size already.
    public static func stretch(of object: SceneObject) -> SIMD3<Float> {
        guard case let .primitive(shape) = object.kind, !(BevelSpec(object) != nil && BevelSpec.applies(to: shape)) else {
            return SIMD3<Float>(1, 1, 1)
        }
        let scale = object.transform.scale
        return SIMD3<Float>(Float(max(abs(scale.x), 1e-3)), Float(max(abs(scale.y), 1e-3)), Float(max(abs(scale.z), 1e-3)))
    }
}

/// Making an object paintable and the edits on its layers: each returns the command (or nil when there's nothing to
/// do) and the files to write first, so the caller writes them, then performs.
public enum PaintOperations {
    /// The files a new or changed paint needs written before its command (name → bytes).
    public typealias Files = [String: Data]

    /// A first surface for a mesh: its unwrap (the mesh's own uvs when they're asked for and good) and one empty layer.
    public static func prepare(mesh: MeshData, stretch: SIMD3<Float> = SIMD3<Float>(1, 1, 1), keepOwnUVs: Bool,
                               size: Int = PaintSurface.defaultSize) throws(PaintUnwrap.Failure) -> (paint: ObjectPaint, unwrap: PaintUnwrap, files: Files) {
        let unwrap: PaintUnwrap = if keepOwnUVs, let own = PaintUnwrap.existing(mesh) {
            own
        } else {
            try PaintUnwrap.unwrap(mesh, scale: stretch)
        }
        let data = unwrap.data
        let name = PaintFiles.unwrapName(for: data)
        let surface = PaintSurface(size: size, unwrap: name, mesh: PaintMesh.fingerprint(mesh))
        let paint = ObjectPaint(surface: surface, layers: [PaintLayer(id: "l1", name: "Layer 1")])
        return (paint, unwrap, [name: data])
    }

    /// A picture as a layer's tiles: their files and the tile changes (transparent tiles clear theirs).
    public static func tileChanges(_ image: RGBAImage, layer: PaintLayer, surface: PaintSurface,
                                   encode: (RGBAImage) -> Data = PNGCodec.encode) -> (changes: [PaintTileChange], files: Files) {
        var changes: [PaintTileChange] = []
        var files: Files = [:]
        let tiles = PaintComposer.tiles(of: image, surface: surface)
        for index in surface.allTiles {
            if let tile = tiles[index] {
                let png = encode(tile)
                let name = PaintFiles.tileName(for: png)
                files[name] = png
                if layer[index] != name { changes.append(PaintTileChange(layer: layer.id, tile: index, file: name)) }
            } else if layer[index] != nil {
                changes.append(PaintTileChange(layer: layer.id, tile: index, file: nil))
            }
        }
        return (changes, files)
    }

    /// Fills a whole layer with one colour (every tile is the same file).
    public static func fill(_ color: RGBA, layer: PaintLayer, surface: PaintSurface, object: ObjectID,
                            encode: (RGBAImage) -> Data = PNGCodec.encode) -> (command: EditCommand, files: Files) {
        let png = encode(RGBAImage(width: PaintSurface.tileSize, height: PaintSurface.tileSize, color: color))
        let name = PaintFiles.tileName(for: png)
        let changes = surface.allTiles.map { PaintTileChange(layer: layer.id, tile: $0, file: name) }
        return (.paintTiles(object, changes), [name: png])
    }

    public static func clear(_ layer: PaintLayer, object: ObjectID) -> EditCommand? {
        let changes = layer.tiles.keys.sorted().compactMap(PaintTileIndex.init(key:)).map { PaintTileChange(layer: layer.id, tile: $0, file: nil) }
        return changes.isEmpty ? nil : .paintTiles(object, changes)
    }

    // MARK: Layers (one `setPaint` each)

    public static func addLayer(to paint: ObjectPaint, above id: String?, object: ObjectID) -> (EditCommand, String)? {
        guard paint.layers.count < ObjectPaint.maximumLayers else { return nil }
        var changed = paint
        let layer = PaintLayer(id: paint.newLayerID(), name: paint.newLayerName())
        let index = id.flatMap(paint.layerIndex).map { $0 + 1 } ?? paint.layers.count
        changed.layers.insert(layer, at: min(index, changed.layers.count))
        return (.setPaint(object, changed), layer.id)
    }

    public static func deleteLayer(_ id: String, from paint: ObjectPaint, object: ObjectID) -> EditCommand? {
        guard let index = paint.layerIndex(id) else { return nil }
        var changed = paint
        changed.layers.remove(at: index)
        if changed.layers.isEmpty { changed.layers = [PaintLayer(id: changed.newLayerID(), name: changed.newLayerName())] }
        return .setPaint(object, changed)
    }

    /// Moves a layer to `index` (0 = bottom).
    public static func moveLayer(_ id: String, to index: Int, in paint: ObjectPaint, object: ObjectID) -> EditCommand? {
        guard let from = paint.layerIndex(id) else { return nil }
        let target = min(max(index, 0), paint.layers.count - 1)
        guard target != from else { return nil }
        var changed = paint
        let layer = changed.layers.remove(at: from)
        changed.layers.insert(layer, at: target)
        return .setPaint(object, changed)
    }

    /// Changes one layer's settings (name, opacity, blend, visibility); nil when nothing changed.
    public static func update(_ id: String, in paint: ObjectPaint, object: ObjectID, _ change: (inout PaintLayer) -> Void) -> EditCommand? {
        guard let index = paint.layerIndex(id) else { return nil }
        var changed = paint
        change(&changed.layers[index])
        changed.layers[index].opacity = min(max(changed.layers[index].opacity, 0), 1)
        return changed == paint ? nil : .setPaint(object, changed)
    }

    /// A copy of a layer above it.
    public static func duplicateLayer(_ id: String, in paint: ObjectPaint, object: ObjectID) -> (EditCommand, String)? {
        guard paint.layers.count < ObjectPaint.maximumLayers, let index = paint.layerIndex(id) else { return nil }
        var changed = paint
        var copy = paint.layers[index]
        copy.id = paint.newLayerID()
        copy.name = "\(copy.name) copy"
        changed.layers.insert(copy, at: index + 1)
        return (.setPaint(object, changed), copy.id)
    }

    /// A layer merged into the one under it (their composite, at full opacity, in normal mode).
    public static func mergeDown(_ id: String, in paint: ObjectPaint, object: ObjectID, image: (PaintLayer) -> RGBAImage,
                                 encode: (RGBAImage) -> Data = PNGCodec.encode) -> (command: EditCommand, files: Files)? {
        guard let index = paint.layerIndex(id), index > 0 else { return nil }
        let upper = paint.layers[index], lower = paint.layers[index - 1]
        var pair = ObjectPaint(surface: paint.surface, layers: [lower, upper])
        pair.layers[0].visible = true
        pair.layers[1].visible = upper.visible
        let merged = PaintComposer.composite(pair, layer: image)
        var result = lower
        result.opacity = 1
        result.blend = .normal
        result.visible = lower.visible
        result.tiles = [:]
        var files: Files = [:]
        for (tile, picture) in PaintComposer.tiles(of: merged, surface: paint.surface) {
            let png = encode(picture)
            let name = PaintFiles.tileName(for: png)
            files[name] = png
            result[tile] = name
        }
        var changed = paint
        changed.layers[index - 1] = result
        changed.layers.remove(at: index)
        return (.setPaint(object, changed), files)
    }
}
