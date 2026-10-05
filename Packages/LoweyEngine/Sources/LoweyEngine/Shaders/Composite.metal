// Composite.metal — the last kernel of every frame: transition between two finished shots, screen effects (shake,
// zoom blur, glitch, speed lines, flash), overlays and captions on top, the Director view's framing guides, and
// the sRGB encoding into the drawable or the encoder's pixel buffer. Preview and export share it exactly.

#include "LoweyCommon.h"

struct CompositeUniforms {
    float4 size;         // output width, height, 1/width, 1/height
    float4 transition;   // x = kind (0 none, 1 cut, 2 fade, 3 dip to black, 4 wipe, 5 zoom through), y = progress, z = eased
    float4 shake;        // xy = offset (fraction of the height), z = roll (rad), w = zoom blur
    float4 effects;      // x = glitch, y = speed lines, z = flash, w = glitch seed
    float4 flashColor;   // rgb linear, w = speed-line seed
    float4 guides;       // x = show, y = mask aspect (w / h, 0 = none), z = thirds, w = safe areas
    float4 options;      // x = overlay present, y = premultiplied alpha output, z = opaque output, w = flipbook layers (1 multiply, 2 screen, 4 add, 8 normal)
};

constexpr sampler lw_compositeSampler(coord::normalized, address::clamp_to_edge, filter::linear);

static inline float2 lw_zoomed(float2 uv, float scale) {
    return (uv - 0.5) / scale + 0.5;
}

static inline float4 lw_transition(texture2d<float, access::sample> to, texture2d<float, access::sample> from, float2 uv,
                                   constant CompositeUniforms &u) {
    float kind = u.transition.x;
    float4 incoming = to.sample(lw_compositeSampler, uv);
    if (kind < 0.5) { return incoming; }
    float p = u.transition.y;
    float eased = u.transition.z;
    if (kind < 1.5) {
        return p < 0.5 ? from.sample(lw_compositeSampler, uv) : incoming;
    }
    if (kind < 2.5) {
        return mix(from.sample(lw_compositeSampler, uv), incoming, eased);
    }
    if (kind < 3.5) {
        float4 image = p < 0.5 ? from.sample(lw_compositeSampler, uv) : incoming;
        float darkness = p < 0.5 ? p * 2.0 : (1.0 - p) * 2.0;
        darkness = darkness * darkness * (3.0 - 2.0 * darkness);
        return float4(image.rgb * (1.0 - darkness), image.a);
    }
    if (kind < 4.5) {
        float mask = smoothstep(eased - 0.02, eased + 0.02, uv.x);
        return mix(incoming, from.sample(lw_compositeSampler, uv), mask);
    }
    // Zoom through: the outgoing shot rushes in, the incoming one settles, crossing in the middle.
    float4 outgoing = from.sample(lw_compositeSampler, lw_zoomed(uv, 1.0 + eased * 1.5));
    float4 settling = to.sample(lw_compositeSampler, lw_zoomed(uv, 0.6 + 0.4 * eased));
    return mix(outgoing, settling, saturate((p - 0.35) / 0.3));
}

static inline float4 lw_screenEffects(float2 uv, texture2d<float, access::sample> to, texture2d<float, access::sample> from,
                                      constant CompositeUniforms &u) {
    float aspect = u.size.x * u.size.w;
    // Shake: offset + roll, slightly zoomed in so the edges never show.
    float2 centered = (uv - 0.5) * float2(aspect, 1.0);
    float roll = u.shake.z;
    float2x2 rotation = float2x2(float2(cos(roll), sin(roll)), float2(-sin(roll), cos(roll)));
    centered = rotation * centered / 1.04 - u.shake.xy;
    float2 shaken = centered / float2(aspect, 1.0) + 0.5;
    float4 color = lw_transition(to, from, shaken, u);
    if (u.shake.w > 0.0) {
        float3 sum = color.rgb;
        for (int tap = 1; tap < 10; tap++) {
            float scale = 1.0 - u.shake.w * 0.06 * float(tap) / 10.0;
            sum += lw_transition(to, from, lw_zoomed(shaken, 1.0 / scale), u).rgb;
        }
        color.rgb = sum / 10.0;
    }
    if (u.effects.x > 0.0) {
        // Glitch: horizontal strips jump sideways, colour plates split.
        float band = floor(uv.y * 24.0);
        float jump = lw_hash(float2(band, u.effects.w)) > 0.72 ? (lw_hash(float2(band + 3.0, u.effects.w)) - 0.5) * 0.16 * u.effects.x : 0.0;
        float2 shifted = shaken + float2(jump, 0.0);
        float split = 0.012 * u.effects.x;
        color.r = lw_transition(to, from, shifted + float2(split, 0), u).r;
        color.g = lw_transition(to, from, shifted, u).g;
        color.b = lw_transition(to, from, shifted - float2(split, 0), u).b;
    }
    if (u.effects.y > 0.0) {
        float2 fromCenter = (uv - 0.5) * float2(aspect, 1.0);
        float angle = atan2(fromCenter.y, fromCenter.x);
        float radius = length(fromCenter);
        float ray = lw_hash(float2(floor(angle * 90.0), u.flashColor.w));
        float line = step(1.0 - 0.18 * u.effects.y, ray) * smoothstep(0.25, 0.75, radius);
        color.rgb = mix(color.rgb, float3(1.0), line * 0.75);
    }
    if (u.effects.z > 0.0) {
        color.rgb = mix(color.rgb, u.flashColor.rgb, saturate(u.effects.z));
    }
    return color;
}

static inline float3 lw_guides(float3 color, float2 pixel, constant CompositeUniforms &u) {
    float2 size = u.size.xy;
    float2 uv = pixel / size;
    float2 lo = float2(0.0);
    float2 hi = float2(1.0);
    if (u.guides.y > 0.0) {
        float frame = u.guides.y;
        float view = size.x / size.y;
        if (frame > view) {
            float h = view / frame;
            lo.y = (1.0 - h) * 0.5;
            hi.y = 1.0 - lo.y;
        } else {
            float w = frame / view;
            lo.x = (1.0 - w) * 0.5;
            hi.x = 1.0 - lo.x;
        }
        if (any(uv < lo) || any(uv > hi)) { return color * 0.35; }
    }
    float2 inner = (uv - lo) / (hi - lo);
    float pixelWidth = 1.0 / min(size.x * (hi.x - lo.x), size.y * (hi.y - lo.y));
    float line = 0.0;
    if (u.guides.z > 0.5) {
        float2 third = abs(fract(inner * 3.0 + 0.5) - 0.5) / 3.0;
        line = max(line, 1.0 - smoothstep(0.0, pixelWidth * 1.5, min(third.x, third.y)) * 1.0);
        if (any(inner < 0.01) || any(inner > 0.99)) { line = 0.0; }
    }
    if (u.guides.w > 0.5) {
        float2 safe = abs(inner - 0.5);
        float edge = min(abs(safe.x - 0.45), abs(safe.y - 0.45));
        bool inside = safe.x <= 0.451 && safe.y <= 0.451;
        line = max(line, inside ? (1.0 - smoothstep(0.0, pixelWidth * 1.5, edge)) * 0.6 : 0.0);
    }
    return mix(color, float3(1.0), line * 0.45);
}

/// Flipbook tracks drawn in multiply, screen or add (premultiplied sRGB stamped by the brush engine), blended in sRGB
/// the way a painting app blends layers.
static inline float4 lw_flipbookLayers(float4 color, float2 uv, texture2d<float, access::sample> multiply,
                                       texture2d<float, access::sample> screen, texture2d<float, access::sample> add, uint mask) {
    float3 below = lw_linearToSrgb(saturate(color.rgb));
    if ((mask & 1u) != 0u) {
        float4 layer = multiply.sample(lw_compositeSampler, uv);
        float3 straight = layer.rgb / max(layer.a, 1e-4);
        below = mix(below, below * straight, layer.a);
    }
    if ((mask & 2u) != 0u) {
        float4 layer = screen.sample(lw_compositeSampler, uv);
        float3 straight = layer.rgb / max(layer.a, 1e-4);
        below = mix(below, 1.0 - (1.0 - below) * (1.0 - straight), layer.a);
    }
    if ((mask & 4u) != 0u) {
        float4 layer = add.sample(lw_compositeSampler, uv);
        below = saturate(below + layer.rgb);
        color.a = max(color.a, layer.a);
    }
    return float4(lw_srgbToLinear(below), color.a);
}

kernel void lw_composite(texture2d<float, access::sample> to [[texture(0)]],
                         texture2d<float, access::sample> from [[texture(1)]],
                         texture2d<float, access::sample> overlay [[texture(2)]],
                         texture2d<float, access::write> output [[texture(3)]],
                         texture2d<float, access::sample> multiply [[texture(4)]],
                         texture2d<float, access::sample> screen [[texture(5)]],
                         texture2d<float, access::sample> add [[texture(6)]],
                         texture2d<float, access::sample> normal [[texture(7)]],
                         constant CompositeUniforms &u [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uint(u.size.x) || gid.y >= uint(u.size.y)) { return; }
    float2 uv = (float2(gid) + 0.5) * u.size.zw;
    float4 color = lw_screenEffects(uv, to, from, u);
    uint layers = uint(u.options.w + 0.5);
    if (layers != 0u) {
        color = lw_flipbookLayers(color, uv, multiply, screen, add, layers);
    }
    if ((layers & 8u) != 0u) {
        // Normal flipbooks: laid over the shot, under the overlays.
        float4 layer = normal.sample(lw_compositeSampler, uv);
        float3 below = lw_linearToSrgb(saturate(color.rgb));
        color.rgb = lw_srgbToLinear(layer.rgb + below * (1.0 - layer.a));
        color.a = layer.a + color.a * (1.0 - layer.a);
    }
    if (u.options.x > 0.5) {
        // Overlays and captions: premultiplied sRGB drawn by Core Graphics.
        float4 layer = overlay.sample(lw_compositeSampler, uv);
        float3 below = lw_linearToSrgb(saturate(color.rgb));
        float3 composed = layer.rgb + below * (1.0 - layer.a);
        color.rgb = lw_srgbToLinear(composed);
        color.a = layer.a + color.a * (1.0 - layer.a);
    }
    if (u.guides.x > 0.5) {
        color.rgb = lw_guides(color.rgb, float2(gid) + 0.5, u);
    }
    float3 encoded = lw_linearToSrgb(saturate(color.rgb));
    float alpha = u.options.z > 0.5 ? 1.0 : saturate(color.a);
    if (u.options.y > 0.5) { encoded *= alpha; }
    output.write(float4(encoded, alpha), gid);
}
