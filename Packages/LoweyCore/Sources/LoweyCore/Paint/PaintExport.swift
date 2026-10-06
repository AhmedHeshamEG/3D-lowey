import Foundation

/// An object's paint as an exporter writes it: the paint mesh (the object's surface with the paint's uvs, in the
/// object's own space) and its texture, flattened over the object's colour into an opaque PNG.
public struct PaintedExport: Hashable, Sendable {
    public var mesh: MeshData
    public var texture: Data

    public init(mesh: MeshData, texture: Data) {
        self.mesh = mesh
        self.texture = texture
    }
}

/// The paint of an object for exports and for the renderer's "shape changed" case: the stored unwrap when the shape
/// is the one it was made for, else a fresh unwrap with every layer carried over by position.
public enum PaintExport {
    /// The surface paint lands on now and the layer pictures on it. `source` is the object's current mesh.
    public static func current(_ paint: ObjectPaint, source: MeshData, file: (String) -> Data?) -> (unwrap: PaintUnwrap, layers: [String: RGBAImage])? {
        guard let stored = file(paint.surface.unwrap).flatMap({ try? PaintUnwrap(data: $0) }) else { return nil }
        var tiles: [String: RGBAImage] = [:]
        for name in Set(paint.layers.flatMap(\.tiles.values)) {
            tiles[name] = file(name).flatMap { try? PNGCodec.decode($0) }
        }
        var layers: [String: RGBAImage] = [:]
        for layer in paint.layers {
            layers[layer.id] = PaintComposer.layerImage(layer, surface: paint.surface) { tiles[$0] }
        }
        if PaintMesh.fingerprint(source) == paint.surface.mesh, stored.source.allSatisfy({ Int($0) < source.positions.count }) {
            return (stored, layers)
        }
        guard let fresh = try? PaintUnwrap.unwrap(source) else { return nil }
        let map = PaintTransfer.correspondence(from: stored, to: fresh, size: paint.surface.size)
        return (fresh, layers.mapValues { PaintTransfer.carry($0, through: map, size: paint.surface.size) })
    }

    /// The export of a painted object (nil when it has no paint that shows, or its files are missing).
    public static func painted(_ object: SceneObject, source: MeshData?, base: RGBA, file: (String) -> Data?,
                               encode: (RGBAImage) -> Data = PNGCodec.encode) -> PaintedExport? {
        guard let paint = object.paint, paint.showsPaint, let source, let (unwrap, layers) = current(paint, source: source, file: file),
              let mesh = unwrap.mesh(over: source) else { return nil }
        var texture = PaintComposer.composite(paint) { layers[$0.id] ?? .clear(width: paint.surface.size, height: paint.surface.size) }
        PaintRaster.dilate(&texture, coverage: PaintRaster.coverage(unwrap, size: paint.surface.size))
        return PaintedExport(mesh: mesh, texture: encode(PaintComposer.flattened(texture, over: RGBA(base.r, base.g, base.b, 1))))
    }
}
