// Brush.metal — the brush engine on the GPU: every stamp (dab) of a stroke is one instanced quad sampling the brush's
// tip and grain. The same functions draw ink in a 3D scene (billboards turned to the camera, depth-tested), the
// stroke under the Pencil, and flat strokes in 2D (a board, flipbooks, Brush Studio, previews).
// Output is premultiplied; the colour is in the target's space.

#include <metal_stdlib>
using namespace metal;

struct BrushUniforms {
    float4x4 viewProjection;  // 3D: the camera
    float4x4 model;           // 3D: the drawing's world matrix. 2D: where the stroke's units land in pixels
    float4 eye;               // 3D: xyz camera position (world). 2D: xy = where a fixed grain starts (pixels). w = mode (0 = 2D, 1 = 3D)
    float4 cameraRight;       // xyz (world), w = the model's scale (radius multiplier, 2D and 3D)
    float4 cameraUp;          // xyz (world), w = unused
    float4 color;             // rgb, a = the stroke's opacity
    float4 shape;             // x = roundness, y = angle (rad), z = follows the stroke, w = inverted
    float4 grain;             // x = present, y = scale, z = depth, w = rolling (1) or texturized (0)
    float4 render;            // x = wet edges, y = softness, z = grain inverted, w = texturized tile (pixels at scale 1)
    float4 viewport;          // width, height, 1/width, 1/height (pixels)
};

struct BrushDabData {
    float4 center;     // xyz (2D: xy in the stroke's units, y down), w = radius
    float4 direction;  // xyz unit (zero for a dot), w = sideways offset
    float4 params;     // x = opacity, y = rotation (rad), z = flips (1 = x, 2 = y), w = travel (diameters)
};

struct BrushVaryings {
    float4 position [[position]];
    float2 uv;          // −1…1 across the tip
    float2 grainUV;
    float opacity;
};

/// Where a corner of the tip lands on the brush's two axes, the tip squashed by its roundness and turned.
static inline float2 hmm_tipCorner(float2 corner, float roundness, float angle) {
    float2 squashed = float2(corner.x, corner.y * roundness);
    float c = cos(angle), s = sin(angle);
    return float2(squashed.x * c - squashed.y * s, squashed.x * s + squashed.y * c);
}

vertex BrushVaryings hmm_brushVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                     const device BrushDabData *dabs [[buffer(0)]],
                                     constant BrushUniforms &u [[buffer(1)]]) {
    BrushDabData dab = dabs[iid];
    float2 corner = float2((vid & 1u) != 0u ? 1.0 : -1.0, (vid & 2u) != 0u ? 1.0 : -1.0);
    float2 local = hmm_tipCorner(corner, u.shape.x, u.shape.y + dab.params.y);
    bool follows = u.shape.z > 0.5 && length(dab.direction.xyz) > 1e-6;
    float scale = u.cameraRight.w;
    BrushVaryings out;
    if (u.eye.w > 0.5) {
        float3 center = (u.model * float4(dab.center.xyz, 1.0)).xyz;
        float3 facing = normalize(u.eye.xyz - center);
        float3 along = u.cameraRight.xyz;
        float3 side = u.cameraUp.xyz;
        if (follows) {
            float3 direction = (u.model * float4(dab.direction.xyz, 0.0)).xyz;
            float3 flat = direction - facing * dot(direction, facing);
            if (length(flat) > 1e-6) {
                along = normalize(flat);
                side = cross(facing, along);
            }
        }
        float radius = dab.center.w * scale;
        float3 world = center + side * (dab.direction.w * scale) + (along * local.x + side * local.y) * radius;
        out.position = u.viewProjection * float4(world, 1.0);
    } else {
        float2 along = follows ? normalize(dab.direction.xy) : float2(1.0, 0.0);
        // Pixels run down: the side is a quarter turn anticlockwise as seen, so the tip's top stays up.
        float2 side = float2(along.y, -along.x);
        float2 center = (u.model * float4(dab.center.xy, 0.0, 1.0)).xy;
        float2 pixel = center + side * (dab.direction.w * scale) + (along * local.x + side * local.y) * (dab.center.w * scale);
        out.position = float4(pixel.x * u.viewport.z * 2.0 - 1.0, 1.0 - pixel.y * u.viewport.w * 2.0, 0.0, 1.0);
    }
    uint flips = uint(dab.params.z + 0.5);
    out.uv = float2((flips & 1u) != 0u ? -corner.x : corner.x, (flips & 2u) != 0u ? -corner.y : corner.y);
    float grainScale = max(u.grain.y, 1e-3);
    out.grainUV = (corner * 0.5 + 0.5) / grainScale + float2(dab.params.w / grainScale, 0.0);
    out.opacity = dab.params.x;
    return out;
}

fragment float4 hmm_brushFragment(BrushVaryings in [[stage_in]], constant BrushUniforms &u [[buffer(1)]],
                                  texture2d<float, access::sample> shape [[texture(0)]],
                                  texture2d<float, access::sample> grain [[texture(1)]]) {
    constexpr sampler tip(filter::linear, mip_filter::linear, address::clamp_to_zero);
    constexpr sampler tile(filter::linear, mip_filter::linear, address::repeat);
    float a = shape.sample(tip, in.uv * float2(0.5, -0.5) + 0.5).r;
    if (u.shape.w > 0.5) { a = 1.0 - a; }
    if (u.render.y > 0.0) {
        a *= 1.0 - smoothstep(1.0 - u.render.y, 1.0, length(in.uv));
    }
    if (u.grain.x > 0.5) {
        // A texturized grain is fixed to the paper: in 2D that is the stroke's own units, so it stays put when the
        // view moves or zooms.
        float2 paper = in.position.xy;
        if (u.eye.w < 0.5) { paper = (paper - u.eye.xy) / max(u.model[0][0], 1e-6); }
        float2 coordinates = u.grain.w > 0.5 ? in.grainUV : paper / max(u.render.w, 1.0);
        float value = grain.sample(tile, coordinates).r;
        if (u.render.z > 0.5) { value = 1.0 - value; }
        a *= mix(1.0, value, u.grain.z);
    }
    if (u.render.x > 0.0) {
        // Wet edges: the soft rim pools, the middle thins.
        float rim = a * (1.0 - a) * 4.0;
        a = mix(a, saturate(a * 0.55 + rim * 0.6), u.render.x);
    }
    float alpha = saturate(a * in.opacity * u.color.a);
    return float4(u.color.rgb * alpha, alpha);
}

// ---------------------------------------------------------------------------------------------------------------
// Filled shapes (a flipbook's bursts and drops, a board's arrows and notes): triangles in pixels, one flat
// premultiplied colour.

struct BrushFillUniforms {
    float4 color;     // premultiplied
    float4 viewport;  // width, height, 1/width, 1/height
};

struct BrushFillVaryings {
    float4 position [[position]];
};

vertex BrushFillVaryings hmm_brushFillVertex(uint vid [[vertex_id]], const device float2 *points [[buffer(0)]],
                                             constant BrushFillUniforms &u [[buffer(1)]]) {
    float2 pixel = points[vid];
    BrushFillVaryings out;
    out.position = float4(pixel.x * u.viewport.z * 2.0 - 1.0, 1.0 - pixel.y * u.viewport.w * 2.0, 0.0, 1.0);
    return out;
}

fragment float4 hmm_brushFillFragment(constant BrushFillUniforms &u [[buffer(1)]]) {
    return u.color;
}

// ---------------------------------------------------------------------------------------------------------------
// A drawing painted on its own and laid on its layer at the track's opacity (so its strokes don't darken each other
// where they overlap): a full-frame triangle sampling the scratch layer.

struct BrushLayerVaryings {
    float4 position [[position]];
    float2 uv;
};

vertex BrushLayerVaryings hmm_brushLayerVertex(uint vid [[vertex_id]]) {
    float2 corner = float2((vid << 1u) & 2u, vid & 2u);
    BrushLayerVaryings out;
    out.position = float4(corner * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    out.uv = corner;
    return out;
}

fragment float4 hmm_brushLayerFragment(BrushLayerVaryings in [[stage_in]], constant float4 &opacity [[buffer(1)]],
                                       texture2d<float, access::sample> layer [[texture(0)]]) {
    constexpr sampler exact(filter::nearest, address::clamp_to_edge);
    return layer.sample(exact, in.uv) * opacity.x;
}

// ---------------------------------------------------------------------------------------------------------------
// A picture in a rectangle (a board's pictures, its notes' and titles' words, the board's own cached layer): a quad
// in pixels sampling a premultiplied texture, times an opacity.

struct BrushImageVertex {
    float2 pixel;
    float2 uv;
};

struct BrushImageVaryings {
    float4 position [[position]];
    float2 uv;
};

vertex BrushImageVaryings hmm_brushImageVertex(uint vid [[vertex_id]], const device BrushImageVertex *corners [[buffer(0)]],
                                               constant BrushFillUniforms &u [[buffer(1)]]) {
    BrushImageVertex corner = corners[vid];
    BrushImageVaryings out;
    out.position = float4(corner.pixel.x * u.viewport.z * 2.0 - 1.0, 1.0 - corner.pixel.y * u.viewport.w * 2.0, 0.0, 1.0);
    out.uv = corner.uv;
    return out;
}

fragment float4 hmm_brushImageFragment(BrushImageVaryings in [[stage_in]], constant BrushFillUniforms &u [[buffer(1)]],
                                       texture2d<float, access::sample> image [[texture(0)]]) {
    constexpr sampler smooth(filter::linear, mip_filter::linear, address::clamp_to_edge);
    // `color` tints the picture: white at full strength leaves it as it is, its alpha fades it.
    return image.sample(smooth, in.uv) * u.color;
}
