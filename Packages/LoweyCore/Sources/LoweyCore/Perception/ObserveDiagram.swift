import Foundation
import HmmPerception

/// The shot camera as drawn on a layout diagram: where it stands and the two edges of what it sees.
public struct CameraGlyph: Hashable, Sendable {
    public var eye: FramePoint
    public var left: FramePoint
    public var right: FramePoint
}

/// A top, front or side diagram of the set: its orthographic camera, the same marks as the camera view, and the
/// shot camera drawn in (so a model sees where the camera is and what it looks at).
public struct ObserveDiagram: Hashable, Sendable {
    public var view: ObserveView
    public var camera: ObserveCamera
    public var marks: [Mark]
    public var shotCamera: CameraGlyph?
}

extension ShotObserver {
    /// The diagram for `view` at `time`, numbered like `report`. `aspect` is the diagram picture's.
    public func diagram(_ view: ObserveView, at time: Double, aspect: Double, report: ShotReport) -> ObserveDiagram {
        let animated = Animator.evaluate(document, at: time, rigs: rigs)
        let shot = ObserveCamera.shot(animated, fallback: document.scene.viewpoint, aspect: report.aspect)
        let bounds = SceneBounds(library: library)
        let boxes = report.objects.map { object in bounds.worldBounds(of: ObjectID(raw: object.id), in: animated.scene) }
        // Fit what's on stage (the set's floor and walls would make everything tiny) and the camera.
        let props = zip(report.objects, boxes).compactMap { object, box in object.isSet ? nil : box }
        let fitted = (props.isEmpty ? boxes.compactMap(\.self) : props).reduce(Bounds(min: shot.position, max: shot.position)) { $0.union($1) }
        let camera = ObserveCamera.diagram(view, fitting: fitted, aspect: aspect)
        let rects = boxes.map { box -> PerceptionRect in
            guard let box else { return PerceptionRect(x: 0, y: 0, width: 0, height: 0) }
            let points = box.corners.compactMap { camera.project($0) }
            let minX = points.map(\.x).min() ?? 0
            let minY = points.map(\.y).min() ?? 0
            let rect = PerceptionRect(x: minX, y: minY, width: (points.map(\.x).max() ?? 0) - minX, height: (points.map(\.y).max() ?? 0) - minY)
            return rect.intersection(PerceptionRect(x: 0, y: 0, width: 1, height: 1)) ?? PerceptionRect(x: rect.x, y: rect.y, width: 0, height: 0)
        }
        let marks = MarkLayout.place(rects, aspect: aspect).enumerated().map { index, mark in
            var mark = mark
            mark.number = report.objects[index].mark
            return mark
        }
        return ObserveDiagram(view: view, camera: camera, marks: marks, shotCamera: glyph(of: shot, on: camera, scale: fitted.size.maxComponent))
    }

    /// The shot camera's position and view edges seen from a diagram camera.
    func glyph(of shot: ObserveCamera, on diagram: ObserveCamera, scale: Double) -> CameraGlyph? {
        let halfWidth = atan(tan(shot.fieldOfView * .pi / 360) * shot.aspect)
        let reach = max(scale * 0.35, 1)
        let edge = { (angle: Double) in shot.position + Quat(angle: angle, axis: shot.up).act(shot.forward) * reach }
        guard let eye = diagram.project(shot.position), let left = diagram.project(edge(halfWidth)),
              let right = diagram.project(edge(-halfWidth)) else { return nil }
        return CameraGlyph(eye: eye, left: left, right: right)
    }
}
