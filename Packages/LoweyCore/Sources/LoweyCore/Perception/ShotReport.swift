import Foundation
import HmmPerception

/// One labelled thing in the frame (its set-of-marks number is drawn on the pictures).
public struct ObservedObject: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var mark: Int
    /// Screen box, normalised (0…1, top-left origin), clipped to the frame.
    public var box: PerceptionRect
    /// % of the frame its visible pixels cover.
    public var coverage: Double
    /// % of its own silhouette that isn't hidden behind something else.
    public var visible: Double
    /// Metres from the camera to its middle.
    public var distance: Double
    public var grounded: Bool
    /// Gap under it in centimetres (negative: sunk into what it stands on).
    public var gap: Double
    /// Meant to be in the air (marked airborne, or 3D words hanging like a sign): not a floating mistake.
    public var airborne: Bool
    /// Names of what it intersects.
    public var intersects: [String]
    /// Part of it is outside the frame.
    public var cutByFrame: Bool
    /// Degrees between its front and the direction to the camera (0: facing the camera; 180: its back). Nil when it
    /// has no front (a rock, a box).
    public var facing: Double?
    public var isCharacter: Bool
    /// The Look's accent (keeps its colour, draws the eye).
    public var isAccent: Bool
    /// Part of the set (a floor, a wall, a backdrop: very big, behind things); never the subject, not clutter.
    public var isSet: Bool
    /// Mean L* of its visible pixels, and its ΔL* against what's around it (with pixels only).
    public var lightness: Double?
    public var contrast: Double?
}

/// Where the palette sits.
public struct PaletteRead: Codable, Hashable, Sendable {
    /// Up to five dominant colours, most first.
    public var colors: [String]
    /// Share of the frame each covers (%).
    public var shares: [Double]
    /// Spread of saturation over the frame (standard deviation, 0…1).
    public var saturationSpread: Double
}

/// The light as the frame shows it.
public struct LightRead: Codable, Hashable, Sendable {
    /// Where the key comes from as seen through the camera ("upper left", "behind the subject (rim)").
    public var keyFrom: String
    /// % of the subject in the toon shadow band.
    public var subjectInShadow: Double?
    /// Mean L* of the subject and of everything else.
    public var subjectLightness: Double?
    public var worldLightness: Double?
}

/// The whole frame.
public struct FrameRead: Codable, Hashable, Sendable {
    /// The subject's name (declared, or the obvious one) and whether it was declared.
    public var subject: String?
    public var subjectDeclared: Bool
    /// Subject middle, normalised.
    public var subjectX: Double?
    public var subjectY: Double?
    /// "left third", "centre", "right third" or "off the grid".
    public var thirds: String?
    /// Distance (frame heights) from the subject's middle to the nearest third line or the centre line.
    public var thirdsError: Double?
    /// Space above the subject's top (fraction of the frame height); negative when its top is cut.
    public var headroom: Double?
    /// % of the frame showing nothing but sky or ground.
    public var emptyArea: Double
    /// Subject vs background lightness difference (ΔL*), in the value view.
    public var contrast: Double?
    /// % of the subject's outline that stands out from what's behind it (ΔL* ≥ 12).
    public var silhouetteSeparation: Double?
    /// Things covering more than 1% of the frame (the set excluded).
    public var clutter: Int
    /// Degrees the horizon tilts.
    public var horizonTilt: Double
    /// Edges that touch the frame's border without crossing it ("“Lamp” top").
    public var tangents: [String]
    public var palette: PaletteRead?
    public var light: LightRead
}

/// What `observe` measured: per object, then the frame. Numbers first; `summary` says it in a paragraph.
public struct ShotReport: Codable, Hashable, Sendable {
    public var scene: String
    public var time: Double
    public var camera: String
    public var aspect: Double
    public var objects: [ObservedObject]
    public var frame: FrameRead
    public var checks: [RubricCheck]
    public var summary: String

    /// The marks as drawn on the camera view.
    public var marks: [Mark] {
        MarkLayout.place(objects.map(\.box), aspect: aspect).enumerated().map { index, mark in
            var mark = mark
            mark.number = objects[index].mark
            return mark
        }
    }

    public func object(named name: String) -> ObservedObject? {
        objects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.id == name }
    }

    /// The report as JSON for the AI (sorted keys, so it diffs).
    public func json() throws -> Data {
        try PerceptionReport(summary: summary, data: self).json()
    }
}
