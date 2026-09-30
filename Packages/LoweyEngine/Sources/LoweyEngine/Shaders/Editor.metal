// Editor.metal — what only the stage shows, drawn by the same renderer on top of the finished frame: the building
// grid, gizmos, light and camera icons, the drawing guide and the stroke preview. Colours are sRGB (the frame
// below is already encoded).

#include "LoweyCommon.h"

struct EditorUniforms {
    float4x4 viewProjection;
    float4 cameraPosition;   // xyz, w = radians per pixel (2·tan(fov/2) / height)
};

struct EditorVertex {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
    float shadowBias [[attribute(3)]];
};

struct EditorItem {
    float4x4 model;
    float4 color;            // sRGB, a = opacity
    float4 params;           // x = shade by normal (0 / 1)
};

struct EditorVaryings {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float4 color;
    float shade;
};

vertex EditorVaryings lw_editorVertex(EditorVertex in [[stage_in]], constant EditorUniforms &u [[buffer(3)]],
                                      constant EditorItem &item [[buffer(2)]]) {
    EditorVaryings out;
    float4 world = item.model * float4(in.position, 1.0);
    out.position = u.viewProjection * world;
    out.world = world.xyz;
    out.normal = normalize((item.model * float4(in.normal, 0.0)).xyz);
    out.color = item.color;
    out.shade = item.params.x;
    return out;
}

fragment float4 lw_editorFragment(EditorVaryings in [[stage_in]], constant EditorUniforms &u [[buffer(3)]]) {
    float3 color = in.color.rgb;
    if (in.shade > 0.5) {
        float3 view = normalize(u.cameraPosition.xyz - in.world);
        color *= 0.72 + 0.28 * saturate(dot(normalize(in.normal), view));
    }
    return float4(color * in.color.a, in.color.a);
}

// ---------------------------------------------------------------------------------------------------------------
// The grid: 1 m and 5 m lines, red X and blue Z axes, a pixel wide at any distance, fading into the distance.

static inline float lw_gridLines(float2 p, float2 footprint, float spacing, float widthPixels) {
    float2 q = p / spacing;
    float2 f = max(footprint / spacing, float2(1e-5));
    float2 d = abs(fract(q - 0.5) - 0.5);
    float2 halfWidth = 0.5 * widthPixels * f;
    float2 a = 1.0 - smoothstep(halfWidth, halfWidth + f, d);
    a *= 1.0 - smoothstep(0.12, 0.35, f);
    return max(a.x, a.y);
}

static inline float lw_axisLine(float coordinate, float footprint, float widthPixels) {
    float halfWidth = 0.5 * widthPixels * footprint;
    return 1.0 - smoothstep(halfWidth, halfWidth + footprint, abs(coordinate));
}

fragment float4 lw_gridFragment(EditorVaryings in [[stage_in]], constant EditorUniforms &u [[buffer(3)]]) {
    float3 eye = u.cameraPosition.xyz;
    float3 direction = normalize(in.world - eye);
    float distance = length(in.world - eye);
    float across = distance * max(u.cameraPosition.w, 1e-6);
    float along = across / max(abs(direction.y), 0.03);
    float2 h = length(direction.xz) > 1e-4 ? normalize(direction.xz) : float2(1.0, 0.0);
    float2 footprint = float2(length(float2(h.x * along, h.y * across)), length(float2(h.y * along, h.x * across)));
    float2 p = in.world.xz;
    float alpha = max(lw_gridLines(p, footprint, 1.0, 1.1) * 0.16, lw_gridLines(p, footprint, 5.0, 1.7) * 0.32);
    float3 color = float3(1.0);
    float xAxis = lw_axisLine(p.y, footprint.y, 2.4);
    float zAxis = lw_axisLine(p.x, footprint.x, 2.4);
    color = mix(color, float3(0.95, 0.35, 0.35), xAxis);
    alpha = max(alpha, xAxis * 0.8);
    color = mix(color, float3(0.35, 0.55, 1.0), zAxis);
    alpha = max(alpha, zAxis * 0.8);
    float reach = clamp(abs(eye.y) * 22.0, 35.0, 380.0);
    alpha *= 1.0 - smoothstep(reach * 0.3, reach, length(in.world.xz - eye.xz));
    return float4(color * alpha, alpha);
}
