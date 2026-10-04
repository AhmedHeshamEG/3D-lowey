// Lines.metal — contact shading (SSAO) and the Looks' ink lines, both screen space.

#include "LoweyCommon.h"

// ---------------------------------------------------------------------------------------------------------------
// Contact shading: 8-tap hemisphere SSAO at half the shading resolution. Only the shadow band uses it (the shading
// shader mixes it in there), so it grounds objects without looking like PBR.

struct AOParams {
    float4 projection;   // x = P[0][0], y = P[1][1], z = radius (m), w = intensity
    float4 size;         // output width, height, source width, source height
};

static inline float3 lw_viewPosition(float2 uv, float depth, constant AOParams &p) {
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    return float3(ndc.x * depth / p.projection.x, ndc.y * depth / p.projection.y, -depth);
}

kernel void lw_ssao(texture2d<float, access::sample> normalDepth [[texture(0)]],
                    texture2d<float, access::write> output [[texture(1)]],
                    constant AOParams &p [[buffer(0)]],
                    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uint(p.size.x) || gid.y >= uint(p.size.y)) { return; }
    constexpr sampler pointSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    float2 uv = (float2(gid) + 0.5) / p.size.xy;
    float4 center = normalDepth.sample(pointSampler, uv);
    float depth = center.w;
    if (depth <= 0.0 || depth > 500.0 || length(center.xyz) < 0.5) {
        output.write(float4(1.0), gid);
        return;
    }
    float3 position = lw_viewPosition(uv, depth, p);
    float3 normal = normalize(center.xyz);
    // A per-pixel rotation of the kernel (4×4 interleaved), so 8 taps look like many.
    float angle = lw_hash(float2(gid % 4u)) * 6.2831853;
    float3 tangent = normalize(cross(normal, abs(normal.y) < 0.9 ? float3(0, 1, 0) : float3(1, 0, 0)));
    float3 bitangent = cross(normal, tangent);
    float radius = p.projection.z * clamp(depth / 6.0, 0.35, 2.5);
    float occlusion = 0.0;
    for (int tap = 0; tap < 8; tap++) {
        float t = (float(tap) + 0.5) / 8.0;
        float a = angle + float(tap) * 2.399963;
        float r = sqrt(t);
        float3 direction = tangent * (cos(a) * r) + bitangent * (sin(a) * r) + normal * sqrt(max(1.0 - t, 0.0));
        float3 sample = position + direction * radius * mix(0.35, 1.0, t);
        float2 sampleNdc = float2(sample.x * p.projection.x / -sample.z, sample.y * p.projection.y / -sample.z);
        float2 sampleUV = float2(sampleNdc.x * 0.5 + 0.5, 0.5 - sampleNdc.y * 0.5);
        float sceneDepth = normalDepth.sample(pointSampler, sampleUV).w;
        float difference = -sample.z - sceneDepth;
        float rangeCheck = smoothstep(0.0, 1.0, radius / max(abs(depth - sceneDepth), 1e-4));
        occlusion += (difference > 0.02 ? 1.0 : 0.0) * rangeCheck;
    }
    float ao = 1.0 - (occlusion / 8.0) * p.projection.w;
    output.write(float4(saturate(ao)), gid);
}

// ---------------------------------------------------------------------------------------------------------------
// Lines from the ID, normal and depth buffers, at native resolution after upscaling (always crisp).
//
// A pixel is on a line when, within the line's half-width, it finds another object (a silhouette or material
// border), a crease (normals bending more than the Look's crease angle) or a depth fold. Lines are drawn on the
// nearer surface, anti-aliased by distance to the edge, thinner with distance and with fading creases (tapered
// ends), jittered on twos for "boil", grainy for pencil.

struct LineUniforms {
    float4 size;         // width, height, 1/width, 1/height
    float4 scale;        // x = pixels per point (height / 1080), y = boil step (frame / 2), z = extra outline width, w = unused
    float4 selection;    // rgb = selection colour (linear), w = 1 to draw the selection outline
    float4 extraInk;     // rgb = Finish outline colour (linear), w = unused
};

struct EdgeHit {
    float distance;
    float strength;
    uint neighbor;
};

static inline EdgeHit lw_findEdge(texture2d<uint, access::read> ids, texture2d<float, access::read> normalDepth, int2 p, uint centerID,
                                  float4 center, constant LookUniforms &look, float radius, float2 jitter, constant LineUniforms &u) {
    const int2 directions[8] = { int2(1, 0), int2(-1, 0), int2(0, 1), int2(0, -1), int2(1, 1), int2(-1, 1), int2(1, -1), int2(-1, -1) };
    EdgeHit best;
    best.distance = 1e6;
    best.strength = 0.0;
    best.neighbor = centerID;
    int steps = int(ceil(radius)) + 1;
    uint object = lw_idObject(centerID);
    float depthThreshold = mix(0.35, 0.04, look.lineShape.y);
    for (int d = 0; d < 8; d++) {
        float2 direction = float2(directions[d]);
        float stepLength = length(direction);
        for (int r = 1; r <= steps; r++) {
            float travelled = float(r) * stepLength;
            if (travelled - 0.5 > best.distance) { break; }
            int2 q = clamp(p + int2(round(direction * float(r) + jitter)), int2(0), int2(u.size.xy) - 1);
            uint neighborID = ids.read(uint2(q)).r;
            float4 neighbor = normalDepth.read(uint2(q));
            uint other = lw_idObject(neighborID);
            float strength = 0.0;
            if ((lw_idFlags(neighborID) & LW_FLAG_INK) != 0u) {
                // Ink strokes are lines already: no outline where they cross something.
                continue;
            }
            if (other != object) {
                // Another object: a line on this side only if this side is nearer.
                strength = (other == 0u || neighbor.w >= center.w - 0.01) ? 1.0 : 0.0;
            } else {
                float bend = dot(normalize(center.xyz), normalize(neighbor.xyz));
                if (bend < look.lineShape.x) {
                    strength = saturate((look.lineShape.x - bend) / 0.25 + 0.35);
                }
                float fold = (neighbor.w - center.w) / max(center.w, 0.01);
                if (fold > depthThreshold) {
                    strength = max(strength, saturate(fold / depthThreshold - 0.6));
                }
            }
            if (strength > 0.0) {
                if (travelled < best.distance) {
                    best.distance = travelled;
                    best.strength = strength;
                    best.neighbor = neighborID;
                }
                break;
            }
        }
    }
    return best;
}

kernel void lw_lines(texture2d<float, access::read> color [[texture(0)]],
                     texture2d<uint, access::read> ids [[texture(1)]],
                     texture2d<float, access::read> normalDepth [[texture(2)]],
                     texture2d<float, access::write> output [[texture(3)]],
                     constant LookUniforms *looks [[buffer(0)]],
                     constant float *lineWeights [[buffer(1)]],
                     constant LineUniforms &u [[buffer(2)]],
                     uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uint(u.size.x) || gid.y >= uint(u.size.y)) { return; }
    float4 shaded = color.read(gid);
    uint centerID = ids.read(gid).r;
    uint object = lw_idObject(centerID);
    if (object == 0u) {
        output.write(shaded, gid);
        return;
    }
    if ((lw_idFlags(centerID) & LW_FLAG_INK) != 0u && (lw_idFlags(centerID) & LW_FLAG_SELECTED) == 0u) {
        output.write(shaded, gid);
        return;
    }
    constant LookUniforms &look = looks[lw_idLook(centerID)];
    bool selected = (lw_idFlags(centerID) & LW_FLAG_SELECTED) != 0u && u.selection.w > 0.5;
    bool ink = look.lines.x > 0.5;
    float extra = u.scale.z;
    if ((lw_idFlags(centerID) & LW_FLAG_INK) != 0u) {
        // A selected ink stroke: only the selection outline.
        ink = false;
        extra = 0.0;
    }
    if (!ink && extra <= 0.0 && !selected) {
        output.write(shaded, gid);
        return;
    }
    float4 center = normalDepth.read(gid);
    float distanceScale = clamp(4.0 / sqrt(max(center.w, 1.0)), 0.5, 1.5);
    float width = (ink ? look.lines.y : extra) * u.scale.x * lineWeights[object] * distanceScale;
    width = max(width, selected ? 2.5 * u.scale.x : 0.0);
    float2 jitter = 0.0;
    if (look.lineInk.w > 0.0) {
        float2 seed = float2(gid) * 0.045 + u.scale.y * 13.7;
        jitter = (float2(lw_noise(seed), lw_noise(seed + 31.0)) - 0.5) * 2.4 * look.lineInk.w;
    }
    EdgeHit edge = lw_findEdge(ids, normalDepth, int2(gid), centerID, center, look, width * 0.5 + 1.0, jitter, u);
    if (edge.strength <= 0.0) {
        output.write(shaded, gid);
        return;
    }
    float halfWidth = width * mix(0.35, 0.5, edge.strength);
    float coverage = saturate(halfWidth - (edge.distance - 1.0) + 0.5) * edge.strength;
    if (look.lineShape.z > 0.5) {
        // Pencil: grainy and uneven along the stroke.
        float grain = lw_noise(float2(gid) * 0.7) * 0.6 + lw_noise(float2(gid) * 0.13 + u.scale.y) * 0.4;
        coverage *= mix(0.45, 1.0, grain);
    }
    float3 lineColor;
    if (look.lines.w > 0.5 || !ink) {
        lineColor = ink ? look.lineInk.rgb : u.extraInk.rgb;
    } else {
        float3 hsv = lw_rgbToHsv(max(shaded.rgb, 0.0));
        hsv.y = saturate(hsv.y * 1.25 + 0.05);
        hsv.z *= (1.0 - look.lines.z);
        lineColor = lw_hsvToRgb(hsv);
    }
    bool silhouette = lw_idObject(edge.neighbor) != object;
    bool neighborSelected = (lw_idFlags(edge.neighbor) & LW_FLAG_SELECTED) != 0u;
    if (selected && silhouette && !neighborSelected) {
        lineColor = u.selection.rgb;
        coverage = max(coverage, saturate(1.25 * u.scale.x - (edge.distance - 1.0) + 0.5));
    }
    output.write(float4(mix(shaded.rgb, lineColor, coverage), shaded.a), gid);
}
