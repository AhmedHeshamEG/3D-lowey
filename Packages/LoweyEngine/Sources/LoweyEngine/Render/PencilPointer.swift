import CoreGraphics
import LoweyCore
import Metal
import simd

/// The hovering Pencil on the stage (CONTEXT §4.4): a small point exactly under the tip, the same size at every
/// height, drawn in the editor layer of the frame being rendered (a SwiftUI overlay lands a frame late). The brush
/// outline shows only while the brush is being resized.
public struct PencilPointer: Sendable, Equatable {
    /// Where the tip is, in the view's unit square (0…1, y down).
    public var location: CGPoint
    /// The point's radius as a fraction of the view's height.
    public var dotRadius: Double
    /// The brush outline's radius as a fraction of the view's height (nil = no outline).
    public var outlineRadius: Double?

    public init(location: CGPoint, dotRadius: Double, outlineRadius: Double? = nil) {
        self.location = location
        self.dotRadius = dotRadius
        self.outlineRadius = outlineRadius
    }

    /// A pointer for a point in a view of `size` points: a 2.5 pt point, an outline of `outline` points.
    public init?(at point: CGPoint, in size: CGSize, outline: Double? = nil) {
        guard size.width > 0, size.height > 0 else { return nil }
        self.init(location: CGPoint(x: point.x / size.width, y: point.y / size.height), dotRadius: 2.5 / size.height,
                  outlineRadius: outline.map { $0 / size.height })
    }
}

extension LoweyRenderer {
    /// A dark rim and a light centre (readable on any Look), and the outline ring facing the camera; always on top.
    func pointerDraws(_ pointer: PencilPointer, camera: RenderCamera, aspect: Double) -> [EditorDraw] {
        let ray = camera.ray(through: CGPoint(x: pointer.location.x * aspect, y: pointer.location.y), in: CGSize(width: aspect, height: 1))
        // Just past the near plane, so nothing in the scene can hide it.
        let distance = Double(camera.near) * 4
        let depth = distance * max(ray.direction.dot(Vec3(camera.forward)), 1e-3)
        let worldPerHeight = 2 * tan(Double(camera.fieldOfView) * .pi / 360) * depth
        let center = ray.origin + ray.direction * distance
        var draws = [dot(at: center, radius: pointer.dotRadius * 1.6 * worldPerHeight, color: SIMD4<Float>(0.05, 0.05, 0.06, 0.9)),
                     dot(at: center, radius: pointer.dotRadius * worldPerHeight, color: SIMD4<Float>(0.97, 0.97, 0.98, 1))]
        if let outline = pointer.outlineRadius {
            let radius = outline * worldPerHeight / EditorScene.ringRadius
            let facing = Quat.rotation(from: .unitY, to: (Vec3(camera.position) - center).normalized)
            let model = LoweyCore.Transform(position: center, rotation: facing, scale: Vec3(radius, radius, radius)).matrix
            draws.append(EditorDraw(mesh: editorMeshes.ring, item: EditorItemUniforms(model: model, color: SIMD4<Float>(0.97, 0.97, 0.98, 0.9),
                                                                                      params: .zero), depthTested: false))
        }
        return draws
    }

    private func dot(at center: Vec3, radius: Double, color: SIMD4<Float>) -> EditorDraw {
        // The helper sphere stands on its base: lower it by its radius so it's centred on the tip.
        let model = LoweyCore.Transform(position: center - Vec3(0, radius, 0), scale: Vec3(radius * 2, radius * 2, radius * 2)).matrix
        return EditorDraw(mesh: editorMeshes.sphere, item: EditorItemUniforms(model: model, color: color, params: .zero), depthTested: false)
    }
}
