#if canImport(Metal) && canImport(CoreText)
    import CoreGraphics
    import Foundation
    import HmmBoard
    import HmmBrush
    import HmmBrushRender
    import Metal

    /// What one frame of the canvas shows.
    public struct BoardScene {
        public var board: Board
        /// What changed on the board since the last frame.
        public var changes = BoardChanges()
        public var viewport: BoardViewport
        /// The view's size in points, and its pixels per point.
        public var size: Vec2
        public var contentScale: Double
        /// Fingers are panning or pinching (the layer may be shown stretched).
        public var interacting = false
        /// Items a drag carries: left out of the board's layer and drawn from `lifted`, where the drag has them.
        public var hidden: Set<String> = []
        public var lifted: [BoardItem] = []
        /// The stroke under the Pencil and the brush it's drawn with.
        public var liveStroke: BoardStroke?
        public var liveBrush: Brush = BuiltInBrushes.inkPen
        public var editingNote: String?
        public var overlay: BoardDrawList.Overlay

        public init(board: Board, viewport: BoardViewport, size: Vec2, contentScale: Double, overlay: BoardDrawList.Overlay) {
            self.board = board
            self.viewport = viewport
            self.size = size
            self.contentScale = contentScale
            self.overlay = overlay
        }
    }

    /// Draws a board with Metal: brush strokes with the brush engine's stamps, everything else as flat shapes and
    /// pictures. The board is kept in one layer a little larger than the screen (`BoardLayerPlan`); a frame is that
    /// layer plus whatever is moving: the stroke under the Pencil, what a drag carries, the selection's marks.
    @MainActor
    public final class BoardRenderer {
        public static let format = MTLPixelFormat.bgra8Unorm
        /// A stroke's widest part is never drawn thinner than this many pixels, however far out the view is.
        static let hairline: Float = 0.45

        public let device: MTLDevice
        public let queue: MTLCommandQueue
        private let stamper: BrushStamper
        private let textures: BoardTextures
        private let pipelines: [BrushShaders.Pass: MTLRenderPipelineState]
        private var layer: Layer?
        /// A brush's own tip or grain picture (`brushes/<hash>.png`), for brushes that weren't built in.
        public var brushImage: (String) -> CGImage? = { _ in nil }

        private struct Layer {
            var texture: MTLTexture
            var plan: BoardLayerPlan
            var hidden: Set<String>
            var editingNote: String?
        }

        public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
            guard let device, let queue = device.makeCommandQueue() else { throw BrushRenderError.texture }
            self.device = device
            self.queue = queue
            queue.label = "Board"
            stamper = try BrushStamper(device: device)
            textures = BoardTextures(device: device, queue: queue)
            let library = try BrushShaders.library(device: device)
            var made: [BrushShaders.Pass: MTLRenderPipelineState] = [:]
            for pass in [BrushShaders.Pass.stamp, .fill, .image] {
                made[pass] = try BrushShaders.pipeline(pass, format: Self.format, device: device, library: library)
            }
            pipelines = made
        }

        /// Where the board's pictures are.
        public var assetURL: (String) -> URL? {
            get { textures.assetURL }
            set {
                textures.assetURL = newValue
                textures.removeAll()
                layer = nil
            }
        }

        /// Draws everything again next frame (the board was replaced, memory was short).
        public func invalidate() {
            layer = nil
        }

        // MARK: A frame

        /// Draws a frame into `target` (a drawable's texture, in `format`).
        public func draw(_ scene: BoardScene, to target: MTLTexture, commandBuffer: MTLCommandBuffer) {
            let pixelsPerUnit = scene.viewport.scale * scene.contentScale
            let visible = scene.viewport.visibleRect(size: scene.size)
            prepareLayer(scene, visible: visible, pixelsPerUnit: pixelsPerUnit, commandBuffer: commandBuffer)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass(target, clear: scene.board.paper.color)) else { return }
            encoder.label = "Board frame"
            let screen = BoardPlacement(viewport: scene.viewport, size: scene.size, contentScale: scene.contentScale)
            if let layer, let image = pipelines[.image] {
                encoder.setRenderPipelineState(image)
                stamper.encodeImage(layer.texture, corners: screen.corners(layer.plan.region), encoder: encoder, width: target.width,
                                    height: target.height)
            }
            var draws = BoardDrawList.items(scene.lifted, on: scene.board, placement: screen, editingNote: scene.editingNote,
                                            contentScale: scene.contentScale)
            if let live = scene.liveStroke { draws.append(.stroke(live, brush: scene.liveBrush)) }
            draws += BoardDrawList.overlay(scene.overlay, placement: screen, contentScale: scene.contentScale)
            encode(draws, placement: screen, encoder: encoder, width: target.width, height: target.height)
            encoder.endEncoding()
        }

        /// Makes the layer serve this frame: drawn again when the view left it or the board changed under it, new
        /// strokes laid on top when that is all that happened.
        private func prepareLayer(_ scene: BoardScene, visible: BoardRect, pixelsPerUnit: Double, commandBuffer: MTLCommandBuffer) {
            let serves = layer.map { current in
                current.plan.serves(visible: visible, pixelsPerUnit: pixelsPerUnit, interacting: scene.interacting)
                    && current.hidden == scene.hidden && current.editingNote == scene.editingNote && !scene.changes.rebuild
            } ?? false
            guard serves, let current = layer else {
                redrawLayer(scene, visible: visible, pixelsPerUnit: pixelsPerUnit, commandBuffer: commandBuffer)
                return
            }
            let added = scene.board.items.filter { scene.changes.appended.contains($0.id) && !scene.hidden.contains($0.id) }
            guard !added.isEmpty else { return }
            let descriptor = pass(current.texture, clear: nil)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            encoder.label = "Board layer (new strokes)"
            let placement = BoardPlacement(region: current.plan.region, pixelsPerUnit: current.plan.pixelsPerUnit)
            let draws = BoardDrawList.items(added, on: scene.board, placement: placement, clip: current.plan.region, editingNote: scene.editingNote,
                                            contentScale: scene.contentScale)
            encode(draws, placement: placement, encoder: encoder, width: current.texture.width, height: current.texture.height)
            encoder.endEncoding()
        }

        private func redrawLayer(_ scene: BoardScene, visible: BoardRect, pixelsPerUnit: Double, commandBuffer: MTLCommandBuffer) {
            let plan = BoardLayerPlan(visible: visible, pixelsPerUnit: pixelsPerUnit)
            let reusable = layer.map { $0.texture.width == plan.pixelWidth && $0.texture.height == plan.pixelHeight } ?? false
            guard let texture = reusable ? layer?.texture : makeTarget(width: plan.pixelWidth, height: plan.pixelHeight, shared: false) else {
                layer = nil
                return
            }
            layer = Layer(texture: texture, plan: plan, hidden: scene.hidden, editingNote: scene.editingNote)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass(texture, clear: scene.board.paper.color)) else { return }
            encoder.label = "Board layer"
            let placement = BoardPlacement(region: plan.region, pixelsPerUnit: pixelsPerUnit)
            var draws = BoardDrawList.paper(scene.board.paper, over: plan.region, placement: placement, viewScale: scene.viewport.scale,
                                            contentScale: scene.contentScale)
            let shown = scene.board.items.filter { !scene.hidden.contains($0.id) }
            draws += BoardDrawList.items(shown, on: scene.board, placement: placement, clip: plan.region, editingNote: scene.editingNote,
                                         contentScale: scene.contentScale)
            encode(draws, placement: placement, encoder: encoder, width: texture.width, height: texture.height)
            encoder.endEncoding()
        }

        // MARK: A picture of the board

        /// A picture of a part of the board on its paper: a pin, a shared image. `items` nil shows everything in the
        /// region. Its long side is at most `maximumSide` pixels.
        public func snapshot(of board: Board, items: Set<String>? = nil, region: BoardRect, pixelsPerUnit: Double,
                             maximumSide: Int = 4096) -> CGImage? {
            let longest = max(region.width, region.height) * pixelsPerUnit
            guard longest > 0 else { return nil }
            let scale = longest > Double(maximumSide) ? pixelsPerUnit * Double(maximumSide) / longest : pixelsPerUnit
            let plan = BoardLayerPlan(region: region, pixelsPerUnit: scale)
            guard let texture = makeTarget(width: plan.pixelWidth, height: plan.pixelHeight, shared: true),
                  let commandBuffer = queue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass(texture, clear: board.paper.color)) else { return nil }
            encoder.label = "Board picture"
            let placement = BoardPlacement(region: region, pixelsPerUnit: scale)
            let shown = board.items.filter { items?.contains($0.id) ?? true }
            let draws = BoardDrawList.items(shown, on: board, placement: placement, clip: region, contentScale: max(scale, 1))
            encode(draws, placement: placement, encoder: encoder, width: texture.width, height: texture.height)
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            return Self.image(from: texture)
        }

        static func image(from texture: MTLTexture) -> CGImage? {
            let width = texture.width, height = texture.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                texture.getBytes(base, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
            guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
            // BGRA in memory: 32-bit little-endian with alpha first.
            let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                           space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider,
                           decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }

        // MARK: Drawing a list

        private func makeTarget(width: Int, height: Int, shared: Bool) -> MTLTexture? {
            guard width > 0, height > 0, width <= 16384, height <= 16384 else { return nil }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.format, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = shared ? .shared : .private
            let texture = device.makeTexture(descriptor: descriptor)
            texture?.label = "Board layer"
            return texture
        }

        /// A pass into `texture`: cleared to a colour, or (nil) keeping what is there.
        private func pass(_ texture: MTLTexture, clear: BoardColor?) -> MTLRenderPassDescriptor {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].storeAction = .store
            if let clear {
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].clearColor = MTLClearColor(red: clear.red, green: clear.green, blue: clear.blue, alpha: 1)
            } else {
                pass.colorAttachments[0].loadAction = .load
            }
            return pass
        }

        private func encode(_ draws: [BoardDraw], placement: BoardPlacement, encoder: MTLRenderCommandEncoder, width: Int, height: Int) {
            var current: BrushShaders.Pass?
            func use(_ pass: BrushShaders.Pass) -> Bool {
                guard let pipeline = pipelines[pass] else { return false }
                if current != pass { encoder.setRenderPipelineState(pipeline) }
                current = pass
                return true
            }
            for draw in draws {
                switch draw {
                case let .stroke(stroke, brush):
                    guard use(.stamp), let batch = strokeBatch(stroke, brush: brush, placement: placement) else { continue }
                    stamper.encode([batch], encoder: encoder, view: nil, width: width, height: height, image: brushImage)
                case let .fill(triangles, color, opacity):
                    guard use(.fill) else { continue }
                    let alpha = Float(opacity)
                    let premultiplied = SIMD4<Float>(Float(color.red) * alpha, Float(color.green) * alpha, Float(color.blue) * alpha, alpha)
                    stamper.encodeTriangles(triangles, color: premultiplied, encoder: encoder, width: width, height: height)
                case let .picture(asset, corners):
                    if let texture = textures.picture(asset) {
                        guard use(.image) else { continue }
                        stamper.encodeImage(texture, corners: corners, encoder: encoder, width: width, height: height)
                    } else if use(.fill), corners.count == 4 {
                        // A picture whose file is gone keeps its place as a grey card.
                        let card = [corners[0], corners[1], corners[2], corners[1], corners[3], corners[2]]
                        stamper.encodeTriangles(card, color: SIMD4<Float>(0.3, 0.3, 0.32, 0.6), encoder: encoder, width: width, height: height)
                    }
                case let .text(spec, corners):
                    guard let texture = textures.text(spec), use(.image) else { continue }
                    stamper.encodeImage(texture, corners: corners, encoder: encoder, width: width, height: height)
                }
            }
        }

        /// A stroke's stamps, placed by the shader. Kept strokes' stamps are cached by the stamper; the one under the
        /// Pencil changes every frame and isn't.
        private func strokeBatch(_ stroke: BoardStroke, brush: Brush, placement: BoardPlacement) -> BrushBatch? {
            let stamps: (MTLBuffer, Int)?
            if let key = stroke.brush {
                stamps = stamper.stamps(stroke.path, brush: brush, key: key, seed: stroke.seed)
            } else {
                let dabs = BrushStroker.dabs(stroke.path, brush: brush, seed: stroke.seed).map(BrushDabData.init)
                stamps = stamper.buffer(dabs).map { ($0, dabs.count) }
            }
            guard let (buffer, count) = stamps else { return nil }
            let scale = Float(placement.scale)
            let widest = Float(stroke.path.widths.max() ?? 1)
            let radiusScale = max(scale, Self.hairline / max(widest, 1e-6))
            let place = BrushBatch.Placement(offset: SIMD2<Float>(Float(placement.offset.x), Float(placement.offset.y)), scale: scale,
                                             radiusScale: radiusScale)
            let color = SIMD4<Float>(Float(stroke.color.red), Float(stroke.color.green), Float(stroke.color.blue), 1)
            return BrushBatch(dabs: buffer, count: count, brush: brush, color: color, placement: place)
        }
    }
#endif
