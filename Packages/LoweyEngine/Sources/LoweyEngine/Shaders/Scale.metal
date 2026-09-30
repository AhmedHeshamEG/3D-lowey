// Scale.metal — bilinear upscaling of the shaded image when MetalFX isn't available (lines and overlays are drawn
// after this, at native resolution, so edges stay crisp either way).

#include "LoweyCommon.h"

kernel void lw_upscale(texture2d<float, access::sample> source [[texture(0)]],
                       texture2d<float, access::write> output [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
    output.write(source.sample(bilinear, uv), gid);
}
