import Foundation
import LoweyCore
import simd

extension RGBA {
    /// sRGB → linear light (the renderer works in linear).
    var linear: SIMD3<Float> {
        func channel(_ c: Double) -> Float {
            Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
        }
        return SIMD3<Float>(channel(r), channel(g), channel(b))
    }

    var linearWithAlpha: SIMD4<Float> { SIMD4<Float>(linear, Float(a)) }
}

/// Turns the document's Look (mood, sky, fog, ground) and its render styles (`LookPreset`) into shader uniforms.
enum LookResolver {
    /// The world part of the frame uniforms: sun, sky, ambient, ground, fog.
    static func world(_ look: Look, into frame: inout FrameUniforms, transparentBackdrop: Bool) {
        let exposure = Float(pow(2, look.lighting.exposure))
        let lighting = look.lighting
        frame.sunDirection = SIMD4<Float>((-lighting.sunDirection).float3, Float(lighting.sunIntensity))
        let sunOn = lighting.sunIntensity > 0.02
        frame.sunColor = SIMD4<Float>(lighting.sunColor.linear * Float(lighting.sunIntensity) * exposure, lighting.sunShadows && sunOn ? 1 : 0)
        var sky = look.sky
        var horizon = sky.horizon
        var bottom = sky.bottom
        if look.fog.enabled {
            horizon = horizon.lerp(to: look.fog.color, 0.6)
            bottom = bottom.lerp(to: look.fog.color, 0.8)
        }
        sky.horizon = horizon
        sky.bottom = bottom
        frame.skyTop = SIMD4<Float>(sky.top.linear * exposure, Float(sky.stars))
        frame.skyHorizon = SIMD4<Float>(horizon.linear * exposure, exposure)
        frame.skyBottom = SIMD4<Float>(bottom.linear * exposure, transparentBackdrop ? 1 : 0)
        // Ambient: the sky's own colour, lifted toward a neutral moonlit grey so dark moods stay readable.
        let skyTint = sky.top.lerp(to: horizon, 0.5).lerp(to: RGBA(0.5, 0.53, 0.62), 0.3)
        frame.ambient = SIMD4<Float>(skyTint.linear * exposure, Float(lighting.ambientIntensity))
        let bounce = look.ground.visible ? look.ground.color.lerp(to: skyTint, 0.35) : skyTint.scaled(0.5)
        frame.groundBounce = SIMD4<Float>(bounce.linear * exposure * 0.8, Float(max(look.ground.size, 1)))
        let density = look.fog.enabled && look.fog.distance > 0 ? Float(min(1 / look.fog.distance, 0.999)) : 0
        frame.fog = SIMD4<Float>(look.fog.color.linear * exposure, density)
    }

    /// One Look's shading, line, print and finish parameters. `extraOutline` is the project's Finish ▸ Outlines
    /// (lines on top of any Look, v1's depth outlines).
    static func uniforms(_ preset: LookPreset) -> LookUniforms {
        var look = LookUniforms()
        let shading = preset.shading
        look.bands = SIMD4<Float>(Float(shading.bands), Float(shading.threshold), Float(shading.midThreshold), Float(shading.edgeSoftness))
        look.shadow = SIMD4<Float>(Float(shading.shadowHueShift), Float(shading.shadowValue), Float(shading.shadowSaturation),
                                   Float(shading.ambientSteps))
        look.rim = SIMD4<Float>(Float(shading.rim), Float(shading.rimThreshold), Float(shading.rimSoftness), Float(shading.contactShading))
        look.specular = SIMD4<Float>(Float(shading.specular), Float(shading.specularSize), Float(shading.specularSoftness),
                                     Float(shading.smoothing))
        look.model = SIMD4<Float>(shading.model == .clay ? 1 : 0, shading.posterizeTextures ? 1 : 0, shading.softShadows ? 1 : 0,
                                  Float(shading.bloom))
        let lines = preset.lines
        look.lines = SIMD4<Float>(lines.enabled ? 1 : 0, Float(lines.width), Float(lines.darken), lines.colorMode == .ink ? 1 : 0)
        look.lineInk = SIMD4<Float>(lines.inkColor.linear, Float(lines.boil))
        look.lineShape = SIMD4<Float>(Float(cos(lines.creaseAngle * .pi / 180)), Float(lines.depthSensitivity), lines.pencil ? 1 : 0, 0)
        let comic = preset.comic
        look.comic = SIMD4<Float>(Float(comic.halftone), Float(comic.halftoneScale), comic.objectSpaceDots ? 1 : 0, comic.misregistration ? 1 : 0)
        let finish = preset.finish
        look.finish = SIMD4<Float>(Float(finish.paperGrain), Float(finish.paperTint), Float(finish.vignette), Float(finish.saturation))
        look.grade = SIMD4<Float>(Float(finish.lift), Float(finish.gamma), Float(finish.gain), finish.accentKeepsColor ? 1 : 0)
        return look
    }

    /// The project's Finish (v1's post settings) as post uniforms.
    static func post(_ post: PostSettings, sceneLook: LookPreset, frame: Int, size: SIMD2<Float>) -> PostUniforms {
        var uniforms = PostUniforms()
        uniforms.size = SIMD4<Float>(size.x, size.y, 1 / max(size.x, 1), 1 / max(size.y, 1))
        uniforms.grade = SIMD4<Float>(Float(pow(2, post.exposure)), Float(post.contrast), Float(post.saturation), Float(post.temperature))
        uniforms.bloom = SIMD4<Float>(Float(post.bloom) * 0.8, 1.0, Float(sceneLook.shading.bloom) * 0.5, 0)
        uniforms.film = SIMD4<Float>(Float(post.vignette), Float(post.grain), Float(post.chromaticAberration), Float(post.retro))
        let kind: Float = switch post.texture {
        case .none: 0
        case .paper: 1
        case .collage: 2
        case .film: 3
        }
        uniforms.texture = SIMD4<Float>(kind, Float(post.textureStrength), Float(frame), 0)
        uniforms.pixels = SIMD4<Float>(size.y / 1080, Float(frame), Float(frame / 2), 0)
        return uniforms
    }
}
