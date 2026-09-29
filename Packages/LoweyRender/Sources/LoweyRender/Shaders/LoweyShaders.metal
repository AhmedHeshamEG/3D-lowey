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
    half opacity = half(material.opacity_scale()) * baseSample.a;

    float4 custom = params.uniforms().custom_parameter();
    // w = round(glow × 100) + fog density. Negative w marks an imported model's material.
    bool imported = custom.w < 0.0;
    float packed = abs(custom.w);
    float glow = floor(packed) / 100.0;
    float density = fract(packed);
    half3 tint = half3(material.emissive_color());
    half3 emissive;
    if (imported) {
        // Its own emission map, plus "self glow" (glowing in its own colours: it has no glow colour).
        emissive = tint * textures.emissive_color().sample(loweySampler, uv).rgb + baseColor * half(glow);
    } else {
        // Lowey's surfaces glow in a colour, with no emission map. (Multiplying by the unset map, which RealityKit
        // leaves black, is what made glow do nothing at all.)
        emissive = tint * half(max(glow, 1.0));
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

// ---------------------------------------------------------------------------------------------
// The ground: lit like every surface, and it melts into the sky at its edge (no hard rim against the horizon).
//
// custom_parameter() = (horizon, bottom, fogColor, packed)
//   horizon / bottom = the sky's colours below the horizon (sRGB bytes packed as r × 65536 + g × 256 + b, exposure and
//   fog already applied, exactly as the sky image is drawn), fogColor likewise;
//   packed = round(radius in metres) + fogDensity (fogDensity < 1, 0 = no fog).
// Towards the rim the ground's own colour hands over to the very colour of the sky behind it (worked out from the view
// direction, like the sky dome), so the floor ends in the distance instead of at a line.

/// A packed sRGB colour (r × 65536 + g × 256 + b), 0…1, still sRGB-encoded.
static float3 loweyUnpackSRGB(float value)
{
    float n = floor(value + 0.5);
    float r = floor(n / 65536.0);
    float g = floor((n - r * 65536.0) / 256.0);
    float b = n - r * 65536.0 - g * 256.0;
    return float3(r, g, b) / 255.0;
}

/// sRGB → linear light (what the sky texture becomes when it's sampled).
static half3 loweyLinear(float3 srgb)
{
    float3 low = srgb / 12.92;
    float3 high = pow((max(srgb, 0.0) + 0.055) / 1.055, 2.4);
    return half3(select(high, low, srgb <= 0.04045));
}

static float loweyHash(float2 p)
{
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

/// Smooth value noise, 0…1.
static float loweyNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = loweyHash(i);
    float b = loweyHash(i + float2(1, 0));
    float c = loweyHash(i + float2(0, 1));
    float d = loweyHash(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Where the camera is, from the world → view matrix (rigid: rotation + translation).
static float3 loweyEye(float4x4 worldToView)
{
    float3x3 rotation = float3x3(worldToView[0].xyz, worldToView[1].xyz, worldToView[2].xyz);
    return -(transpose(rotation) * worldToView[3].xyz);
}

[[visible]]
void loweyGround(realitykit::surface_parameters params)
{
    auto material = params.material_constants();
    float4 custom = params.uniforms().custom_parameter();
    float packed = custom.w;
    float radius = max(floor(packed), 1.0);
    float density = fract(packed);

    float3 world = params.geometry().world_position();
    float4x4 worldToView = params.uniforms().world_to_view();
    float3 viewPosition = (worldToView * float4(world, 1.0)).xyz;
    float distance = length(viewPosition);
    float3 eye = loweyEye(worldToView);
    float3 direction = normalize(world - eye);

    // A faint, large-scale unevenness (±4 %) so a big floor doesn't read as one flat sheet.
    float2 ground = world.xz;
    float grain = loweyNoise(ground * 0.16) * 0.65 + loweyNoise(ground * 0.53 + 17.0) * 0.35;
    half shade = 1.0h + half((grain - 0.5) * 0.08);
    half3 baseColor = half3(material.base_color_tint().rgb) * shade;

    // Fog, as on every other surface.
    half fog = density > 0.0 ? half(1.0 - exp(-distance * density)) : 0.0h;
    half3 fogColor = loweyLinear(loweyUnpackSRGB(custom.z));

    // The sky's colour in this direction (below the horizon: horizon → bottom, as the sky image draws it). The mix is
    // in sRGB like the image, then to linear.
    float elevation = asin(clamp(direction.y, -1.0, 1.0)) / (M_PI_F / 2.0);
    float t = pow(clamp(-elevation, 0.0, 1.0), 0.35);
    half3 skyColor = loweyLinear(mix(loweyUnpackSRGB(custom.x), loweyUnpackSRGB(custom.y), t));

    // The rim: the last half of the radius hands over to the sky.
    float r = length(ground);
    half edge = half(smoothstep(radius * 0.45, radius * 0.97, r));

    half keep = (1.0h - fog) * (1.0h - edge);
    params.surface().set_base_color(baseColor * keep);
    params.surface().set_emissive_color(fogColor * fog * (1.0h - edge) + skyColor * edge);
    params.surface().set_roughness(mix(half(material.roughness_scale()), 1.0h, 1.0h - keep));
    params.surface().set_metallic(0.0h);
    params.surface().set_specular(half(0.5) * keep);
    params.surface().set_opacity(1.0h);
}

// ---------------------------------------------------------------------------------------------
// The building grid: 1 m and 5 m lines with the red X and blue Z axes, drawn per pixel so they stay crisp and one pixel
// soft at any distance, thin out where they'd crowd into moiré, and fade away with distance (no hard end).
//
// custom_parameter() = (radiansPerPixel, 0, 0, 0): the view's angle per pixel (2·tan(fov/2) / height in pixels).

/// Coverage of lines every `spacing` metres, `widthPixels` wide, given the pixel's footprint on the ground.
static float loweyGridLines(float2 p, float2 footprint, float spacing, float widthPixels)
{
    float2 q = p / spacing;
    float2 f = max(footprint / spacing, float2(1e-5));
    float2 d = abs(fract(q - 0.5) - 0.5);
    float2 halfWidth = 0.5 * widthPixels * f;
    float2 a = 1.0 - smoothstep(halfWidth, halfWidth + f, d);
    // Cells smaller than a few pixels would shimmer: those lines fade out.
    a *= 1.0 - smoothstep(0.12, 0.35, f);
    return max(a.x, a.y);
}

static float loweyAxisLine(float coordinate, float footprint, float widthPixels)
{
    float halfWidth = 0.5 * widthPixels * footprint;
    return 1.0 - smoothstep(halfWidth, halfWidth + footprint, abs(coordinate));
}

[[visible]]
void loweyGrid(realitykit::surface_parameters params)
{
    float4 custom = params.uniforms().custom_parameter();
    float pixelAngle = max(custom.x, 1e-6);

    float3 world = params.geometry().world_position();
    float4x4 worldToView = params.uniforms().world_to_view();
    float distance = length((worldToView * float4(world, 1.0)).xyz);
    float3 eye = loweyEye(worldToView);
    float3 direction = normalize(world - eye);

    // One pixel on the ground: an ellipse, stretched along the view direction the flatter you look.
    float across = distance * pixelAngle;
    float along = across / max(abs(direction.y), 0.03);
    float2 h = length(direction.xz) > 1e-4 ? normalize(direction.xz) : float2(1.0, 0.0);
    float2 footprint = float2(length(float2(h.x * along, h.y * across)), length(float2(h.y * along, h.x * across)));

    float2 p = world.xz;
    float minor = loweyGridLines(p, footprint, 1.0, 1.1);
    float major = loweyGridLines(p, footprint, 5.0, 1.7);
    float alpha = max(minor * 0.16, major * 0.32);
    half3 color = half3(1.0h);

    // The axes: X runs along z = 0 (red), Z along x = 0 (blue).
    float xAxis = loweyAxisLine(p.y, footprint.y, 2.4);
    float zAxis = loweyAxisLine(p.x, footprint.x, 2.4);
    half3 red = half3(0.95h, 0.35h, 0.35h);
    half3 blue = half3(0.35h, 0.55h, 1.0h);
    color = mix(color, red, half(xAxis));
    alpha = max(alpha, xAxis * 0.8);
    color = mix(color, blue, half(zAxis));
    alpha = max(alpha, zAxis * 0.8);

    // Fade with distance on the ground, further when you're higher up.
    // (Capped inside the 400 m quad, so its edge never shows.)
    float reach = clamp(abs(eye.y) * 22.0, 35.0, 380.0);
    float flat = length(world.xz - eye.xz);
    alpha *= 1.0 - smoothstep(reach * 0.3, reach, flat);

    params.surface().set_base_color(color);
    params.surface().set_opacity(half(alpha));
}
