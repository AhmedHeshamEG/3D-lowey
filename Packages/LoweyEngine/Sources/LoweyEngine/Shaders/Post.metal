// Post.metal — everything after the lines: bloom, lens (blur or misregistration + chromatic aberration), the Look's
// print language and finish, the project's Finish, and tone mapping. Preview and export run exactly these kernels.

#include "LoweyCommon.h"

struct PostUniforms {
    float4 size;       // width, height, 1/width, 1/height
    float4 grade;      // x = exposure multiplier, y = contrast, z = saturation, w = temperature
    float4 bloom;      // x = intensity, y = threshold, z = scene Look bloom, w = unused
    float4 film;       // x = vignette, y = grain, z = chromatic aberration, w = retro
    float4 texture;    // x = kind (0 none, 1 paper, 2 collage, 3 old film), y = strength, z = frame, w = unused
    float4 lens;       // x = CoC pixels per unit of |1/focus − 1/d|, y = 1/focus, z = max CoC (px), w = mode (0 off, 1 blur, 2 misregistration)
    float4 pixels;     // x = pixels per point (height / 1080), y = frame index, z = boil step, w = unused
};

constexpr sampler lw_postSampler(coord::normalized, address::clamp_to_edge, filter::linear);
constexpr sampler lw_pointSampler(coord::normalized, address::clamp_to_edge, filter::nearest);

// ---------------------------------------------------------------------------------------------------------------
// Bloom: soft-threshold prefilter at half size, a mip chain down, tent upsampling back up.

kernel void lw_bloomPrefilter(texture2d<float, access::sample> source [[texture(0)]],
                              texture2d<float, access::write> output [[texture(1)]],
                              constant PostUniforms &u [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    float2 texel = 1.0 / float2(output.get_width(), output.get_height());
    float2 uv = (float2(gid) + 0.5) * texel;
    float3 sum = 0.0;
    for (int y = -1; y <= 1; y += 2) {
        for (int x = -1; x <= 1; x += 2) {
            sum += source.sample(lw_postSampler, uv + float2(x, y) * texel * 0.25).rgb;
        }
    }
    float3 color = sum * 0.25;
    float brightness = max(color.r, max(color.g, color.b));
    float knee = u.bloom.y * 0.5;
    float soft = clamp(brightness - u.bloom.y + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1e-4);
    float contribution = max(soft, brightness - u.bloom.y) / max(brightness, 1e-4);
    output.write(float4(color * contribution, 1.0), gid);
}

kernel void lw_bloomDown(texture2d<float, access::sample> source [[texture(0)]],
                         texture2d<float, access::write> output [[texture(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    float2 texel = 1.0 / float2(source.get_width(), source.get_height());
    float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
    float3 a = source.sample(lw_postSampler, uv + texel * float2(-1, -1)).rgb;
    float3 b = source.sample(lw_postSampler, uv + texel * float2(1, -1)).rgb;
    float3 c = source.sample(lw_postSampler, uv + texel * float2(-1, 1)).rgb;
    float3 d = source.sample(lw_postSampler, uv + texel * float2(1, 1)).rgb;
    float3 e = source.sample(lw_postSampler, uv).rgb;
    output.write(float4((a + b + c + d) * 0.125 + e * 0.5, 1.0), gid);
}

kernel void lw_bloomUp(texture2d<float, access::sample> smaller [[texture(0)]],
                       texture2d<float, access::read> current [[texture(1)]],
                       texture2d<float, access::write> output [[texture(2)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    float2 texel = 1.0 / float2(smaller.get_width(), smaller.get_height());
    float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
    float3 sum = smaller.sample(lw_postSampler, uv).rgb * 4.0;
    sum += (smaller.sample(lw_postSampler, uv + float2(texel.x, 0)).rgb + smaller.sample(lw_postSampler, uv - float2(texel.x, 0)).rgb
        + smaller.sample(lw_postSampler, uv + float2(0, texel.y)).rgb + smaller.sample(lw_postSampler, uv - float2(0, texel.y)).rgb) * 2.0;
    sum += smaller.sample(lw_postSampler, uv + texel).rgb + smaller.sample(lw_postSampler, uv - texel).rgb
        + smaller.sample(lw_postSampler, uv + float2(texel.x, -texel.y)).rgb + smaller.sample(lw_postSampler, uv + float2(-texel.x, texel.y)).rgb;
    output.write(float4(current.read(gid).rgb + sum / 16.0, 1.0), gid);
}

// ---------------------------------------------------------------------------------------------------------------
// Lens: depth of field as blur (most Looks) or as colour misregistration (Comic), plus chromatic aberration.

kernel void lw_lens(texture2d<float, access::sample> source [[texture(0)]],
                    texture2d<float, access::read> normalDepth [[texture(1)]],
                    texture2d<float, access::write> output [[texture(2)]],
                    constant PostUniforms &u [[buffer(0)]],
                    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uint(u.size.x) || gid.y >= uint(u.size.y)) { return; }
    float2 uv = (float2(gid) + 0.5) * u.size.zw;
    float4 center = source.sample(lw_pointSampler, uv);
    float depth = normalDepth.read(gid).w;
    float coc = 0.0;
    if (u.lens.w > 0.5) {
        float inverse = depth > 0.0 && depth < 1e5 ? 1.0 / depth : 0.0;
        coc = min(abs(u.lens.y - inverse) * u.lens.x, u.lens.z);
    }
    float3 color = center.rgb;
    if (u.lens.w > 1.5 && coc > 0.3) {
        // Misregistration: the colour plates slip apart where the lens would blur.
        float2 offset = float2(coc, coc * 0.35) * u.size.zw;
        color.r = source.sample(lw_postSampler, uv + offset).r;
        color.b = source.sample(lw_postSampler, uv - offset).b;
    } else if (u.lens.w > 0.5 && coc > 0.5) {
        float3 sum = color;
        float weight = 1.0;
        for (int tap = 0; tap < 16; tap++) {
            float t = (float(tap) + 0.5) / 16.0;
            float angle = float(tap) * 2.399963;
            float2 offset = float2(cos(angle), sin(angle)) * sqrt(t) * coc * u.size.zw;
            sum += source.sample(lw_postSampler, uv + offset).rgb;
            weight += 1.0;
        }
        color = sum / weight;
    }
    if (u.film.z > 0.0) {
        float2 fromCenter = uv - 0.5;
        float spread = u.film.z * 0.008;
        color.r = mix(color.r, source.sample(lw_postSampler, 0.5 + fromCenter * (1.0 + spread)).r, 1.0);
        color.b = mix(color.b, source.sample(lw_postSampler, 0.5 + fromCenter * (1.0 - spread)).b, 1.0);
    }
    output.write(float4(color, center.a), gid);
}

// ---------------------------------------------------------------------------------------------------------------
// Look & finish: halftone in the shadow band, bloom, tone mapping, grade, Sketch's desaturation (accents keep
// their colour), paper, the project's Finish (retro, paper / collage / film textures, vignette, grain).

static inline float lw_halftone(float2 pixel, float darkness, float spacing, float amount) {
    float2x2 rotation = float2x2(float2(0.7071, 0.7071), float2(-0.7071, 0.7071));
    float2 cell = rotation * pixel / spacing;
    float2 local = fract(cell) - 0.5;
    float radius = sqrt(saturate(darkness)) * 0.62 * amount;
    return 1.0 - smoothstep(radius - 0.08, radius + 0.08, length(local));
}

static inline float3 lw_grade(float3 color, constant PostUniforms &u, constant LookUniforms &look, bool accent) {
    // Contrast around mid grey, saturation, temperature.
    color = (color - 0.5) * (1.0 + u.grade.y * 0.5) + 0.5;
    float luma = lw_luminance(color);
    float saturation = 1.0 + u.grade.z;
    if (!(accent && look.grade.w > 0.5)) { saturation += look.finish.w; }
    color = mix(float3(luma), color, max(saturation, 0.0));
    color *= float3(1.0 + u.grade.w * 0.1, 1.0, 1.0 - u.grade.w * 0.12);
    // Lift / gamma / gain.
    color = color * (1.0 + look.grade.z) + look.grade.x * (1.0 - color);
    color = pow(max(color, 0.0), float3(1.0 / max(1.0 + look.grade.y, 0.1)));
    return color;
}

kernel void lw_finish(texture2d<float, access::sample> source [[texture(0)]],
                      texture2d<float, access::sample> light [[texture(1)]],
                      texture2d<uint, access::read> ids [[texture(2)]],
                      texture2d<float, access::sample> bloom [[texture(3)]],
                      texture2d<float, access::write> output [[texture(4)]],
                      constant PostUniforms &u [[buffer(0)]],
                      constant LookUniforms *looks [[buffer(1)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uint(u.size.x) || gid.y >= uint(u.size.y)) { return; }
    float2 uv = (float2(gid) + 0.5) * u.size.zw;
    float2 pixel = float2(gid);
    if (u.film.w > 0.0) {
        // Retro: chunky pixels (read at the block's centre) and fewer colours below.
        float block = max(2.0, u.size.y / 540.0 * (2.0 + u.film.w * 6.0));
        pixel = (floor(pixel / block) + 0.5) * block;
        uv = pixel * u.size.zw;
    }
    float4 sampled = source.sample(lw_pointSampler, uv);
    uint id = ids.read(uint2(clamp(pixel, float2(0), u.size.xy - 1.0))).r;
    constant LookUniforms &look = looks[lw_idObject(id) == 0u ? 0u : lw_idLook(id)];
    bool accent = (lw_idFlags(id) & LW_FLAG_ACCENT) != 0u;
    float3 color = sampled.rgb;
    // Halftone dots in the shadow band.
    if (look.comic.x > 0.0 && lw_idObject(id) != 0u) {
        float level = light.sample(lw_postSampler, uv).r;
        float darkness = 1.0 - smoothstep(0.0, 0.5, level);
        float dots = lw_halftone(float2(gid), darkness, look.comic.y * u.pixels.x, look.comic.x);
        color = mix(color, color * 0.55, dots * darkness);
    }
    color += bloom.sample(lw_postSampler, uv).rgb * (u.bloom.x + u.bloom.z);
    color = lw_softClip(color * u.grade.x);
    color = lw_grade(color, u, look, accent);
    // Paper: faint grain and a warm tint (Comic's print, Sketch's sheet).
    if (look.finish.x > 0.0 || look.finish.y > 0.0) {
        float fibre = lw_noise(float2(gid) * 0.9) * 0.5 + lw_noise(float2(gid) * 0.11) * 0.5;
        color *= 1.0 - look.finish.x * 0.08 * fibre;
        color = mix(color, color * float3(1.0, 0.95, 0.82), look.finish.y * 0.6);
    }
    float kind = u.texture.x;
    if (kind > 0.5 && u.texture.y > 0.0) {
        float seed = kind > 2.5 ? u.texture.z : 7.0;
        float blotch = lw_noise(float2(gid) / (u.size.y / 90.0) + seed * 3.1);
        float tone = 1.0 - u.texture.y * (0.3 - 0.35 * blotch);
        color *= tone * float3(1.0, 0.97, 0.9);
        if (kind > 1.5 && kind < 2.5) { color = floor(color * max(5.0, 12.0 - u.texture.y * 6.0) + 0.5) / max(5.0, 12.0 - u.texture.y * 6.0); }
        if (kind > 2.5) {
            color *= 1.0 + (lw_hash(float2(u.texture.z, 1.0)) - 0.5) * 0.24 * u.texture.y;
            float scratchX = lw_hash(float2(u.texture.z, 3.0)) * u.size.x;
            if (abs(float(gid.x) - scratchX) < max(u.size.x / 900.0, 1.0) && lw_hash(float2(u.texture.z, 5.0)) < 0.6) {
                color = mix(color, float3(1.0, 1.0, 0.95), 0.35 * u.texture.y);
            }
        }
    }
    if (u.film.w > 0.0) {
        float levels = max(4.0, 24.0 - u.film.w * 18.0);
        color = floor(color * levels + 0.5) / levels;
    }
    float vignette = max(u.film.x, look.finish.z);
    if (vignette > 0.0) {
        float2 fromCenter = (float2(gid) * u.size.zw - 0.5) * float2(u.size.x * u.size.w, 1.0);
        color *= 1.0 - vignette * smoothstep(0.35, 1.05, length(fromCenter) * 1.2);
    }
    if (u.film.y > 0.0) {
        float noise = lw_hash(float2(gid) + u.pixels.y * 17.0) - 0.5;
        color = saturate(color + noise * u.film.y * 0.12);
    }
    output.write(float4(saturate(color), sampled.a), gid);
}
