// Geometry.metal — vertex stages (static and GPU-skinned) and the depth-only passes (sun shadows, prepass).

#include "LoweyCommon.h"

// ---------------------------------------------------------------------------------------------------------------
// Vertex stages

struct Skinned {
    float4 position;
    float3 normal;
};

/// Linear blend skinning with up to four joints (model space).
static inline Skinned lw_skin(float3 position, float3 normal, ushort4 joints, float4 weights, constant float4x4 *palette, uint first) {
    float4x4 m = palette[first + joints.x] * weights.x + palette[first + joints.y] * weights.y
        + palette[first + joints.z] * weights.z + palette[first + joints.w] * weights.w;
    Skinned out;
    out.position = m * float4(position, 1.0);
    out.normal = normalize((m * float4(normal, 0.0)).xyz);
    return out;
}

static inline SurfaceVaryings lw_surface(float4 local, float3 localNormal, float2 uv, float bias, constant ObjectUniforms &object,
                                         constant FrameUniforms &frame) {
    SurfaceVaryings out;
    float4 world = object.model * local;
    out.worldPosition = world.xyz;
    out.worldNormal = normalize((object.normalMatrix * float4(localNormal, 0.0)).xyz);
    out.viewPosition = (frame.view * world).xyz;
    out.position = frame.viewProjection * world;
    out.uv = uv;
    out.shadowBias = bias;
    out.objectIndex = 0;
    return out;
}

vertex SurfaceVaryings lw_vertexStatic(VertexIn in [[stage_in]], uint instance [[instance_id]],
                                        constant ObjectUniforms *objects [[buffer(LW_OBJECTS)]],
                                        constant FrameUniforms &frame [[buffer(LW_FRAME)]]) {
    constant ObjectUniforms &object = objects[instance];
    SurfaceVaryings out = lw_surface(float4(in.position, 1.0), in.normal, in.uv, in.shadowBias, object, frame);
    out.objectIndex = instance;
    return out;
}

vertex SurfaceVaryings lw_vertexSkinned(SkinnedVertexIn in [[stage_in]], uint instance [[instance_id]],
                                         constant ObjectUniforms *objects [[buffer(LW_OBJECTS)]],
                                         constant FrameUniforms &frame [[buffer(LW_FRAME)]],
                                         constant float4x4 *palette [[buffer(LW_JOINTS)]]) {
    constant ObjectUniforms &object = objects[instance];
    Skinned skinned = lw_skin(in.position, in.normal, in.joints, in.weights, palette, object.ids.w);
    SurfaceVaryings out = lw_surface(skinned.position, skinned.normal, in.uv, in.shadowBias, object, frame);
    out.objectIndex = instance;
    return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Sun shadows (depth only, one cascade per pass)

struct ShadowVaryings {
    float4 position [[position]];
};

vertex ShadowVaryings lw_shadowStatic(VertexIn in [[stage_in]], uint instance [[instance_id]],
                                      constant ObjectUniforms *objects [[buffer(LW_OBJECTS)]],
                                      constant FrameUniforms &frame [[buffer(LW_FRAME)]],
                                      constant uint &cascade [[buffer(LW_CASCADE)]]) {
    ShadowVaryings out;
    out.position = frame.shadowMatrices[cascade] * (objects[instance].model * float4(in.position, 1.0));
    return out;
}

vertex ShadowVaryings lw_shadowSkinned(SkinnedVertexIn in [[stage_in]], uint instance [[instance_id]],
                                       constant ObjectUniforms *objects [[buffer(LW_OBJECTS)]],
                                       constant FrameUniforms &frame [[buffer(LW_FRAME)]],
                                       constant float4x4 *palette [[buffer(LW_JOINTS)]],
                                       constant uint &cascade [[buffer(LW_CASCADE)]]) {
    constant ObjectUniforms &object = objects[instance];
    Skinned skinned = lw_skin(in.position, in.normal, in.joints, in.weights, palette, object.ids.w);
    ShadowVaryings out;
    out.position = frame.shadowMatrices[cascade] * (object.model * skinned.position);
    return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Prepass: geometric normal + linear depth, and the ID buffer (object, look, flags). Native resolution, no MSAA:
// lines and picking read it pixel-exact.

struct PrepassOut {
    float4 normalDepth [[color(0)]];
    uint id [[color(1)]];
};

fragment PrepassOut lw_prepass(SurfaceVaryings in [[stage_in]], constant ObjectUniforms *objects [[buffer(LW_OBJECTS)]]) {
    constant ObjectUniforms &object = objects[in.objectIndex];
    // The geometric (faceted) normal from screen derivatives: creases show wherever the surface really bends.
    float3 geometric = normalize(cross(dfdx(in.viewPosition), dfdy(in.viewPosition)));
    // Always facing the camera (the derivative order flips it on some faces).
    geometric = dot(geometric, -in.viewPosition) < 0.0 ? -geometric : geometric;
    PrepassOut out;
    out.normalDepth = float4(geometric, -in.viewPosition.z);
    out.id = lw_packID(object.ids.x, object.ids.y, object.ids.z);
    return out;
}

/// Ground in the prepass: writes depth and a background ID (0), so objects standing on it get outlines and contact
/// shading, and the ground itself is never picked.
fragment PrepassOut lw_prepassGround(SurfaceVaryings in [[stage_in]]) {
    PrepassOut out;
    out.normalDepth = float4(0.0, 0.0, 1.0, -in.viewPosition.z);
    out.id = 0;
    return out;
}

vertex SurfaceVaryings lw_vertexGround(VertexIn in [[stage_in]], constant FrameUniforms &frame [[buffer(LW_FRAME)]]) {
    SurfaceVaryings out;
    float radius = max(frame.groundBounce.w, 1.0);
    float4 world = float4(in.position.x * radius, 0.0, in.position.z * radius, 1.0);
    out.worldPosition = world.xyz;
    out.worldNormal = float3(0, 1, 0);
    out.viewPosition = (frame.view * world).xyz;
    out.position = frame.viewProjection * world;
    out.uv = in.uv;
    out.shadowBias = 0;
    out.objectIndex = 0;
    return out;
}
