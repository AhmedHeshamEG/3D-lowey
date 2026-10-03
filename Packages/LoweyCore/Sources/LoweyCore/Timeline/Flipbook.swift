import Foundation

/// What a flipbook track is pinned to.
public enum FlipbookAnchor: Hashable, Sendable {
    /// Screen FX: drawn in the frame. Units are frame heights from the centre (x right, y up), so a drawing keeps its
    /// shape in every delivery format (a 9:16 frame crops the sides of the same drawing).
    case camera
    /// Follows an object: drawn on the plane facing the camera through the object's centre, in metres (x right, y up
    /// as seen from the camera), so it shrinks as the object moves away and rides along with it.
    case object(ObjectID)

    public var object: ObjectID? {
        if case let .object(id) = self { return id }
        return nil
    }
}

extension FlipbookAnchor: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = raw == "camera" ? .camera : .object(ObjectID(raw: raw))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .camera: try container.encode("camera")
        case let .object(id): try container.encode(id.raw)
        }
    }
}

/// How a flipbook track mixes with the shot under it.
public enum FlipbookBlend: String, Codable, Sendable, CaseIterable {
    case normal, multiply, screen, add

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .multiply: "Multiply"
        case .screen: "Screen"
        case .add: "Add"
        }
    }
}

/// One 2D stroke of a flipbook drawing (see `FlipbookAnchor` for the units).
public struct FlipStroke: Codable, Hashable, Sendable {
    public var points: [Vec2]
    /// Half-widths per point (pressure), same units as the points.
    public var widths: [Double]
    public var color: ColorValue
    /// A closed shape filled with the colour (impact bursts, drops) instead of a line.
    public var filled: Bool

    public init(points: [Vec2], widths: [Double], color: ColorValue, filled: Bool = false) {
        self.points = points
        self.widths = widths.count == points.count ? widths : Array(repeating: widths.first ?? 0.004, count: points.count)
        self.color = color
        self.filled = filled
    }

    private enum CodingKeys: String, CodingKey {
        case points, widths, color, filled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let points = try c.decode([[Double]].self, forKey: .points).map { Vec2($0.first ?? 0, $0.count > 1 ? $0[1] : 0) }
        try self.init(points: points, widths: c.decode([Double].self, forKey: .widths), color: c.decode(ColorValue.self, forKey: .color),
                      filled: c.decodeIfPresent(Bool.self, forKey: .filled) ?? false)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(points.map { [$0.x, $0.y] }, forKey: .points)
        try c.encode(widths, forKey: .widths)
        try c.encode(color, forKey: .color)
        if filled { try c.encode(filled, forKey: .filled) }
    }
}

/// One drawing of a flipbook, shown for `hold` frames (on ones = 1, on twos = 2 …).
public struct FlipbookFrame: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var hold: Int
    public var strokes: [FlipStroke]

    public init(id: String, hold: Int = 2, strokes: [FlipStroke] = []) {
        self.id = id
        self.hold = max(hold, 1)
        self.strokes = strokes
    }
}

/// A frame-by-frame drawing track over the 3D shot (Procreate Dreams' flipbook): drawings with hold lengths, played
/// from `start`, optionally looping until `end`; anchored to the camera or to an object; blended over the shot.
public struct FlipbookTrack: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var anchor: FlipbookAnchor
    public var start: Double
    public var frames: [FlipbookFrame]
    public var blend: FlipbookBlend
    public var opacity: Double
    public var loops: Bool
    /// Where a looping track stops (nil = the end of the scene).
    public var end: Double?
    public var visible: Bool
    /// Where on the anchor the drawing is centred (an object's centre is its bounds' centre).
    public var offset: Vec2

    public init(id: String, name: String, anchor: FlipbookAnchor = .camera, start: Double = 0, frames: [FlipbookFrame] = [],
                blend: FlipbookBlend = .normal, opacity: Double = 1, loops: Bool = false, end: Double? = nil, visible: Bool = true,
                offset: Vec2 = Vec2(0, 0)) {
        self.id = id
        self.name = name
        self.anchor = anchor
        self.start = start
        self.frames = frames
        self.blend = blend
        self.opacity = opacity
        self.loops = loops
        self.end = end
        self.visible = visible
        self.offset = offset
    }

    /// Frames from the first drawing to the end of the last one's hold.
    public var lengthInFrames: Int { frames.reduce(0) { $0 + $1.hold } }

    public func duration(fps: Int) -> Double { Double(lengthInFrames) / Double(max(fps, 1)) }

    /// Where the track stops showing (a loop runs to `end`, else the scene's end).
    public func end(fps: Int, sceneDuration: Double) -> Double {
        loops ? (end ?? sceneDuration) : start + duration(fps: fps)
    }

    /// The drawing showing at `time` (nil before the start, after the end, or with no drawings).
    public func frameIndex(at time: Double, fps: Int, sceneDuration: Double = .infinity) -> Int? {
        guard !frames.isEmpty, time >= start - 1e-9, time < end(fps: fps, sceneDuration: sceneDuration) - 1e-9 else { return nil }
        var frame = Int(((time - start) * Double(fps) + 1e-6).rounded(.down))
        let length = lengthInFrames
        if loops, length > 0 { frame %= length }
        for (index, drawing) in frames.enumerated() {
            if frame < drawing.hold { return index }
            frame -= drawing.hold
        }
        return nil
    }

    /// When drawing `index` starts showing (first pass).
    public func startTime(ofFrame index: Int, fps: Int) -> Double {
        start + Double(frames.prefix(max(index, 0)).reduce(0) { $0 + $1.hold }) / Double(max(fps, 1))
    }
}

/// Inserts, replaces or removes one flipbook track (`track == nil` removes).
public struct FlipbookEdit: Codable, Hashable, Sendable {
    public var id: String
    public var track: FlipbookTrack?
    public var index: Int?

    public init(id: String, track: FlipbookTrack?, index: Int? = nil) {
        self.id = id
        self.track = track
        self.index = index
    }

    public init(_ track: FlipbookTrack) {
        self.init(id: track.id, track: track)
    }
}

/// Editing flipbook drawings (each returns a new track; the editor applies it as one command).
public enum FlipbookEditing {
    /// Adds a stroke to the drawing showing at `time`. Past the last drawing a new drawing is appended (so drawing on
    /// at the playhead keeps the flipbook going); before the start the track starts earlier.
    public static func adding(_ stroke: FlipStroke, at time: Double, fps: Int, hold: Int, to track: FlipbookTrack,
                              newID: String) -> (track: FlipbookTrack, frame: Int) {
        var result = track
        if result.frames.isEmpty {
            result.start = time
            result.frames = [FlipbookFrame(id: newID, hold: hold, strokes: [stroke])]
            return (result, 0)
        }
        if let index = track.frameIndex(at: time, fps: fps) {
            result.frames[index].strokes.append(stroke)
            return (result, index)
        }
        if time < track.start {
            let gap = max(Int(((track.start - time) * Double(fps)).rounded()), 1)
            result.start = time
            result.frames.insert(FlipbookFrame(id: newID, hold: gap, strokes: [stroke]), at: 0)
            return (result, 0)
        }
        // After the end: the last drawing holds until the playhead, then the new one starts.
        let frameAtTime = Int(((time - track.start) * Double(fps) + 1e-6).rounded(.down))
        let gap = frameAtTime - track.lengthInFrames
        if gap > 0, let last = result.frames.indices.last { result.frames[last].hold += gap }
        result.frames.append(FlipbookFrame(id: newID, hold: hold, strokes: [stroke]))
        return (result, result.frames.count - 1)
    }

    /// A new empty drawing after `index` (the next drawing to draw).
    public static func insertingFrame(after index: Int, hold: Int, in track: FlipbookTrack, newID: String) -> FlipbookTrack {
        var result = track
        let at = min(max(index + 1, 0), track.frames.count)
        result.frames.insert(FlipbookFrame(id: newID, hold: hold), at: at)
        return result
    }

    public static func duplicatingFrame(_ index: Int, in track: FlipbookTrack, newID: String) -> FlipbookTrack {
        guard track.frames.indices.contains(index) else { return track }
        var result = track
        var copy = track.frames[index]
        copy.id = newID
        result.frames.insert(copy, at: index + 1)
        return result
    }

    public static func removingFrame(_ index: Int, from track: FlipbookTrack) -> FlipbookTrack {
        guard track.frames.indices.contains(index) else { return track }
        var result = track
        result.frames.remove(at: index)
        return result
    }

    public static func settingHold(_ hold: Int, ofFrame index: Int, in track: FlipbookTrack) -> FlipbookTrack {
        guard track.frames.indices.contains(index) else { return track }
        var result = track
        result.frames[index].hold = min(max(hold, 1), 48)
        return result
    }

    /// Removes the stroke points `isErased` picks from drawing `frame`, splitting strokes (filled shapes go whole).
    public static func erasing(frame index: Int, in track: FlipbookTrack, where isErased: (Vec2) -> Bool) -> FlipbookTrack {
        guard track.frames.indices.contains(index) else { return track }
        var result = track
        var kept: [FlipStroke] = []
        for stroke in track.frames[index].strokes {
            if stroke.filled {
                if !stroke.points.contains(where: isErased) { kept.append(stroke) }
                continue
            }
            var points: [Vec2] = []
            var widths: [Double] = []
            for (point, width) in zip(stroke.points, stroke.widths) {
                if isErased(point) {
                    if points.count >= 2 { kept.append(FlipStroke(points: points, widths: widths, color: stroke.color)) }
                    points = []
                    widths = []
                } else {
                    points.append(point)
                    widths.append(width)
                }
            }
            if points.count >= 2 || (points.count == 1 && stroke.points.count == 1) {
                kept.append(FlipStroke(points: points, widths: widths, color: stroke.color))
            }
        }
        result.frames[index].strokes = kept
        return result
    }
}

public extension Timeline {
    func flipbook(_ id: String) -> FlipbookTrack? { flipbooks.first { $0.id == id } }
}
