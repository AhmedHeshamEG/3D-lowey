import Foundation

/// Camera move presets. Each generates editable keys on the camera (position, rotation, field of view),
/// starting from where the camera is at `start` and framed around a subject point.
public enum CameraMove: String, Codable, Sendable, CaseIterable, Identifiable {
    case pushIn, pullOut, punchIn, snapZoom, orbit, dolly, truck, crane, whipPan, shake, reveal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pushIn: "Push in"
        case .pullOut: "Pull out"
        case .punchIn: "Punch in"
        case .snapZoom: "Snap zoom"
        case .orbit: "Orbit"
        case .dolly: "Dolly"
        case .truck: "Truck"
        case .crane: "Crane"
        case .whipPan: "Whip pan"
        case .shake: "Shake"
        case .reveal: "Reveal"
        }
    }

    public var defaultDuration: Double {
        switch self {
        case .punchIn: 0.25
        case .snapZoom: 0.45
        case .whipPan: 0.35
        case .shake: 0.8
        case .pushIn, .pullOut: 2.5
        case .orbit: 4
        case .dolly, .truck, .crane: 3
        case .reveal: 3
        }
    }
}

public struct CameraMoveOptions: Hashable, Sendable {
    public var duration: Double
    /// 0…2: how strong (1 = default distances / angles).
    public var strength: Double

    public init(duration: Double, strength: Double = 1) {
        self.duration = duration
        self.strength = strength
    }
}

public enum CameraMoves {
    /// Keys for a move. `subject` is the point the shot is about (selection centre, or the focus point).
    public static func keys(
        _ move: CameraMove, camera: SceneObject, world: Transform, parentWorld: Transform, subject: Vec3, at start: Double,
        options: CameraMoveOptions
    ) -> [(PropertyKey, [Keyframe])] {
        let shot = CameraShot(camera: camera, world: world, parentWorld: parentWorld, subject: subject, start: start, options: options)
        switch move {
        case .pushIn, .pullOut, .dolly: return shot.travel(move)
        case .punchIn: return shot.punchIn()
        case .snapZoom: return shot.snapZoom()
        case .truck: return [shot.positionKeys([(0, shot.eye), (shot.d, shot.eye + shot.right * (2 * shot.s))])]
        case .crane: return shot.crane()
        case .orbit: return shot.orbit()
        case .whipPan: return shot.whipPan()
        case .shake: return shot.shake()
        case .reveal: return shot.reveal()
        }
    }

    /// Applies a move to a camera as one command (keys inside the move's span are replaced).
    public static func apply(
        _ move: CameraMove, camera id: ObjectID, subject: Vec3, at start: Double, options: CameraMoveOptions,
        current: Scene, timeline: Timeline, ids: inout IDFactory
    ) -> EditCommand? {
        guard let camera = current.objects[id] else { return nil }
        let parentWorld = camera.parent.map { current.worldTransform(of: $0) } ?? .identity
        let world = current.worldTransform(of: id)
        var edits: [TrackEdit] = []
        for (property, keys) in keys(move, camera: camera, world: world, parentWorld: parentWorld, subject: subject, at: start, options: options) {
            var track = timeline.track(for: id, property) ?? Track(id: ids.next(), target: id, property: property)
            if let first = keys.first?.time, let last = keys.last?.time {
                track.removeKeys(in: TimeRange(start: first, end: last))
            }
            for key in keys {
                track.setKey(key)
            }
            edits.append(TrackEdit(track))
        }
        return edits.isEmpty ? nil : .batch(move.title, [.setTracks(edits)])
    }

    /// Focus pull: animate the focus distance to `distance` over `duration`.
    public static func focusPull(camera id: ObjectID, to distance: Double, at start: Double, duration: Double, current: Scene,
                                 timeline: Timeline, ids: inout IDFactory) -> EditCommand? {
        guard let camera = current.objects[id] else { return nil }
        let from = camera[.focusDistance]?.floatValue ?? 5
        var track = timeline.track(for: id, .focusDistance) ?? Track(id: ids.next(), target: id, property: .focusDistance)
        track.removeKeys(in: TimeRange(start: start, end: start + duration))
        track.setKey(Keyframe(time: start, value: .float(from)))
        track.setKey(Keyframe(time: start + duration, value: .float(distance)))
        return .batch("Focus pull", [.setTracks([TrackEdit(track)])])
    }
}
