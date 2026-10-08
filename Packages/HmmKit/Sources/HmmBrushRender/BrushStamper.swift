#if canImport(Metal)
    import CoreGraphics
    import Foundation
    import HmmBrush
    import Metal
    import simd

    /// The brush engine's GPU half: turns strokes into stamp buffers (cached while they stay the same) and draws them
    /// with the pipeline the caller set. `BrushStroker` decides every stamp; this only uploads and draws.
    public final class BrushStamper {
        public let device: MTLDevice
        public let textures: BrushTextureCache
        private var strokeBuffers: [StrokeKey: (buffer: MTLBuffer, count: Int, lastUse: UInt64)] = [:]
        private var clock: UInt64 = 0

        /// A stroke's stamps depend on its path, brush and seed only.
        struct StrokeKey: Hashable {
            var points: [SIMD3<Float>]
            var widths: [Float]
            var alphas: [Float]
            var brush: String
            var seed: UInt64
        }

        public init(device: MTLDevice) throws {
            self.device = device
            textures = try BrushTextureCache(device: device)
        }

        // MARK: Buffers

        public func buffer(_ dabs: [BrushDabData]) -> MTLBuffer? {
            guard !dabs.isEmpty else { return nil }
            return dabs.withUnsafeBytes { bytes in
                bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
            }
        }

        /// A stroke's stamps (in the path's own units), built once per path. `key` names the brush: the same key
        /// must mean the same settings.
        public func stamps<P: BrushPoint>(_ path: BrushPath<P>, brush: Brush, key: String, seed: UInt64) -> (MTLBuffer, Int)? {
            let points = path.points.map { point -> SIMD3<Float> in
                let c = point.brushCoordinates
                return SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z))
            }
            let strokeKey = StrokeKey(points: points, widths: path.widths.map(Float.init), alphas: path.alphas.map(Float.init), brush: key,
                                      seed: seed)
            clock &+= 1
            if let entry = strokeBuffers[strokeKey] {
                strokeBuffers[strokeKey] = (entry.buffer, entry.count, clock)
                return (entry.buffer, entry.count)
            }
            let dabs = BrushStroker.dabs(path, brush: brush, seed: seed).map(BrushDabData.init)
            guard let buffer = buffer(dabs) else { return nil }
            strokeBuffers[strokeKey] = (buffer, dabs.count, clock)
            if strokeBuffers.count > 4096 {
                let recent = clock > 2048 ? clock - 2048 : 0
                strokeBuffers = strokeBuffers.filter { $0.value.lastUse >= recent }
            }
            return (buffer, dabs.count)
        }

        public func trim() {
            strokeBuffers.removeAll()
        }

        // MARK: Drawing

        /// The camera, for stamps in the world.
        public struct WorldView {
            public var viewProjection: simd_float4x4
            public var eye: SIMD3<Float>
            public var right: SIMD3<Float>
            public var up: SIMD3<Float>

            public init(viewProjection: simd_float4x4, view: simd_float4x4, eye: SIMD3<Float>) {
                self.viewProjection = viewProjection
                self.eye = eye
                // The view matrix's rows are the camera's axes in the world.
                right = SIMD3<Float>(view.columns.0.x, view.columns.1.x, view.columns.2.x)
                up = SIMD3<Float>(view.columns.0.y, view.columns.1.y, view.columns.2.y)
            }
        }

        /// Draws batches with the stamp pipeline already set on `encoder`. World batches need `view`.
        public func encode(_ batches: [BrushBatch], encoder: MTLRenderCommandEncoder, view: WorldView?, width: Int, height: Int,
                           image: (String) -> CGImage?) {
            for batch in batches where batch.count >= 1 {
                var uniforms = BrushUniforms(brush: batch.brush)
                uniforms.setViewport(width: width, height: height)
                uniforms.color = batch.color
                if let world = batch.world, let view {
                    uniforms.viewProjection = view.viewProjection
                    uniforms.model = world.model
                    uniforms.eye = SIMD4<Float>(view.eye, 1)
                    uniforms.cameraRight = SIMD4<Float>(view.right, world.scale)
                    uniforms.cameraUp = SIMD4<Float>(view.up, 0)
                } else if batch.world != nil {
                    continue
                } else if let placement = batch.placement {
                    uniforms.place(placement)
                }
                let (shape, grain) = textures.textures(for: batch.brush, image: image)
                encoder.setVertexBuffer(batch.dabs, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<BrushUniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BrushUniforms>.stride, index: 1)
                encoder.setFragmentTexture(shape, index: 0)
                encoder.setFragmentTexture(grain, index: 1)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: batch.count)
            }
        }

        /// Triangles (pixels, three corners each) in one premultiplied colour, with a fill pipeline set.
        public func encodeTriangles(_ corners: [Vec2], color: SIMD4<Float>, encoder: MTLRenderCommandEncoder, width: Int, height: Int) {
            guard !corners.isEmpty else { return }
            let points = corners.map { SIMD2<Float>(Float($0.x), Float($0.y)) }
            guard let buffer = points.withUnsafeBytes({ bytes in
                bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
            }) else { return }
            var uniforms = BrushFillUniforms(color: color, width: width, height: height)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<BrushFillUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BrushFillUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: points.count)
        }

        /// A premultiplied picture in a quad (pixels; corners top left, top right, bottom left, bottom right), times
        /// `opacity`, with the image pipeline set.
        public func encodeImage(_ texture: MTLTexture, corners: [Vec2], opacity: Float = 1, encoder: MTLRenderCommandEncoder, width: Int,
                                height: Int) {
            guard corners.count == 4 else { return }
            let uvs: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)]
            let vertices = zip(corners, uvs).map { SIMD4<Float>(Float($0.0.x), Float($0.0.y), $0.1.x, $0.1.y) }
            guard let buffer = vertices.withUnsafeBytes({ bytes in
                bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
            }) else { return }
            var uniforms = BrushFillUniforms(color: SIMD4<Float>(repeating: opacity), width: width, height: height)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<BrushFillUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BrushFillUniforms>.stride, index: 1)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    /// The brush shaders (Brush.metal, compiled into this module) and the pipelines over them.
    public enum BrushShaders {
        /// What a pipeline draws.
        public enum Pass: Sendable {
            /// Brush stamps: one instanced quad per dab.
            case stamp
            /// Flat triangles in one colour.
            case fill
            /// A whole layer laid over the target at an opacity.
            case layer
            /// A picture in a quad.
            case image

            var functions: (vertex: String, fragment: String) {
                switch self {
                case .stamp: ("hmm_brushVertex", "hmm_brushFragment")
                case .fill: ("hmm_brushFillVertex", "hmm_brushFillFragment")
                case .layer: ("hmm_brushLayerVertex", "hmm_brushLayerFragment")
                case .image: ("hmm_brushImageVertex", "hmm_brushImageFragment")
                }
            }
        }

        public static func library(device: MTLDevice) throws -> MTLLibrary {
            guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module), library.functionNames.contains("hmm_brushVertex") else {
                throw BrushRenderError.shaders
            }
            return library
        }

        /// A pipeline descriptor for a pass: its functions and premultiplied source-over blending on the first colour
        /// attachment. The caller sets the formats (and samples, depth) of its own target.
        public static func descriptor(_ pass: Pass, library: MTLLibrary) throws -> MTLRenderPipelineDescriptor {
            let names = pass.functions
            guard let vertex = library.makeFunction(name: names.vertex), let fragment = library.makeFunction(name: names.fragment) else {
                throw BrushRenderError.pipeline(names.fragment)
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            let color = descriptor.colorAttachments[0]
            color?.isBlendingEnabled = true
            color?.sourceRGBBlendFactor = .one
            color?.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color?.sourceAlphaBlendFactor = .one
            color?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return descriptor
        }

        /// A pipeline for a plain colour target of `format` (no depth, no multisampling).
        public static func pipeline(_ pass: Pass, format: MTLPixelFormat, device: MTLDevice, library: MTLLibrary) throws -> MTLRenderPipelineState {
            let descriptor = try descriptor(pass, library: library)
            descriptor.colorAttachments[0].pixelFormat = format
            descriptor.label = "brush \(pass)"
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                throw BrushRenderError.pipeline("\(pass): \(error.localizedDescription)")
            }
        }
    }
#endif
