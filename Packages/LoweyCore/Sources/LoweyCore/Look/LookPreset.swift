import Foundation

/// How surfaces take light.
public enum LookModel: String, Codable, Sendable, CaseIterable {
    /// Cel shading: flat colour bands with soft edges, hue-shifted shadows, rim and specular shapes.
    case toon
    /// Soft, rounded lighting (the v1 look): smooth diffuse, soft shadows, sky light, fog and bloom.
    case clay
}

/// Shading parameters of a Look (the per-fragment recipe; see docs/SPEC.md §2.1).
public struct ShadingParams: Codable, Hashable, Sendable {
    public var model: LookModel
    /// 2 (light / shadow) or 3 (light / mid / shadow).
    public var bands: Int
    /// Where the light/shadow boundary sits on the 0…1 light term.
    public var threshold: Double
    /// Where the mid/light boundary sits (3 bands only).
    public var midThreshold: Double
    /// Half-width of each band edge: 0.002 crisp … 0.08 soft.
    public var edgeSoftness: Double
    /// Shadow colour = base shifted toward the ambient hue by this much (0…1)…
    public var shadowHueShift: Double
    /// …with its value lowered by this much (0.30–0.40)…
    public var shadowValue: Double
    /// …and its saturation raised by this much (0.08–0.15).
    public var shadowSaturation: Double
    /// Hemisphere ambient quantisation (0 = smooth, 1 = two flat levels).
    public var ambientSteps: Double
    /// Contact shading strength inside the shadow band (half-resolution SSAO).
    public var contactShading: Double
    /// Rim light strength, threshold and softness (thresholded fresnel).
    public var rim: Double
    public var rimThreshold: Double
    public var rimSoftness: Double
    /// Specular shape (glossy materials only): strength, size (0…1) and softness.
    public var specular: Double
    public var specularSize: Double
    public var specularSoftness: Double
    /// Shape smoothing: 1 = smooth forms, 0 = faceted (per-triangle normals). Objects can override it.
    public var smoothing: Double
    /// Posterise imported textures into the band structure.
    public var posterizeTextures: Bool
    /// HDR emissive halo strength.
    public var bloom: Double
    /// Soft (filtered) sun shadows, for Clay.
    public var softShadows: Bool

    public init(model: LookModel = .toon, bands: Int = 2, threshold: Double = 0.5, midThreshold: Double = 0.78,
                edgeSoftness: Double = 0.03, shadowHueShift: Double = 0.18, shadowValue: Double = 0.35,
                shadowSaturation: Double = 0.12, ambientSteps: Double = 0.6, contactShading: Double = 0.6,
                rim: Double = 0.35, rimThreshold: Double = 0.62, rimSoftness: Double = 0.04, specular: Double = 0.8,
                specularSize: Double = 0.25, specularSoftness: Double = 0.02, smoothing: Double = 1,
                posterizeTextures: Bool = true, bloom: Double = 0.35, softShadows: Bool = false) {
        self.model = model
        self.bands = bands
        self.threshold = threshold
        self.midThreshold = midThreshold
        self.edgeSoftness = edgeSoftness
        self.shadowHueShift = shadowHueShift
        self.shadowValue = shadowValue
        self.shadowSaturation = shadowSaturation
        self.ambientSteps = ambientSteps
        self.contactShading = contactShading
        self.rim = rim
        self.rimThreshold = rimThreshold
        self.rimSoftness = rimSoftness
        self.specular = specular
        self.specularSize = specularSize
        self.specularSoftness = specularSoftness
        self.smoothing = smoothing
        self.posterizeTextures = posterizeTextures
        self.bloom = bloom
        self.softShadows = softShadows
    }
}

/// Screen-space lines from the ID, normal and depth buffers.
public struct LineParams: Codable, Hashable, Sendable {
    public enum ColorMode: String, Codable, Sendable, CaseIterable {
        /// The object's own colour, darkened (never pure black).
        case darkened
        /// One ink colour for every line.
        case ink
    }

    public var enabled: Bool
    /// Width in points at 1080p (0.5…6), scaled by distance and per-object line weight.
    public var width: Double
    public var colorMode: ColorMode
    public var inkColor: RGBA
    /// How much darker than the object a darkened line is (0…1).
    public var darken: Double
    /// Surface creases above this angle (degrees) get a line.
    public var creaseAngle: Double
    /// Depth discontinuity sensitivity (0 = none, 1 = strong).
    public var depthSensitivity: Double
    /// Hand-drawn jitter stepped on twos (0 = still).
    public var boil: Double
    /// Pencil-textured strokes (grainy, uneven).
    public var pencil: Bool

    public init(enabled: Bool = true, width: Double = 1.6, colorMode: ColorMode = .darkened, inkColor: RGBA = RGBA(0.07, 0.06, 0.09),
                darken: Double = 0.72, creaseAngle: Double = 50, depthSensitivity: Double = 0.5, boil: Double = 0, pencil: Bool = false) {
        self.enabled = enabled
        self.width = width
        self.colorMode = colorMode
        self.inkColor = inkColor
        self.darken = darken
        self.creaseAngle = creaseAngle
        self.depthSensitivity = depthSensitivity
        self.boil = boil
        self.pencil = pencil
    }

    public static let off = LineParams(enabled: false)
}

/// Print-comic language: halftone dots and colour misregistration.
public struct ComicParams: Codable, Hashable, Sendable {
    /// Halftone dots in the shadow band (0 = off).
    public var halftone: Double
    /// Dot spacing in points at 1080p.
    public var halftoneScale: Double
    /// Dots stick to surfaces instead of the screen (no "shower door" on moving things).
    public var objectSpaceDots: Bool
    /// Depth of field becomes RGB misregistration instead of blur.
    public var misregistration: Bool

    public init(halftone: Double = 0, halftoneScale: Double = 7, objectSpaceDots: Bool = false, misregistration: Bool = false) {
        self.halftone = halftone
        self.halftoneScale = halftoneScale
        self.objectSpaceDots = objectSpaceDots
        self.misregistration = misregistration
    }

    public static let off = ComicParams()
}

/// The finish of a Look: paper, vignette, grade, and Sketch's desaturation with an accent.
public struct LookFinish: Codable, Hashable, Sendable {
    /// Very subtle paper grain (0…1).
    public var paperGrain: Double
    /// Paper yellowing / print texture (Comic).
    public var paperTint: Double
    public var vignette: Double
    /// Saturation change (−1 = greyscale).
    public var saturation: Double
    /// Objects flagged Accent keep their full colour when the Look desaturates.
    public var accentKeepsColor: Bool
    /// Lift / gamma / gain (0 = neutral each).
    public var lift: Double
    public var gamma: Double
    public var gain: Double

    public init(paperGrain: Double = 0, paperTint: Double = 0, vignette: Double = 0, saturation: Double = 0,
                accentKeepsColor: Bool = false, lift: Double = 0, gamma: Double = 0, gain: Double = 0) {
        self.paperGrain = paperGrain
        self.paperTint = paperTint
        self.vignette = vignette
        self.saturation = saturation
        self.accentKeepsColor = accentKeepsColor
        self.lift = lift
        self.gamma = gamma
        self.gain = gain
    }

    public static let neutral = LookFinish()
}

/// A Look: shading model + lines + print language + finish + default animation frame rate. Five are built in;
/// any can be duplicated as "My Look" and tweaked; any object can override the scene's Look.
public struct LookPreset: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// The built-in Look this one was duplicated from (nil for a built-in).
    public var basedOn: String?
    public var shading: ShadingParams
    public var lines: LineParams
    public var comic: ComicParams
    public var finish: LookFinish
    /// Default stepping for animated objects (cameras stay on ones).
    public var stepping: Stepping

    public init(id: String, name: String, basedOn: String? = nil, shading: ShadingParams = ShadingParams(),
                lines: LineParams = LineParams(), comic: ComicParams = .off, finish: LookFinish = .neutral,
                stepping: Stepping = .onOnes) {
        self.id = id
        self.name = name
        self.basedOn = basedOn
        self.shading = shading
        self.lines = lines
        self.comic = comic
        self.finish = finish
        self.stepping = stepping
    }

    public var isBuiltIn: Bool { LookPreset.builtIns.contains { $0.id == id } }

    /// A copy the user can edit ("My Look").
    public func duplicated(id newID: String, name newName: String) -> LookPreset {
        var copy = self
        copy.id = newID
        copy.name = newName
        copy.basedOn = basedOn ?? id
        return copy
    }
}
