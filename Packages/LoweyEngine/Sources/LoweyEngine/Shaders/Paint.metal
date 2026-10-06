// Paint.metal — colour painted on models. Every pass draws the object's paint mesh flat in its texture's space (a
// vertex's uv is its place on screen), so each pixel of a layer knows where it sits on the model:
//   project  — a stroke (or a picture) on the screen lands on the texels the camera sees, through the frame's own
//              ID buffer and depth (nothing paints through what stands in front, nor round the back);
//   coverage — which texels the unwrap uses, once per surface;
//   compose  — layers laid over each other with their blend mode and opacity (premultiplied, stored sRGB values);
//   finish   — the composite turned straight-alpha and pushed a few texels past each chart's edge (no seams).

#include "LoweyCommon.h"

struct PaintUniforms {
    float4x4 model;           // the object's world matrix (as drawn this frame)
    float4x4 normalMatrix;
    float4x4 viewProjection;  // the camera the stroke is seen through
    float4 eye;               // xyz camera position, w = orthographic (1) or not
    float4 forward;           // xyz the way the camera looks
    float4 screen;            // width, height (pixels of the ID buffer and the stroke), 1/width, 1/height
    float4 params;            // x = the object's index in the ID buffer, y = depth tolerance, z = unused, w = unused
};

struct PaintVaryings {
    float4 position [[position]];
    float3 world;
    float3 normal;
};

/// A paint mesh vertex at its uv: x right, y down the texture.
vertex PaintVaryings lw_paintVertex(VertexIn in [[stage_in]], constant PaintUniforms &u [[buffer(1)]]) {
    PaintVaryings out;
    out.position = float4(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0, 0.0, 1.0);
    out.world = (u.model * float4(in.position, 1.0)).xyz;
    out.normal = normalize((u.normalMatrix * float4(in.normal, 0.0)).xyz);
    return out;
}

fragment float4 lw_paintProject(PaintVaryings in [[stage_in]], constant PaintUniforms &u [[buffer(1)]],
                                texture2d<float, access::sample> stroke [[texture(0)]],
                                texture2d<uint, access::read> ids [[texture(1)]],
                                depth2d<float, access::read> depth [[texture(2)]]) {
    float4 clip = u.viewProjection * float4(in.world, 1.0);
    if (clip.w <= 0.0) { discard_fragment(); }
    float3 ndc = clip.xyz / clip.w;
    float2 uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (any(uv < 0.0) || any(uv >= 1.0)) { discard_fragment(); }
    uint2 pixel = uint2(uv * u.screen.xy);
    // Only where this object is the one seen, and this texel is the surface seen there (reverse-Z: nearer is larger).
    uint packed = ids.read(pixel).r;
    if ((packed & LW_ID_OBJECT_MASK) != uint(u.params.x + 0.5)) { discard_fragment(); }
    float seen = depth.read(pixel);
    if (ndc.z < seen - max(seen * u.params.y, 1e-6)) { discard_fragment(); }
    float3 toEye = u.eye.w > 0.5 ? -normalize(u.forward.xyz) : normalize(u.eye.xyz - in.world);
    float facing = dot(normalize(in.normal), toEye);
    if (facing <= 0.0) { discard_fragment(); }
    constexpr sampler screen(filter::linear, address::clamp_to_zero);
    // Grazing surfaces take paint gently (the stroke would smear across them).
    return stroke.sample(screen, uv) * smoothstep(0.0, 0.25, facing);
}

fragment float4 lw_paintCoverage(PaintVaryings in [[stage_in]]) {
    return float4(1.0);
}

// ---------------------------------------------------------------------------------------------------------------
// Layers

struct PaintComposeUniforms {
    float4 params;  // x = opacity, y = blend (0 normal, 1 multiply, 2 screen, 3 overlay, 4 add)
};

struct PaintFullVaryings {
    float4 position [[position]];
    float2 uv;
};

vertex PaintFullVaryings lw_paintFullVertex(uint vid [[vertex_id]]) {
    float2 corner = float2((vid << 1u) & 2u, vid & 2u);
    PaintFullVaryings out;
    out.position = float4(corner * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    out.uv = corner;
    return out;
}

static inline float3 lw_paintBlend(float3 b, float3 s, uint mode) {
    switch (mode) {
    case 1u: return b * s;
    case 2u: return b + s - b * s;
    case 3u: return select(1.0 - 2.0 * (1.0 - b) * (1.0 - s), 2.0 * b * s, b <= 0.5);
    case 4u: return min(b + s, 1.0);
    default: return s;
    }
}

/// One layer over the layers under it (both premultiplied): Cs' = (1 − αb)·Cs + αb·B(Cb, Cs), then source-over.
fragment float4 lw_paintCompose(PaintFullVaryings in [[stage_in]], constant PaintComposeUniforms &u [[buffer(1)]],
                                texture2d<float, access::read> backdrop [[texture(0)]],
                                texture2d<float, access::read> layer [[texture(1)]]) {
    uint2 pixel = uint2(in.position.xy);
    float4 under = backdrop.read(pixel);
    float4 over = layer.read(pixel);
    float alpha = over.a * u.params.x;
    if (alpha <= 0.0) { return under; }
    float3 source = over.rgb / max(over.a, 1e-6);
    float3 mixed = source;
    if (u.params.y > 0.5 && under.a > 0.0) {
        float3 base = under.rgb / under.a;
        mixed = source * (1.0 - under.a) + lw_paintBlend(base, source, uint(u.params.y + 0.5)) * under.a;
    }
    return float4(mixed * alpha + under.rgb * (1.0 - alpha), alpha + under.a * (1.0 - alpha));
}

/// The composite as the shading pass reads it: straight alpha, and every empty texel within four of a chart filled
/// from the chart's texels (alpha-weighted), so filtering at a chart's edge never reaches an empty texel.
fragment float4 lw_paintFinish(PaintFullVaryings in [[stage_in]],
                               texture2d<float, access::read> composite [[texture(0)]],
                               texture2d<float, access::read> coverage [[texture(1)]]) {
    int2 pixel = int2(in.position.xy);
    int2 size = int2(composite.get_width(), composite.get_height());
    if (coverage.read(uint2(pixel)).r > 0.5) {
        float4 c = composite.read(uint2(pixel));
        return c.a > 0.0 ? float4(c.rgb / c.a, c.a) : float4(0.0);
    }
    float4 sum = 0.0;
    float count = 0.0;
    for (int dy = -4; dy <= 4; dy++) {
        for (int dx = -4; dx <= 4; dx++) {
            int2 at = pixel + int2(dx, dy);
            if (any(at < 0) || any(at >= size)) { continue; }
            if (coverage.read(uint2(at)).r < 0.5) { continue; }
            sum += composite.read(uint2(at));
            count += 1.0;
        }
    }
    if (count == 0.0 || sum.a <= 0.0) { return float4(0.0); }
    return float4(sum.rgb / sum.a, sum.a / count);
}
