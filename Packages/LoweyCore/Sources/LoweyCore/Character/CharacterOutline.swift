import Foundation

/// Characters get a stable thick outline (an inverted hull: the mesh pushed out along its normals, drawn inside out
/// in the line colour) on top of the Look's lines, so their silhouette never flickers or breaks up. Face decals (eyes,
/// pupils, brows, mouth, cheeks) are drawn flat, like paint on the head, and get no hull of their own.
public enum CharacterOutline {
    /// Hull width in metres for a character about 1.7 m tall in the Ink Look.
    public static let baseWidth = 0.009

    /// Parts drawn flat with no outline: face decals, and a Blob's hover glow.
    public static func isDecal(role: String) -> Bool {
        ["eye", "pupil", "brow", "mouth", "cheek", "blush", "hover"].contains { role.hasPrefix($0) }
    }

    /// The hull width for a character drawn in `look` at `scale` (nil: the Look draws no lines).
    public static func width(look: LookPreset, scale: Double, lineWeight: Double = 1) -> Double? {
        guard look.lines.enabled, lineWeight > 0 else { return nil }
        return baseWidth * look.lines.width / LineParams().width * abs(scale) * lineWeight
    }

    /// Whether `id` is a character root: a Blob, a built character or a character playing clips.
    public static func isCharacter(_ id: ObjectID, in scene: Scene) -> Bool {
        scene.objects[id]?[.rigStandard] != nil || scene.timeline.clipTracks.contains { $0.target == id }
    }
}

/// Ready-made Shadow Brush paintings: designed shadow shapes for a head (or anything), in the object's own bounds.
public enum ShadowPreset: String, CaseIterable, Sendable, Identifiable {
    /// Light from one side: the far side falls into shadow, the near side lifts.
    case sideLight
    /// Light from above: a lit crown, shadow under the chin.
    case topLight
    /// Only a crisp shadow under the chin (the jaw line).
    case underChin
    /// Half lit, half in shadow (drama).
    case split
    /// The edges lift (a backlit pop around the silhouette).
    case rimPop

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sideLight: "Side light"
        case .topLight: "Top light"
        case .underChin: "Under the chin"
        case .split: "Split"
        case .rimPop: "Rim pop"
        }
    }

    /// (position in the bounds −1…1, radius as a fraction of the size, amount): negative pushes shadow in.
    var marks: [(Vec3, Double, Double)] {
        switch self {
        case .sideLight: [(Vec3(-0.85, 0, 0.55), 0.7, -0.65), (Vec3(0.75, 0.25, 0.6), 0.55, 0.45)]
        case .topLight: [(Vec3(0, 0.85, 0.35), 0.7, 0.5), (Vec3(0, -0.75, 0.55), 0.6, -0.6)]
        case .underChin: [(Vec3(0, -0.88, 0.6), 0.42, -0.85)]
        case .split: [(Vec3(-0.55, 0, 0.8), 0.75, -0.9), (Vec3(0.55, 0, 0.8), 0.7, 0.55)]
        case .rimPop: [(Vec3(-0.92, 0.2, 0.2), 0.38, 0.6), (Vec3(0.92, 0.2, 0.2), 0.38, 0.6), (Vec3(0, 0.95, 0.1), 0.35, 0.5)]
        }
    }

    /// The dabs in an object's local space, for its local `bounds`.
    public func dabs(in bounds: Bounds) -> [ShadowDab] {
        let center = bounds.center
        let half = bounds.size * 0.5
        let size = max(bounds.size.maxComponent, 1e-3)
        return marks.map { mark, radius, amount in
            ShadowDab(position: center + Vec3(half.x * mark.x, half.y * mark.y, half.z * mark.z), radius: size * radius, amount: amount)
        }
    }
}
