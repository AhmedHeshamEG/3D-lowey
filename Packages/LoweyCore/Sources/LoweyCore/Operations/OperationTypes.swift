import Foundation

/// Array layouts ("20 fence posts in a line", "a grid of desks", "chairs around a table").
public enum ArrayLayout: Hashable, Sendable, Codable {
    case line(count: Int, step: Vec3)
    case grid(columns: Int, rows: Int, spacingX: Double, spacingZ: Double)
    case circle(count: Int, radius: Double, faceCenter: Bool)
    /// Copies spaced evenly along a path in the world (a sketch's curve), starting where the object is; `align`
    /// turns each copy with the path.
    case path(count: Int, points: [Vec3], closed: Bool, align: Bool)
}

/// Scatter settings. Defaults give good results with no tweaking.
public struct ScatterSettings: Hashable, Sendable, Codable {
    public var count: Int
    public var radius: Double
    /// Random yaw range in degrees (0...360).
    public var rotationJitter: Double
    /// Uniform scale range.
    public var scaleMin: Double
    public var scaleMax: Double
    /// Minimum distance between copies relative to the object's footprint (0 = allow overlap).
    public var spacing: Double
    public var seed: UInt64

    public init(count: Int = 20, radius: Double = 5, rotationJitter: Double = 360, scaleMin: Double = 0.8,
                scaleMax: Double = 1.25, spacing: Double = 0.8, seed: UInt64 = 1) {
        self.count = count
        self.radius = radius
        self.rotationJitter = rotationJitter
        self.scaleMin = scaleMin
        self.scaleMax = scaleMax
        self.spacing = spacing
        self.seed = seed
    }
}

public enum AlignMode: String, Sendable, Codable, CaseIterable {
    case min, center, max
}

/// Snapping configuration.
public struct SnapSettings: Hashable, Sendable, Codable {
    public var grid: Bool
    public var gridSize: Double
    public var rotation: Bool
    public var rotationStep: Double
    public var ground: Bool
    public var objects: Bool
    /// How close (m) a face must be to snap to another object.
    public var objectThreshold: Double

    public init(grid: Bool = false, gridSize: Double = 0.25, rotation: Bool = true, rotationStep: Double = 15,
                ground: Bool = true, objects: Bool = true, objectThreshold: Double = 0.12) {
        self.grid = grid
        self.gridSize = gridSize
        self.rotation = rotation
        self.rotationStep = rotationStep
        self.ground = ground
        self.objects = objects
        self.objectThreshold = objectThreshold
    }
}

public enum Snapping {
    public static func snapToGrid(_ value: Double, size: Double) -> Double {
        guard size > 0 else { return value }
        return (value / size).rounded() * size
    }

    public static func snapToGrid(_ point: Vec3, size: Double, includeY: Bool = false) -> Vec3 {
        Vec3(snapToGrid(point.x, size: size), includeY ? snapToGrid(point.y, size: size) : point.y, snapToGrid(point.z, size: size))
    }

    public static func snapAngle(_ degrees: Double, step: Double) -> Double {
        guard step > 0 else { return degrees }
        return (degrees / step).rounded() * step
    }

    /// Snaps the moving bounds' faces to nearby faces of other bounds (flush placement,
    /// like stacking Lego). Returns the correction to add to the position.
    public static func objectSnapOffset(moving: Bounds, others: [Bounds], threshold: Double) -> Vec3 {
        var correction = Vec3.zero
        for axis in Axis.allCases {
            var best: Double?
            for other in others {
                // Only consider objects overlapping on the other two axes (touching neighbours).
                let otherAxes = Axis.allCases.filter { $0 != axis }
                let overlaps = otherAxes.allSatisfy { a in
                    moving.min[a] <= other.max[a] + threshold && moving.max[a] >= other.min[a] - threshold
                }
                guard overlaps else { continue }
                let candidates = [
                    other.max[axis] - moving.min[axis], // sit against the far face
                    other.min[axis] - moving.max[axis], // sit against the near face
                    other.min[axis] - moving.min[axis], // align min faces
                    other.max[axis] - moving.max[axis], // align max faces
                    other.center[axis] - moving.center[axis] // align centers
                ]
                for delta in candidates where abs(delta) <= threshold {
                    if abs(delta) < abs(best ?? .infinity) { best = delta }
                }
            }
            if let best { correction[axis] = best }
        }
        return correction
    }
}

/// Timeline bookkeeping shared by operations.
public enum TimelineTools {
    /// The timeline without anything that targets `objects`.
    public static func removingReferences(to objects: Set<ObjectID>, from timeline: Timeline) -> Timeline {
        var result = timeline
        result.tracks.removeAll { objects.contains($0.target) }
        result.behaviors.removeAll { objects.contains($0.target) }
        result.clipTracks.removeAll { objects.contains($0.target) }
        result.cuts.removeAll { objects.contains($0.camera) }
        return result
    }

    /// Copies of the tracks / behaviours / clip tracks of mapped objects, retargeted to their copies.
    /// `offsets` shifts the position keys of (top-level) copies so they move next to the original.
    public static func copyAnimation(
        from timeline: Timeline, mapping: [ObjectID: ObjectID], offsets: [ObjectID: Vec3] = [:], ids: inout IDFactory
    ) -> EditCommand? {
        var tracks: [TrackEdit] = []
        for track in timeline.tracks {
            guard let target = mapping[track.target] else { continue }
            var keys = track.keyframes
            if track.property == .position, let offset = offsets[track.target] {
                keys = keys.map { key in
                    var moved = key
                    if let position = key.value.vec3Value { moved.value = .vec3(position + offset) }
                    return moved
                }
            }
            tracks.append(TrackEdit(Track(id: ids.next(), target: target, property: track.property, keyframes: keys)))
        }
        var behaviors: [Behavior] = []
        for behavior in timeline.behaviors {
            guard let target = mapping[behavior.target] else { continue }
            var copy = behavior
            copy.id = (ids.next() as TrackID).raw
            copy.target = target
            behaviors.append(copy)
        }
        var clipTracks: [ClipTrack] = []
        for clipTrack in timeline.clipTracks {
            guard let target = mapping[clipTrack.target] else { continue }
            var copy = clipTrack
            copy.id = (ids.next() as TrackID).raw
            copy.target = target
            clipTracks.append(copy)
        }
        if behaviors.isEmpty, clipTracks.isEmpty {
            return tracks.isEmpty ? nil : .setTracks(tracks)
        }
        var updated = timeline
        updated.tracks += tracks.compactMap(\.track)
        updated.behaviors += behaviors
        updated.clipTracks += clipTracks
        return .setTimeline(updated)
    }
}
