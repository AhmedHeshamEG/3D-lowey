import Foundation

/// Where a flipbook track sits in a frame of pixels: the anchor's centre and how many pixels one drawing unit is.
public struct FlipbookAnchorFrame: Hashable, Sendable {
    /// Pixels from the top left.
    public var center: Vec2
    public var pixelsPerUnit: Double

    /// A drawing point (units, y up) in pixels (y down).
    public func pixel(_ point: Vec2) -> Vec2 {
        Vec2(center.x + point.x * pixelsPerUnit, center.y - point.y * pixelsPerUnit)
    }

    /// A pixel back in drawing units.
    public func point(_ pixel: Vec2) -> Vec2 {
        Vec2((pixel.x - center.x) / pixelsPerUnit, (center.y - pixel.y) / pixelsPerUnit)
    }
}

/// A stroke ready to draw: pixels, half-widths in pixels, a resolved colour.
public struct FlipbookPixelStroke: Hashable, Sendable {
    public var points: [Vec2]
    public var widths: [Double]
    public var color: RGBA
    public var filled: Bool

    public init(points: [Vec2], widths: [Double], color: RGBA, filled: Bool) {
        self.points = points
        self.widths = widths
        self.color = color
        self.filled = filled
    }
}

/// One visible flipbook drawing at a moment.
public struct FlipbookDraw: Hashable, Sendable {
    public var track: String
    public var blend: FlipbookBlend
    public var opacity: Double
    public var strokes: [FlipbookPixelStroke]
}

/// Lays out the flipbooks of a moment for a frame of `width` × `height` pixels. `project` maps a world point to
/// normalised device coordinates (−1…1, y up) and its distance in front of the camera (nil behind it).
public struct FlipbookLayout {
    public var width: Double
    public var height: Double
    /// Vertical field of view in degrees.
    public var fieldOfView: Double
    public var project: (Vec3) -> (x: Double, y: Double, depth: Double)?

    public init(width: Double, height: Double, fieldOfView: Double, project: @escaping (Vec3) -> (x: Double, y: Double, depth: Double)?) {
        self.width = width
        self.height = height
        self.fieldOfView = fieldOfView
        self.project = project
    }

    /// A frame seen through a camera at `camera` (vertical field of view in degrees).
    public init(width: Double, height: Double, camera: Transform, fieldOfView: Double) {
        let aspect = width / max(height, 1)
        self.init(width: width, height: height, fieldOfView: fieldOfView) { point in
            guard let ndc = OverlayLayout.project(point, camera: camera, fieldOfView: fieldOfView, aspect: aspect) else { return nil }
            return (ndc.0, ndc.1, -camera.rotation.inverse.act(point - camera.position).z)
        }
    }

    /// The pixel frame of a track's anchor in `scene` (nil when its object is gone or behind the camera).
    public func anchorFrame(_ track: FlipbookTrack, in scene: Scene) -> FlipbookAnchorFrame? {
        switch track.anchor {
        case .camera:
            let center = Vec2(width / 2 + track.offset.x * height, height / 2 - track.offset.y * height)
            return FlipbookAnchorFrame(center: center, pixelsPerUnit: height)
        case let .object(id):
            guard scene.objects[id] != nil, let ndc = project(scene.worldTransform(of: id).position), ndc.depth > 1e-3 else { return nil }
            let focal = 1 / tan(min(max(fieldOfView, 1), 170) * .pi / 360)
            let pixelsPerMetre = height / 2 * focal / ndc.depth
            let pivot = Vec2((ndc.x + 1) / 2 * width, (1 - ndc.y) / 2 * height)
            let center = Vec2(pivot.x + track.offset.x * pixelsPerMetre, pivot.y - track.offset.y * pixelsPerMetre)
            return FlipbookAnchorFrame(center: center, pixelsPerUnit: pixelsPerMetre)
        }
    }

    /// Every flipbook drawing visible at `time`, bottom track first.
    public func draws(_ timeline: Timeline, scene: Scene, palette: Palette, at time: Double) -> [FlipbookDraw] {
        timeline.flipbooks.compactMap { track in
            guard track.visible, track.opacity > 0.001,
                  let index = track.frameIndex(at: time, fps: timeline.fps, sceneDuration: timeline.duration),
                  let frame = anchorFrame(track, in: scene) else { return nil }
            let strokes = track.frames[index].strokes.map { stroke in
                FlipbookPixelStroke(points: stroke.points.map(frame.pixel), widths: stroke.widths.map { $0 * frame.pixelsPerUnit },
                                    color: stroke.color.resolved(in: palette), filled: stroke.filled)
            }
            return strokes.isEmpty ? nil : FlipbookDraw(track: track.id, blend: track.blend, opacity: track.opacity, strokes: strokes)
        }
    }

    /// The outline of a pressure stroke in pixels: left side forward, right side back (a closed polygon). Single points
    /// become a small diamond.
    public static func outline(_ stroke: FlipbookPixelStroke) -> [Vec2] {
        let points = stroke.points
        guard points.count >= 2 else {
            guard let p = points.first else { return [] }
            let r = max(stroke.widths.first ?? 1, 0.5)
            return [Vec2(p.x + r, p.y), Vec2(p.x, p.y + r), Vec2(p.x - r, p.y), Vec2(p.x, p.y - r)]
        }
        var left: [Vec2] = []
        var right: [Vec2] = []
        for index in points.indices {
            let previous = points[max(index - 1, 0)]
            let next = points[min(index + 1, points.count - 1)]
            let direction = next - previous
            let length = max(direction.length, 1e-9)
            let normal = Vec2(-direction.y / length, direction.x / length)
            let width = max(stroke.widths[index], 0.35)
            left.append(points[index] + normal * width)
            right.append(points[index] - normal * width)
        }
        return left + right.reversed()
    }
}
