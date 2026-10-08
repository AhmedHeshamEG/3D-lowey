import CoreGraphics
import LoweyCore
import Metal

// The brush engine's GPU half (the stamp shader, `BrushStamper`, tip and grain textures) is hmm-kit's HmmBrushRender:
// the Schizzo board draws with it too. Everything in the engine sees it through this one line.
@_exported import HmmBrushRender

extension BrushStamper {
    /// A filled shape (pixels) in one premultiplied colour, with the fill pipeline set.
    func encodeFill(_ outline: [Vec2], color: SIMD4<Float>, encoder: MTLRenderCommandEncoder, width: Int, height: Int) {
        guard outline.count >= 3 else { return }
        let area = zip(outline, outline.dropFirst() + [outline[0]]).reduce(0) { $0 + $1.0.cross($1.1) }
        let ordered = area < 0 ? Array(outline.reversed()) : outline
        let triangles = PolygonTriangulator.triangulate(outline: ordered.enumerated().map { (vertex: $0.offset, point: $0.element) }, holes: [])
        encodeTriangles(triangles.flatMap { [ordered[$0.0], ordered[$0.1], ordered[$0.2]] }, color: color, encoder: encoder, width: width,
                        height: height)
    }
}
