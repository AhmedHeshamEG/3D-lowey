// LoweyCommon.h — types and helpers shared by every LoweyRender 2 shader.
//
// The uniform structs are mirrored in Swift (Render/GPUTypes.swift) with SIMD4 / simd_float4x4 members only, so the
// layouts match without padding rules: keep every member a float4, uint4 or float4x4.

#pragma once
#include <metal_stdlib>
using namespace metal;

// Vertex buffer indices.
#define LW_VERTICES 0
#define LW_SKIN 1
#define LW_OBJECTS 2
#define LW_FRAME 3
#define LW_JOINTS 4
#define LW_LOOKS 5
#define LW_LIGHTS 6
#define LW_CASCADE 7

// Object flags (ObjectUniforms.ids.z).
#define LW_FLAG_ACCENT 1u
#define LW_FLAG_TEXTURED 2u
#define LW_FLAG_SELECTED 4u
#define LW_FLAG_SKINNED 8u
#define LW_FLAG_UNLIT 16u
#define LW_FLAG_GLOSSY 32u
#define LW_FLAG_INK 64u

// ID buffer packing: 20 bits object, 4 bits look, 8 bits flags.
#define LW_ID_OBJECT_MASK 0xFFFFFu
#define LW_ID_LOOK_SHIFT 20u
#define LW_ID_FLAGS_SHIFT 24u

struct FrameUniforms {
    float4x4 view;
    float4x4 projection;
    float4x4 viewProjection;
    float4x4 inverseViewProjection;
    float4x4 shadowMatrices[2];
    float4 cameraPosition;   // xyz, w = time (s)
    float4 viewport;         // width, height, 1/width, 1/height (of the shading target)
    float4 sunDirection;     // xyz toward the sun, w = sun intensity
    float4 sunColor;         // linear rgb × intensity, w = 1 when the sun casts shadows
    float4 skyTop;           // linear rgb, w = star density
    float4 skyHorizon;       // linear rgb, w = exposure multiplier
    float4 skyBottom;        // linear rgb, w = 1 for a transparent backdrop
    float4 ambient;          // linear rgb sky tint, w = ambient intensity
    float4 groundBounce;     // linear rgb, w = ground radius (m)
    float4 fog;              // linear rgb, w = density (1 / distance, 0 = off)
    float4 cascades;         // x = far of cascade 0, y = far of cascade 1, z = 1 / shadow map size, w = frame index
    float4 misc;             // x = light count, y = near plane, z = far plane, w = orthographic (1) or not
};

struct LookUniforms {
    float4 bands;      // x = band count (2 / 3), y = threshold, z = mid threshold, w = edge softness
    float4 shadow;     // x = hue shift toward ambient, y = value drop, z = saturation boost, w = ambient steps
    float4 rim;        // x = strength, y = threshold, z = softness, w = contact shading
    float4 specular;   // x = strength, y = size, z = softness, w = default smoothing
    float4 model;      // x = model (0 toon, 1 clay), y = posterize textures, z = soft shadows, w = bloom
    float4 lines;      // x = enabled, y = width (pt @1080p), z = darken, w = colour mode (0 darkened, 1 ink)
    float4 lineInk;    // rgb = ink colour (linear), w = boil
    float4 lineShape;  // x = cos(crease angle), y = depth sensitivity, z = pencil (1 / 0), w = unused
    float4 comic;      // x = halftone, y = dot spacing (pt @1080p), z = object-space dots, w = misregistration
    float4 finish;     // x = paper grain, y = paper tint, z = vignette, w = saturation
    float4 grade;      // x = lift, y = gamma, z = gain, w = accent keeps colour
};

struct ObjectUniforms {
    float4x4 model;
    float4x4 normalMatrix;
    float4 baseColor;  // linear rgb, a = opacity
    float4 emissive;   // linear rgb × intensity, w = glow intensity
    float4 params;     // x = smoothing (0 faceted … 1 smooth), y = rim strength (−1 = the look's), z = glossy, w = line weight
    uint4 ids;         // x = object index (1-based), y = look index, z = flags, w = first joint in the joint buffer
};

struct LightData {
    float4 position;   // xyz world, w = range (m)
    float4 color;      // linear rgb × intensity, w = type (0 point, 1 spot)
    float4 direction;  // xyz spot direction, w = cos(outer angle)
    float4 params;     // x = cos(inner angle)
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
    float shadowBias [[attribute(3)]];
};

struct SkinnedVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
    float shadowBias [[attribute(3)]];
    ushort4 joints [[attribute(4)]];
    float4 weights [[attribute(5)]];
};

struct SurfaceVaryings {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float3 viewPosition;
    float2 uv;
    float shadowBias;
    uint objectIndex [[flat]];
};

// ---------------------------------------------------------------------------------------------------------------
// Colour

static inline float3 lw_srgbToLinear(float3 c) {
    float3 low = c / 12.92;
    float3 high = pow((max(c, 0.0) + 0.055) / 1.055, 2.4);
    return select(high, low, c <= 0.04045);
}

static inline float3 lw_linearToSrgb(float3 c) {
    float3 low = c * 12.92;
    float3 high = 1.055 * pow(max(c, 0.0), 1.0 / 2.4) - 0.055;
    return select(high, low, c <= 0.0031308);
}

static inline float lw_luminance(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

static inline float3 lw_rgbToHsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

static inline float3 lw_hsvToRgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, saturate(p - K.xxx), c.y);
}

/// The Looks' shadow colour: never black, never a plain darkening. Value down, saturation up, hue pulled toward the
/// ambient (sky) hue.
static inline float3 lw_shadowColor(float3 base, float3 ambientTint, constant LookUniforms &look) {
    float3 hsv = lw_rgbToHsv(max(base, 0.0));
    float3 ambientHsv = lw_rgbToHsv(max(ambientTint, 0.0001));
    float delta = ambientHsv.x - hsv.x;
    delta -= round(delta); // shortest way around the hue circle
    float shift = look.shadow.x * saturate(ambientHsv.y * 1.5);
    hsv.x = fract(hsv.x + delta * shift);
    hsv.y = saturate(hsv.y + look.shadow.z * (1.0 - hsv.y));
    hsv.z = hsv.z * (1.0 - look.shadow.y);
    return lw_hsvToRgb(hsv);
}

/// Keeps the palette's values exact below 0.8 and rolls highlights off toward 1 (no clipped white blobs).
static inline float3 lw_softClip(float3 c) {
    float3 over = max(c - 0.8, 0.0);
    return min(c, 0.8) + 0.2 * (1.0 - exp(-over / 0.2));
}

// ---------------------------------------------------------------------------------------------------------------
// Noise

static inline float lw_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static inline float lw_hash3(float3 p) {
    return fract(sin(dot(p, float3(127.1, 311.7, 74.7))) * 43758.5453);
}

static inline float lw_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = lw_hash(i);
    float b = lw_hash(i + float2(1, 0));
    float c = lw_hash(i + float2(0, 1));
    float d = lw_hash(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ---------------------------------------------------------------------------------------------------------------
// Packing

static inline uint lw_packID(uint object, uint look, uint flags) {
    return (object & LW_ID_OBJECT_MASK) | ((look & 0xFu) << LW_ID_LOOK_SHIFT) | ((flags & 0xFFu) << LW_ID_FLAGS_SHIFT);
}

static inline uint lw_idObject(uint id) { return id & LW_ID_OBJECT_MASK; }
static inline uint lw_idLook(uint id) { return (id >> LW_ID_LOOK_SHIFT) & 0xFu; }
static inline uint lw_idFlags(uint id) { return (id >> LW_ID_FLAGS_SHIFT) & 0xFFu; }
