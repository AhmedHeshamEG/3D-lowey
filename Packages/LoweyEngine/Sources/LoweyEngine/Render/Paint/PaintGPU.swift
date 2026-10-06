import CoreGraphics
import LoweyCore
import Metal
import simd

/// The pipelines of painting on models (Paint.metal).
struct PaintPipelines {
    /// A stroke or picture laid on a layer through the camera.
    let project: MTLRenderPipelineState
    /// The eraser: the same projection wiping paint off.
    let erase: MTLRenderPipelineState
    /// Which texels the unwrap uses.
    let coverage: MTLRenderPipelineState
    /// One layer over the layers under it.
    let compose: MTLRenderPipelineState
    /// The composite, straight-alpha and pushed past chart edges.
    let finish: MTLRenderPipelineState

    init(_ builder: PipelineBuilder) throws {
        project = try builder.paint(fragment: "lw_paintProject", write: .over)
        erase = try builder.paint(fragment: "lw_paintProject", write: .erase)
        coverage = try builder.paint(fragment: "lw_paintCoverage", format: .r8Unorm, write: .replace)
        compose = try builder.paint(vertex: "lw_paintFullVertex", fragment: "lw_paintCompose", write: .replace)
        finish = try builder.paint(vertex: "lw_paintFullVertex", fragment: "lw_paintFinish", write: .replace)
    }
}

/// Swift mirror of `PaintUniforms` in Paint.metal.
struct PaintUniforms {
    var model = matrix_identity_float4x4
    var normalMatrix = matrix_identity_float4x4
    var viewProjection = matrix_identity_float4x4
    var eye = SIMD4<Float>.zero
    var forward = SIMD4<Float>(0, 0, -1, 0)
    var screen = SIMD4<Float>(1, 1, 1, 1)
    var params = SIMD4<Float>.zero
}

/// The stroke being painted on a model, drawn into its layer by the frame that shows it.
public struct LivePaint {
    public enum Source {
        /// The brush engine's stamps, in the stage's points.
        case stamps([BrushDab<Vec2>], brush: Brush)
        /// A picture laid over the stage (points), projected onto what the camera sees.
        case picture(CGImage, rect: CGRect)
    }

    public var object: ObjectID
    public var layer: String
    /// Changes with every new stroke: a new one keeps the layer as it was before it, to paint over again each frame.
    public var stroke: Int
    public var source: Source
    /// sRGB, the stroke's opacity in `a`.
    public var color: RGBA
    public var erases: Bool
    /// The stage's points to pixels.
    public var pixelsPerPoint: Double

    public init(object: ObjectID, layer: String, stroke: Int, source: Source, color: RGBA, erases: Bool, pixelsPerPoint: Double) {
        self.object = object
        self.layer = layer
        self.stroke = stroke
        self.source = source
        self.color = color
        self.erases = erases
        self.pixelsPerPoint = pixelsPerPoint
    }
}

/// A layer's pixels after a stroke: the tiles it changed, straight alpha.
public struct PaintedTiles: Sendable {
    public var object: ObjectID
    public var layer: String
    public var tiles: [PaintTileIndex: RGBAImage]

    public init(object: ObjectID, layer: String, tiles: [PaintTileIndex: RGBAImage]) {
        self.object = object
        self.layer = layer
        self.tiles = tiles
    }
}
