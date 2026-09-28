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
    // Negative w = "self glow": an imported model glowing in its own colours (it has no glow colour of its own).
    bool selfGlow = custom.w < 0.0;
    float packed = abs(custom.w);
    float glow = floor(packed) / 100.0;
    float density = fract(packed);
    emissive *= half(max(glow, 1.0));
    if (selfGlow) {
        emissive += baseColor * half(glow);
    }

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

// ---------------------------------------------------------------------------------------------
// Depth for post-processing (lens blur, ink outlines) — Phase 3.
//
// Everything post-processing needs from depth is linear in 1/distance (the circle of confusion is
// |1/focus − 1/d| × lens), so depth is stored as v = min(0.5 / d, 1): 0 = infinitely far, 1 = 0.5 m.
// The export renders a second "depth world" with this unlit shader; the live stage converts RealityKit's
// own depth buffer with `loweyInverseDepth`. Both produce the same v, so preview and export blur alike.

[[visible]]
void loweyDepth(realitykit::surface_parameters params)
{
    float3 world = params.geometry().world_position();
    float3 viewPosition = (params.uniforms().world_to_view() * float4(world, 1.0)).xyz;
    float distance = max(-viewPosition.z, 0.0001);
    half v = half(min(0.5 / distance, 1.0));
    params.surface().set_base_color(half3(v, v, v));
    params.surface().set_emissive_color(half3(v, v, v));
    params.surface().set_opacity(1.0h);
}

struct LoweyDepthParams {
    float near;
    float far;
};

/// Reverse-Z depth buffer (1 at the near plane, 0 at the far plane) → v = 0.5 / distance.
kernel void loweyInverseDepth(depth2d<float, access::read> depth [[texture(0)]],
                              texture2d<half, access::write> output [[texture(1)]],
                              constant LoweyDepthParams& p [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    uint2 source = uint2(float2(gid) * float2(depth.get_width(), depth.get_height()) / float2(output.get_width(), output.get_height()));
    float z = depth.read(source);
    float inverseDistance = (z * (p.far - p.near) + p.near) / (p.near * p.far);
    half v = half(clamp(0.5 * inverseDistance, 0.0, 1.0));
    output.write(half4(v, v, v, 1.0h), gid);
}
