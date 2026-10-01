import Foundation

public extension LookPreset {
    /// Ink (default): cel shading that holds up close. Soft band edges, hue-shifted shadows, bounce light, contact
    /// shading, rim, darkened-colour lines. The house default.
    static let ink = LookPreset(id: "ink", name: "Ink")

    /// Comic: Ink with halftone dots in the shadows, misregistration for depth of field, animation on twos, heavier
    /// lines and a printed-paper finish (Into the Spider-Verse lineage).
    static let comic = LookPreset(
        id: "comic", name: "Comic",
        shading: ShadingParams(edgeSoftness: 0.012, shadowValue: 0.38, shadowSaturation: 0.15, contactShading: 0.4, rim: 0.45),
        lines: LineParams(width: 2.6, colorMode: .ink, darken: 0.8, creaseAngle: 42, depthSensitivity: 0.6),
        comic: ComicParams(halftone: 0.75, halftoneScale: 7, misregistration: true),
        finish: LookFinish(paperGrain: 0.25, paperTint: 0.35, saturation: 0.08),
        stepping: .onTwos
    )

    /// Sketch: desaturated Ink with pencil lines that boil, paper grain on; objects flagged Accent keep their colour
    /// (Paperman lineage).
    static let sketch = LookPreset(
        id: "sketch", name: "Sketch",
        shading: ShadingParams(edgeSoftness: 0.05, shadowValue: 0.3, shadowSaturation: 0.05, ambientSteps: 0.3, rim: 0.2),
        lines: LineParams(width: 1.4, colorMode: .ink, inkColor: RGBA(0.16, 0.15, 0.17), creaseAngle: 40, depthSensitivity: 0.55,
                          boil: 0.6, pencil: true),
        finish: LookFinish(paperGrain: 0.55, paperTint: 0.12, vignette: 0.15, saturation: -0.88, accentKeepsColor: true)
    )

    /// Clay: soft, warm, rounded (the v1 look on the new renderer): smooth diffuse light, soft shadows, sky light,
    /// fog and bloom, no lines.
    static let clay = LookPreset(
        id: "clay", name: "Clay",
        shading: ShadingParams(model: .clay, edgeSoftness: 0.5, shadowHueShift: 0.08, shadowValue: 0.2, shadowSaturation: 0.04,
                               ambientSteps: 0, contactShading: 0.8, rim: 0.12, specular: 0.25, specularSize: 0.4,
                               specularSoftness: 0.3, posterizeTextures: false, bloom: 0.5, softShadows: true),
        lines: .off
    )

    /// Low-poly: faceted (per-triangle) normals with Ink bands and optional lines (the original 3D-lowey identity).
    static let lowPoly = LookPreset(
        id: "lowPoly", name: "Low-poly",
        shading: ShadingParams(edgeSoftness: 0.02, rim: 0.25, smoothing: 0),
        lines: LineParams(enabled: false, width: 1.2)
    )

    /// The five built-in Looks, in the order the Look panel shows them.
    static let builtIns: [LookPreset] = [.ink, .comic, .sketch, .clay, .lowPoly]
}

/// Finds Looks by id among the built-ins and a project's own ("My Look") presets.
public enum LookLibrary {
    public static let defaultID = LookPreset.ink.id

    /// The preset for `id`, or Ink when it's unknown (a deleted custom Look never breaks a scene).
    public static func resolve(_ id: String?, custom: [LookPreset] = []) -> LookPreset {
        guard let id else { return .ink }
        return custom.first { $0.id == id } ?? LookPreset.builtIns.first { $0.id == id } ?? .ink
    }

    /// Every Look offered for a project: built-ins, then its own.
    public static func all(custom: [LookPreset]) -> [LookPreset] {
        LookPreset.builtIns + custom.filter { !$0.isBuiltIn }
    }

    /// A unique name for a duplicate ("My Ink", "My Ink 2"…).
    public static func duplicateName(for preset: LookPreset, existing: [LookPreset]) -> String {
        let base = "My \(preset.name)"
        let names = Set(existing.map(\.name))
        guard names.contains(base) else { return base }
        var counter = 2
        while names.contains("\(base) \(counter)") {
            counter += 1
        }
        return "\(base) \(counter)"
    }
}

public extension Document {
    /// The Look the scene renders with.
    var lookPreset: LookPreset {
        LookLibrary.resolve(effectiveLook.presetID, custom: project.customLooks)
    }

    /// The Look an object renders with: its own override, else the scene's.
    func lookPreset(for object: SceneObject) -> LookPreset {
        guard let id = object.lookOverride else { return lookPreset }
        return LookLibrary.resolve(id, custom: project.customLooks)
    }
}

public extension SceneObject {
    /// This object's own Look (nil = the scene's).
    var lookOverride: String? { properties[.lookPreset]?.stringValue }
    /// Line weight multiplier (1 = the Look's width).
    var lineWeight: Double { properties[.lineWeight]?.floatValue ?? 1 }
    /// Kept in colour by the Sketch Look.
    var isAccent: Bool { properties[.accent]?.boolValue ?? false }
    /// Gets a specular shape (glass, metal, eyes).
    var isGlossy: Bool { properties[.glossy]?.boolValue ?? false }
}

public extension PropertyKey {
    /// A Look id this object uses instead of the scene's.
    static let lookPreset: PropertyKey = "lookPreset"
    /// Line weight multiplier, 0…4.
    static let lineWeight: PropertyKey = "lineWeight"
    /// Shape smoothing override, 0 (faceted) … 1 (smooth).
    static let smoothing: PropertyKey = "smoothing"
    /// Rim light strength override, 0…1.
    static let rimStrength: PropertyKey = "rimStrength"
    /// Glossy material: gets a specular shape.
    static let glossy: PropertyKey = "glossy"
    /// Keeps its colour in the Sketch Look.
    static let accent: PropertyKey = "accent"
    /// Primitive bevel radius in metres (0 = sharp).
    static let bevel: PropertyKey = "bevel"
    /// Primitive bevel segments (1…6).
    static let bevelSegments: PropertyKey = "bevelSegments"
}
