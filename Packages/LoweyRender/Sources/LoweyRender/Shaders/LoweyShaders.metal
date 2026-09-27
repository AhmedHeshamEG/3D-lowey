// LoweyShaders.metal — the one surface shader every lit Lowey surface uses.
//
// Why a custom shader: RealityKit has no fog. Baking fog into the material means the
// live viewport and offscreen renders (thumbnails, snapshots, Phase 2 video export)
// look identical. It also gives HDR glow for emissive objects (lamps, screens, eyes).
//
// custom_parameter() = (fogR, fogG, fogB, packed)
//   packed = round(glow × 100) + fogDensity    (fogDensity < 1, 0 = no fog)

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

constexpr sampler loweySampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear);

[[visible]]
void loweySurface(realitykit::surface_parameters params)
{
    auto material = params.material_constants();
    auto textures = params.textures();

    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;

    half4 baseSample = textures.base_color().sample(loweySampler, uv);
    half3 baseColor = half3(material.base_color_tint().rgb) * baseSample.rgb;
    half roughness = half(material.roughness_scale()) * textures.roughness().sample(loweySampler, uv).r;
    half metallic = half(material.metallic_scale()) * textures.metallic().sample(loweySampler, uv).r;
    half3 emissive = half3(material.emissive_color()) * textures.emissive_color().sample(loweySampler, uv).rgb;
    half opacity = half(material.opacity_scale()) * baseSample.a;

    float4 custom = params.uniforms().custom_parameter();
    float packed = max(custom.w, 0.0);
    float glow = floor(packed) / 100.0;
    float density = fract(packed);
    emissive *= half(max(glow, 1.0));

    // Distance fog (exponential), computed from the view-space distance.
    float3 world = params.geometry().world_position();
    float3 viewPosition = (params.uniforms().world_to_view() * float4(world, 1.0)).xyz;
    float distance = length(viewPosition);
    half fog = density > 0.0 ? half(1.0 - exp(-distance * density)) : 0.0h;
    half3 fogColor = half3(custom.rgb);

    params.surface().set_base_color(baseColor * (1.0h - fog));
    params.surface().set_emissive_color(emissive * (1.0h - fog) + fogColor * fog);
    params.surface().set_roughness(mix(roughness, 1.0h, fog));
    params.surface().set_metallic(metallic * (1.0h - fog));
    params.surface().set_opacity(opacity);
}
