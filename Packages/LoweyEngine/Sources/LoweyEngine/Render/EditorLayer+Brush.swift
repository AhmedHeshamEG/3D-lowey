import CoreGraphics
import LoweyCore
import Metal
import simd

/// The stroke under the Pencil, stamped by the brush engine exactly as it will land: in the world for ink (turned to
/// the camera, hidden behind what stands in front), on the screen for flipbooks.
public struct LiveBrushStroke: Sendable {
    public enum Stamps: Sendable {
        /// World space (ink).
        case world([BrushDab<Vec3>])
        /// The stage's points, from its top left (flipbooks); the stage turns them into pixels.
        case screen([BrushDab<Vec2>])
    }

    public var stamps: Stamps
    public var brush: Brush
    /// sRGB (the editor layer draws over the encoded frame).
    public var color: RGBA

    public init(stamps: Stamps, brush: Brush, color: RGBA) {
        self.stamps = stamps
        self.brush = brush
        self.color = color
    }

    /// The same stroke with its screen stamps scaled from points to pixels.
    func inPixels(_ scale: Double) -> LiveBrushStroke {
        guard case let .screen(dabs) = stamps, scale != 1 else { return self }
        var copy = self
        copy.stamps = .screen(dabs.map { dab in
            var moved = dab
            moved.center = dab.center * scale
            moved.radius = dab.radius * scale
            moved.lateral = dab.lateral * scale
            return moved
        })
        return copy
    }
}

/// A drawing guide's lines over the stage (a flipbook's frame), in the stage's points from its top left.
public struct ScreenGuide: Sendable, Equatable {
    public var lines: [GuideLines.Line]
    public var color: RGBA

    public init(lines: [GuideLines.Line], color: RGBA) {
        self.lines = lines
        self.color = color
    }
}

extension LoweyRenderer {
    /// The live stroke and the 2D guide, after the editor layer's meshes.
    func encodeEditorBrushes(_ editor: EditorScene, request: FrameRequest, output: MTLTexture, encoder: MTLRenderCommandEncoder) {
        if let guide = editor.screenGuide, !guide.lines.isEmpty {
            encoder.setRenderPipelineState(device.pipelines.brushFillEditor)
            encoder.setDepthStencilState(device.pipelines.depthAlways)
            for major in [false, true] {
                let width = (major ? 1.5 : 0.75) * editor.pixelsPerPoint
                let alpha = Float(major ? 0.7 : 0.35)
                let outline = guide.lines.filter { $0.major == major }.flatMap { Self.quad($0, scale: editor.pixelsPerPoint, width: width) }
                let color = SIMD4<Float>(guide.color.srgbVector * alpha, alpha)
                stamper.encodeTriangles(outline, color: color, encoder: encoder, width: output.width, height: output.height)
            }
        }
        guard let live = editor.liveStroke else { return }
        let color = SIMD4<Float>(live.color.srgbVector, 1)
        let dabs: [BrushDabData]
        var world: (simd_float4x4, Float)?
        switch live.stamps {
        case let .world(stamps):
            dabs = stamps.map(BrushDabData.init)
            world = (matrix_identity_float4x4, 1)
        case let .screen(stamps):
            dabs = stamps.map(BrushDabData.init)
        }
        guard let buffer = stamper.buffer(dabs) else { return }
        encoder.setRenderPipelineState(device.pipelines.brushEditor)
        encoder.setDepthStencilState(world == nil ? device.pipelines.depthAlways : device.pipelines.depthRead)
        let camera = request.camera
        let aspect = Float(output.width) / Float(max(output.height, 1))
        let view = BrushStamper.WorldView(viewProjection: camera.projection(aspect: aspect) * camera.viewMatrix, view: camera.viewMatrix,
                                          eye: camera.position)
        stamper.encode([BrushBatch(dabs: buffer, count: dabs.count, brush: live.brush, color: color, world: world)], encoder: encoder,
                       view: view, width: output.width, height: output.height, image: request.input.mediaImage)
    }

    /// A line as two triangles in pixels.
    static func quad(_ line: GuideLines.Line, scale: Double, width: Double) -> [Vec2] {
        let a = line.from * scale, b = line.to * scale
        let along = b - a
        let length = along.length
        guard length > 1e-9 else { return [] }
        let side = Vec2(-along.y / length, along.x / length) * (width / 2)
        return [a + side, a - side, b + side, b + side, a - side, b - side]
    }
}
