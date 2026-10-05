import CoreGraphics
import Foundation
import LoweyCore

/// The brush engine in the editor: the brush a tool holds, its frozen copy in the project (a stroke always draws the
/// way it was drawn, whatever happens to the library), and the drawing guides that straighten or mirror a stroke.
extension EditorModel {
    func currentBrush(for tool: BrushTool) -> Brush {
        app.brushes.brush(for: tool)
    }

    /// The project's key for `brush` and, the first time a stroke here uses it, the command that adds its frozen copy
    /// (its pictures are copied into the project's assets first, so the project carries everything it draws with).
    func projectBrush(_ brush: Brush) -> (key: String, command: EditCommand?) {
        let key = BrushKey.key(for: brush)
        guard document.project.brushes[key] == nil else { return (key, nil) }
        for image in brush.imageKeys {
            let destination = assetsFolder.appendingPathComponent(image)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: app.brushes.store.imageURL(image), to: destination)
        }
        var frozen = brush
        frozen.id = key
        var brushes = document.project.brushes
        brushes[key] = frozen
        return (key, .setBrushes(brushes))
    }

    /// One undo step: the brush's first use (when it is one) and the stroke.
    @discardableResult
    func performStroke(_ command: EditCommand?, brush: EditCommand?, label: String = "Draw") -> Bool {
        guard let command else { return false }
        guard let brush else { return perform(command) }
        return perform(.batch(label, [brush, command]))
    }

    /// Every tenth stroke, the Pencil's touch-to-screen latency goes into the log (Diagnostics ▸ Export logs).
    func strokeEnded() {
        strokesDrawn += 1
        guard strokesDrawn % 10 == 0, let summary = stage?.strokeLatency.summary else { return }
        app.diagnostics.log("Pencil latency: " + summary)
    }

    /// A new stroke's jitter seed (kept by the stroke, so it draws the same in every frame and export).
    static func strokeSeed() -> UInt64 {
        UInt64.random(in: 1 ... UInt64.max)
    }

    // MARK: The frame's guide (flipbooks)

    /// A stage point in the frame guide's units: frame heights from the frame's centre, y up.
    func frameGuidePoint(_ point: CGPoint) -> Vec2 {
        let rect = frameRect
        let height = max(Double(rect.height), 1)
        return Vec2((Double(point.x) - Double(rect.midX)) / height, (Double(rect.midY) - Double(point.y)) / height)
    }

    func stagePoint(fromFrameGuide point: Vec2) -> CGPoint {
        let rect = frameRect
        return CGPoint(x: Double(rect.midX) + point.x * Double(rect.height), y: Double(rect.midY) - point.y * Double(rect.height))
    }

    /// The stroke as the frame's guide makes it: straightened along the guide, or mirrored into copies.
    func guidedOnFrame(_ points: [CGPoint]) -> [[CGPoint]] {
        guard let guide = frameGuide, guide.assisted, points.count > 1 else { return [points] }
        let onGuide = GuideAssist.constrained(points.map(frameGuidePoint), guide: guide)
        return GuideAssist.copies(onGuide, guide: guide).map { $0.map(stagePoint(fromFrameGuide:)) }
    }

    // MARK: The guide plane's guide (ink and solid shapes)

    /// The plane's two axes and origin (the guide plane's own grid: u across, v up the plane).
    func planeBasis(_ guide: GuideSurface?) -> (origin: Vec3, u: Vec3, v: Vec3)? {
        guard case let .plane(origin, normal) = guide else { return nil }
        let n = normal.normalized
        let up = abs(n.y) > 0.9 ? Vec3(0, 0, -1) : Vec3.unitY
        let u = up.cross(n).normalized
        return (origin, u, n.cross(u).normalized)
    }

    /// A stroke on the guide plane as its guide makes it (grid, isometric or symmetry on the plane).
    func guidedOnPlane(_ points: [Vec3], guide surface: GuideSurface?) -> [[Vec3]] {
        guard let guide = planeGuide, guide.assisted, points.count > 1, let basis = planeBasis(surface) else { return [points] }
        let flat = points.map { Vec2(($0 - basis.origin).dot(basis.u), ($0 - basis.origin).dot(basis.v)) }
        let onGuide = GuideAssist.constrained(flat, guide: guide)
        return GuideAssist.copies(onGuide, guide: guide).map { copy in
            copy.map { basis.origin + basis.u * $0.x + basis.v * $0.y }
        }
    }

    func setFrameGuide(_ guide: DrawingGuide?) {
        frameGuide = guide
        workspaceChanged()
        refreshGuide()
    }

    func setPlaneGuide(_ guide: DrawingGuide?) {
        planeGuide = guide
        workspaceChanged()
        refreshGuide()
    }
}
