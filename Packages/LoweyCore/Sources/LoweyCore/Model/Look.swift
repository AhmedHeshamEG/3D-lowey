import Foundation

/// The project palette. Objects bind to slots with `ColorValue.palette(i)`.
public struct Palette: Codable, Hashable, Sendable {
    public struct Swatch: Codable, Hashable, Sendable {
        public var name: String
        public var color: RGBA
        /// Removed from the palette. The slot keeps its colour, so everything already painted with it (in any
        /// scene) looks exactly the same; it just isn't offered any more. Undo brings it back.
        public var removed: Bool?

        public init(name: String, color: RGBA, removed: Bool? = nil) {
            self.name = name
            self.color = color
            self.removed = removed
        }
    }

    public var swatches: [Swatch]

    /// The slots offered in pickers (removed swatches stay in `swatches`, hidden).
    public var visibleSlots: [Int] {
        swatches.indices.filter { swatches[$0].removed != true }
    }

    /// Takes a swatch out of the palette without changing any object's colour.
    public mutating func remove(slot: Int) {
        guard swatches.indices.contains(slot) else { return }
        swatches[slot].removed = true
    }

    public init(swatches: [Swatch]) {
        self.swatches = swatches
    }

    public static let empty = Palette(swatches: [])

    /// Out-of-range slots fall back to the blockout grey rather than failing:
    /// deleting a swatch must never break a scene.
    public func color(at slot: Int) -> RGBA {
        swatches.indices.contains(slot) ? swatches[slot].color : .blockout
    }

    /// A warm/cool low-poly starter palette. A starting point, not a house style.
    public static let starter = Palette(swatches: [
        Swatch(name: "Paper", color: RGBA(hex: "#F2E8D5")!),
        Swatch(name: "Wood", color: RGBA(hex: "#8A5A3B")!),
        Swatch(name: "Leaf", color: RGBA(hex: "#5E8C4A")!),
        Swatch(name: "Stone", color: RGBA(hex: "#8C8F94")!),
        Swatch(name: "Sky", color: RGBA(hex: "#6FA8DC")!),
        Swatch(name: "Lamp", color: RGBA(hex: "#FFB347")!),
        Swatch(name: "Night", color: RGBA(hex: "#1E2440")!),
        Swatch(name: "Accent", color: RGBA(hex: "#E4572E")!)
    ])
}

public enum ShadingStyle: String, Codable, Sendable, CaseIterable {
    /// Soft low-poly: low-poly silhouettes with smooth surfaces (Hesham's preferred look).
    case smooth
    /// Faceted: every face visible.
    case flat
}

public enum LightingPreset: String, Codable, Sendable, CaseIterable {
    case day, goldenHour, dusk, night, space, studio

    public var displayName: String {
        switch self {
        case .day: "Day"
        case .goldenHour: "Golden hour"
        case .dusk: "Dusk"
        case .night: "Night"
        case .space: "Space"
        case .studio: "Studio"
        }
    }
}

/// The key light of the world (sun or moon) plus ambient image-based light.
public struct Lighting: Codable, Hashable, Sendable {
    /// Degrees above the horizon (0...90).
    public var sunElevation: Double
    /// Degrees around the vertical axis (0 = light comes from +Z).
    public var sunAzimuth: Double
    public var sunColor: RGBA
    /// Relative sun strength, 0...2 (1 = a clear day).
    public var sunIntensity: Double
    public var sunShadows: Bool
    /// Ambient (sky) light strength, 0...2.
    public var ambientIntensity: Double
    /// Overall exposure in stops, -3...3.
    public var exposure: Double

    public init(
        sunElevation: Double = 50, sunAzimuth: Double = 35, sunColor: RGBA = .white,
        sunIntensity: Double = 1, sunShadows: Bool = true, ambientIntensity: Double = 1, exposure: Double = 0
    ) {
        self.sunElevation = sunElevation
        self.sunAzimuth = sunAzimuth
        self.sunColor = sunColor
        self.sunIntensity = sunIntensity
        self.sunShadows = sunShadows
        self.ambientIntensity = ambientIntensity
        self.exposure = exposure
    }

    /// Direction the light travels (from the sun toward the ground).
    public var sunDirection: Vec3 {
        let elevation = sunElevation * .pi / 180
        let azimuth = sunAzimuth * .pi / 180
        let toSun = Vec3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation))
        return -toSun
    }
}

public struct Sky: Codable, Hashable, Sendable {
    public var top: RGBA
    public var horizon: RGBA
    public var bottom: RGBA
    /// Star density 0...1 (0 = none).
    public var stars: Double

    public init(top: RGBA, horizon: RGBA, bottom: RGBA, stars: Double = 0) {
        self.top = top
        self.horizon = horizon
        self.bottom = bottom
        self.stars = stars
    }
}

public struct Fog: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var color: RGBA
    /// Distance (m) at which fog reaches ~63% opacity.
    public var distance: Double

    public init(enabled: Bool = false, color: RGBA = RGBA(0.8, 0.85, 0.9), distance: Double = 40) {
        self.enabled = enabled
        self.color = color
        self.distance = distance
    }
}

public struct Ground: Codable, Hashable, Sendable {
    public var visible: Bool
    public var color: RGBA
    /// Radius in meters.
    public var size: Double

    public init(visible: Bool = true, color: RGBA = RGBA(0.55, 0.6, 0.5), size: Double = 60) {
        self.visible = visible
        self.color = color
        self.size = size
    }
}

/// Everything about how a world looks: the Look (render style: Ink, Comic, Sketch, Clay, Low-poly or "My Look"),
/// the mood (sun, sky, fog), the palette and the finish. Lives in the project (default for all scenes) and
/// optionally per scene.
public struct Look: Codable, Hashable, Sendable {
    /// The render style (`LookPreset` id). New projects use Ink.
    public var presetID: String
    /// Mesh shading of imported models and legacy content (the Look's smoothing decides the shading of the rest).
    public var shading: ShadingStyle
    public var palette: Palette
    public var lightingPreset: LightingPreset?
    public var lighting: Lighting
    public var sky: Sky
    public var fog: Fog
    public var ground: Ground
    /// Post-processing (bloom, grain, grade, outlines, retro, textures…) — Phase 3.
    public var post: PostSettings

    public init(
        presetID: String = LookLibrary.defaultID,
        shading: ShadingStyle = .smooth,
        palette: Palette = .starter,
        lightingPreset: LightingPreset? = .day,
        lighting: Lighting = Lighting(),
        sky: Sky = MoodPresets.sky(for: .day),
        fog: Fog = Fog(),
        ground: Ground = Ground(),
        post: PostSettings = PostSettings()
    ) {
        self.presetID = presetID
        self.shading = shading
        self.palette = palette
        self.lightingPreset = lightingPreset
        self.lighting = lighting
        self.sky = sky
        self.fog = fog
        self.ground = ground
        self.post = post
    }

    private enum CodingKeys: String, CodingKey {
        case presetID, shading, palette, lightingPreset, lighting, sky, fog, ground, post
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        presetID = try c.decodeIfPresent(String.self, forKey: .presetID) ?? LookLibrary.defaultID
        shading = try c.decode(ShadingStyle.self, forKey: .shading)
        palette = try c.decode(Palette.self, forKey: .palette)
        lightingPreset = try c.decodeIfPresent(LightingPreset.self, forKey: .lightingPreset)
        lighting = try c.decode(Lighting.self, forKey: .lighting)
        sky = try c.decode(Sky.self, forKey: .sky)
        fog = try c.decode(Fog.self, forKey: .fog)
        ground = try c.decode(Ground.self, forKey: .ground)
        post = try c.decodeIfPresent(PostSettings.self, forKey: .post) ?? PostSettings()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(presetID, forKey: .presetID)
        try c.encode(shading, forKey: .shading)
        try c.encode(palette, forKey: .palette)
        try c.encodeIfPresent(lightingPreset, forKey: .lightingPreset)
        try c.encode(lighting, forKey: .lighting)
        try c.encode(sky, forKey: .sky)
        try c.encode(fog, forKey: .fog)
        try c.encode(ground, forKey: .ground)
        if post != PostSettings() { try c.encode(post, forKey: .post) }
    }

    public static let `default` = MoodPresets.look(for: .day)

    /// The same world in another Look (render style).
    public func withPreset(_ id: String) -> Look {
        var look = self
        look.presetID = id
        return look
    }

    /// Applies a lighting preset: sun, sky, fog. Keeps palette, shading and ground color.
    public func applying(_ preset: LightingPreset) -> Look {
        var look = self
        let presetLook = MoodPresets.look(for: preset)
        look.lightingPreset = preset
        look.lighting = presetLook.lighting
        look.sky = presetLook.sky
        look.fog = presetLook.fog
        return look
    }
}

/// The six built-in lighting moods. Tuned for low-poly worlds.
public enum MoodPresets {
    public static func look(for preset: LightingPreset) -> Look {
        switch preset {
        case .day:
            return Look(
                lightingPreset: .day,
                lighting: Lighting(sunElevation: 55, sunAzimuth: 35, sunColor: RGBA(hex: "#FFF6E8")!,
                                   sunIntensity: 1.0, ambientIntensity: 1.0),
                sky: sky(for: .day),
                fog: Fog(enabled: true, color: RGBA(hex: "#CFE3F2")!, distance: 90),
                ground: Ground(color: RGBA(hex: "#8DB36B")!)
            )
        case .goldenHour:
            return Look(
                lightingPreset: .goldenHour,
                lighting: Lighting(sunElevation: 14, sunAzimuth: 250, sunColor: RGBA(hex: "#FFB86B")!,
                                   sunIntensity: 1.15, ambientIntensity: 0.75),
                sky: sky(for: .goldenHour),
                fog: Fog(enabled: true, color: RGBA(hex: "#F6C48E")!, distance: 70),
                ground: Ground(color: RGBA(hex: "#A7A45E")!)
            )
        case .dusk:
            return Look(
                lightingPreset: .dusk,
                lighting: Lighting(sunElevation: 6, sunAzimuth: 280, sunColor: RGBA(hex: "#FF8A7A")!,
                                   sunIntensity: 0.45, ambientIntensity: 0.5),
                sky: sky(for: .dusk),
                fog: Fog(enabled: true, color: RGBA(hex: "#5B4A78")!, distance: 45),
                ground: Ground(color: RGBA(hex: "#4B5A55")!)
            )
        case .night:
            return Look(
                lightingPreset: .night,
                lighting: Lighting(sunElevation: 40, sunAzimuth: 120, sunColor: RGBA(hex: "#9DB4FF")!,
                                   sunIntensity: 0.22, ambientIntensity: 0.28),
                sky: sky(for: .night),
                fog: Fog(enabled: true, color: RGBA(hex: "#141A33")!, distance: 35),
                ground: Ground(color: RGBA(hex: "#2A3342")!)
            )
        case .space:
            return Look(
                lightingPreset: .space,
                lighting: Lighting(sunElevation: 20, sunAzimuth: 60, sunColor: .white,
                                   sunIntensity: 1.3, ambientIntensity: 0.12),
                sky: sky(for: .space),
                fog: Fog(enabled: false, color: .black, distance: 200),
                ground: Ground(visible: false, color: RGBA(hex: "#333333")!)
            )
        case .studio:
            return Look(
                lightingPreset: .studio,
                lighting: Lighting(sunElevation: 60, sunAzimuth: 30, sunColor: .white,
                                   sunIntensity: 0.9, ambientIntensity: 1.2),
                sky: sky(for: .studio),
                fog: Fog(enabled: false, color: RGBA(hex: "#E6E6E6")!, distance: 100),
                ground: Ground(color: RGBA(hex: "#D9D9D9")!)
            )
        }
    }

    public static func sky(for preset: LightingPreset) -> Sky {
        switch preset {
        case .day:
            Sky(top: RGBA(hex: "#4F8FD6")!, horizon: RGBA(hex: "#CFE3F2")!, bottom: RGBA(hex: "#9DB88A")!)
        case .goldenHour:
            Sky(top: RGBA(hex: "#6C8CC7")!, horizon: RGBA(hex: "#FFC98A")!, bottom: RGBA(hex: "#8C7A55")!)
        case .dusk:
            Sky(top: RGBA(hex: "#1F2150")!, horizon: RGBA(hex: "#E07A6A")!, bottom: RGBA(hex: "#3A3450")!, stars: 0.25)
        case .night:
            Sky(top: RGBA(hex: "#060914")!, horizon: RGBA(hex: "#1B2547")!, bottom: RGBA(hex: "#0B0F1E")!, stars: 0.8)
        case .space:
            Sky(top: RGBA(hex: "#000000")!, horizon: RGBA(hex: "#0A0A18")!, bottom: RGBA(hex: "#000000")!, stars: 1)
        case .studio:
            Sky(top: RGBA(hex: "#D5D8DD")!, horizon: RGBA(hex: "#EEEEEE")!, bottom: RGBA(hex: "#D0D0D0")!)
        }
    }
}
