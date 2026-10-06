import CoreGraphics
import Foundation
import ImageIO
import LoweyCore
import Metal
import Synchronization

/// The GPU side of painted objects. Each one has a texture per layer, filled from the layer's tiles (the stage streams
/// a few a frame and asks for another; exports load every tile at once), composited into the texture the shading pass
/// reads. A stroke draws straight into its layer (`PaintTextures+Stroke`); the tiles it changed are read back and
/// adopted, so the document's next state needs no decoding.
final class PaintTextures {
    let device: RenderDevice
    /// The stage: tiles stream in a few per frame. Off for exports and stills, which need every tile now.
    var streams = false
    /// Tiles were left for later frames (the stage draws again).
    private(set) var wantsAnotherFrame = false
    private(set) var surfaces: [ObjectID: Surface] = [:]
    private var unwraps: [String: PaintUnwrap] = [:]
    private var fingerprints: [ObjectIdentifier: Fingerprint] = [:]
    /// Paint carried onto a changed shape, made off the main thread (`CarriedPaint`).
    let carried = CarriedPaint()
    /// Asks the stage for a frame (carried paint became ready).
    var onNeedsFrame: (@Sendable () -> Void)?
    /// Work queued by this frame's compile: tile uploads, then coverage and compositing.
    var uploads: [Upload] = []
    var scratch: (MTLTexture, MTLTexture)?
    /// The stroke being painted: its layer as it was before it (`PaintTextures+Stroke`).
    var stroke: ActiveStroke?
    var strokeTarget: MTLTexture?
    private var clock: UInt64 = 0

    static let tilesPerFrame = 12

    init(device: RenderDevice) {
        self.device = device
    }

    /// One layer on the GPU (premultiplied, the stored sRGB values) and the file each tile holds now ("" = clear).
    final class Layer {
        let texture: MTLTexture
        var loaded: [String: String] = [:]

        init(texture: MTLTexture) {
            self.texture = texture
        }
    }

    /// An object's paint on the GPU.
    final class Surface {
        let size: Int
        /// The unwrap it's drawn with (a file name, or the carried surface's key).
        var unwrap: String
        var layers: [String: Layer] = [:]
        /// The layers' settings in order (bottom first), as last composited.
        var settings: [PaintLayer] = []
        let composite: MTLTexture
        /// The composite as the shading pass samples it (sRGB, so it reads linear).
        let view: MTLTexture
        var coverage: MTLTexture?
        var coverageMesh: ObjectIdentifier?
        /// The paint mesh this frame draws (coverage is made from it).
        var mesh: GPUMesh?
        var needsCompose = true
        var lastUse: UInt64 = 0

        init(size: Int, unwrap: String, composite: MTLTexture, view: MTLTexture) {
            self.size = size
            self.unwrap = unwrap
            self.composite = composite
            self.view = view
        }
    }

    final class Fingerprint {
        weak var mesh: GPUMesh?
        let value: String

        init(mesh: GPUMesh, value: String) {
            self.mesh = mesh
            self.value = value
        }
    }

    /// A tile to copy into a layer this frame (nil bytes clear it).
    struct Upload {
        var layer: Layer
        var tile: PaintTileIndex
        var file: String
        var bytes: [UInt8]?
    }

    struct ActiveStroke {
        var id: Int
        var object: ObjectID
        var layer: String
        var before: MTLTexture
    }

    // MARK: Lookups

    /// The fingerprint of a mesh the renderer drew (computed once per cached mesh).
    func fingerprint(of mesh: GPUMesh) -> String {
        let key = ObjectIdentifier(mesh)
        if let known = fingerprints[key], known.mesh === mesh { return known.value }
        let value = PaintMesh.fingerprint(mesh.data)
        fingerprints[key] = Fingerprint(mesh: mesh, value: value)
        if fingerprints.count > 512 { fingerprints = fingerprints.filter { $0.value.mesh != nil } }
        return value
    }

    func unwrap(_ name: String, file: (String) -> Data?) -> PaintUnwrap? {
        if let known = unwraps[name] { return known }
        guard let data = file(name), let unwrap = try? PaintUnwrap(data: data) else { return nil }
        unwraps[name] = unwrap
        return unwrap
    }

    // MARK: Keeping a surface in step with the document

    /// The composite of an object's paint for this frame, its layers brought in step with `paint` (tiles read through
    /// `file`, or the pictures of paint carried onto a changed shape). Uploads wait in `uploads` for `encodeUpdates`.
    func texture(for object: ObjectID, paint: ObjectPaint, unwrap: String, mesh: GPUMesh, pictures: [String: RGBAImage]? = nil,
                 file: (String) -> Data?) -> MTLTexture? {
        clock &+= 1
        guard let surface = surface(object, size: paint.surface.size, unwrap: unwrap) else { return nil }
        surface.lastUse = clock
        surface.mesh = mesh
        if surface.coverageMesh != ObjectIdentifier(mesh) { surface.needsCompose = true }
        let wanted = Set(paint.layers.map(\.id))
        for id in surface.layers.keys where !wanted.contains(id) {
            surface.layers[id] = nil
            surface.needsCompose = true
        }
        var budget = streams ? Self.tilesPerFrame : Int.max
        for layer in paint.layers {
            guard let texture = surface.layers[layer.id] ?? makeLayer(size: surface.size) else { continue }
            surface.layers[layer.id] = texture
            if let pictures {
                queuePicture(pictures[layer.id], into: texture, surface: paint.surface, key: unwrap)
            } else {
                queueTiles(layer, into: texture, surface: paint.surface, budget: &budget, file: file)
            }
        }
        if surface.settings != paint.layers.map(Self.settings) {
            surface.settings = paint.layers.map(Self.settings)
            surface.needsCompose = true
        }
        return surface.view
    }

    /// A layer's settings without its tiles (what compositing depends on besides the pixels).
    static func settings(_ layer: PaintLayer) -> PaintLayer {
        var copy = layer
        copy.tiles = [:]
        return copy
    }

    private func surface(_ object: ObjectID, size: Int, unwrap: String) -> Surface? {
        if let existing = surfaces[object], existing.size == size {
            if existing.unwrap != unwrap {
                // A new surface under the same object (prepared again, carried, restored): every tile again.
                existing.unwrap = unwrap
                existing.layers.removeAll()
                existing.coverage = nil
                existing.coverageMesh = nil
                existing.needsCompose = true
            }
            return existing
        }
        let levels = Int(log2(Double(size))) + 1
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: true)
        descriptor.mipmapLevelCount = levels
        descriptor.usage = [.renderTarget, .shaderRead, .pixelFormatView]
        descriptor.storageMode = .private
        guard let composite = device.device.makeTexture(descriptor: descriptor),
              let view = composite.makeTextureView(pixelFormat: .rgba8Unorm_srgb) else { return nil }
        composite.label = "paint \(object.raw)"
        let surface = Surface(size: size, unwrap: unwrap, composite: composite, view: view)
        surfaces[object] = surface
        return surface
    }

    private func makeLayer(size: Int) -> Layer? {
        guard let texture = try? device.makeTexture(RenderDevice.layerFormat, width: size, height: size,
                                                    usage: [.renderTarget, .shaderRead], label: "paint layer") else { return nil }
        return Layer(texture: texture)
    }

    private func queueTiles(_ layer: PaintLayer, into texture: Layer, surface: PaintSurface, budget: inout Int, file: (String) -> Data?) {
        for index in surface.allTiles {
            let wanted = layer[index] ?? ""
            guard texture.loaded[index.key] != wanted else { continue }
            if wanted.isEmpty {
                uploads.append(Upload(layer: texture, tile: index, file: "", bytes: nil))
                texture.loaded[index.key] = ""
                continue
            }
            guard budget > 0 else {
                wantsAnotherFrame = true
                continue
            }
            budget -= 1
            let bytes = file(wanted).flatMap(PaintPixels.premultiplied(png:))
            uploads.append(Upload(layer: texture, tile: index, file: wanted, bytes: bytes))
            texture.loaded[index.key] = wanted
        }
    }

    private func queuePicture(_ picture: RGBAImage?, into texture: Layer, surface: PaintSurface, key: String) {
        guard texture.loaded["picture"] != key else { return }
        texture.loaded["picture"] = key
        for index in surface.allTiles {
            let tile = picture?.tile(index, size: PaintSurface.tileSize)
            uploads.append(Upload(layer: texture, tile: index, file: key, bytes: tile.map(PaintPixels.premultiplied(image:))))
        }
    }

    /// The tiles a stroke wrote are already in the layer: they become what it holds, so nothing is decoded again.
    func adopt(object: ObjectID, layer: String, changes: [PaintTileChange]) {
        guard let texture = surfaces[object]?.layers[layer] else { return }
        for change in changes where change.layer == layer {
            texture.loaded[change.tile] = change.file ?? ""
        }
    }

    /// Every layer loads again from its tiles (and no stroke is in progress).
    func forget() {
        for surface in surfaces.values {
            surface.layers.removeAll()
            surface.needsCompose = true
        }
        stroke = nil
    }

    /// Frees surfaces not drawn lately (and everything under memory pressure).
    func trim(keeping recent: UInt64 = 600) {
        let limit = clock > recent ? clock - recent : 0
        surfaces = surfaces.filter { $0.value.lastUse >= limit }
        if surfaces.isEmpty { scratch = nil }
        unwraps.removeAll()
    }

    /// Called after a frame's work is queued: whether tiles are still to come.
    func startFrame() {
        wantsAnotherFrame = false
    }
}

/// Pixels between PNG tiles, RGBA pictures and the GPU's premultiplied layers.
public enum PaintPixels {
    static let side = PaintSurface.tileSize

    /// A tile's PNG as premultiplied RGBA8 (the colours as stored, no colour conversion).
    static func premultiplied(png: Data) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? bytes : nil
    }

    static func premultiplied(image: RGBAImage) -> [UInt8] {
        var bytes = image.pixels
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = UInt16(bytes[index + 3])
            guard alpha < 255 else { continue }
            for channel in 0 ..< 3 {
                bytes[index + channel] = UInt8((UInt16(bytes[index + channel]) * alpha + 127) / 255)
            }
        }
        return bytes
    }

    /// Premultiplied bytes back to a straight-alpha picture.
    static func straight(_ bytes: [UInt8], width: Int, height: Int) -> RGBAImage {
        var pixels = bytes
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0 ..< 3 {
                pixels[index + channel] = UInt8(min((Int(pixels[index + channel]) * 255 + alpha / 2) / alpha, 255))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// A tile's PNG for the project, compressed (ImageIO).
    public static func png(_ image: RGBAImage) -> Data {
        let data = NSMutableData()
        guard let provider = CGDataProvider(data: Data(image.pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: image.width * 4,
                                    space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                                    decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return PNGCodec.encode(image) }
        CGImageDestinationAddImage(destination, cgImage, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : PNGCodec.encode(image)
    }
}

/// Paint carried onto a changed shape, made off the main thread and picked up by the next frame.
final class CarriedPaint: Sendable {
    struct Result: Sendable {
        var key: String
        var unwrap: PaintUnwrap
        var layers: [String: RGBAImage]
    }

    private let state = Mutex<(results: [ObjectID: Result], working: Set<String>)>(([:], []))

    /// The carried paint for this key, or nil (and the work started) when it isn't made yet.
    func result(for object: ObjectID, key: String, paint: ObjectPaint, source: MeshData, file: @escaping @Sendable (String) -> Data?,
                synchronously: Bool, ready: @escaping @Sendable () -> Void) -> Result? {
        let known: Result? = state.withLock { current in
            guard let result = current.results[object], result.key == key else { return nil }
            return result
        }
        if let known { return known }
        if synchronously {
            guard let made = Self.make(key: key, paint: paint, source: source, file: file) else { return nil }
            state.withLock { $0.results[object] = made }
            return made
        }
        let starts = state.withLock { $0.working.insert(key).inserted }
        guard starts else { return nil }
        Task.detached(priority: .userInitiated) { [self] in
            let made = Self.make(key: key, paint: paint, source: source, file: file)
            state.withLock { current in
                current.working.remove(key)
                if let made { current.results[object] = made }
            }
            if made != nil { ready() }
        }
        return nil
    }

    private static func make(key: String, paint: ObjectPaint, source: MeshData, file: (String) -> Data?) -> Result? {
        guard let (unwrap, layers) = PaintExport.current(paint, source: source, file: file) else { return nil }
        return Result(key: key, unwrap: unwrap, layers: layers)
    }
}
