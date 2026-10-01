import LoweyCore
import simd

/// Two sun-shadow cascades fitted to the shot camera: each is a bounding sphere of a frustum slice, so its size
/// doesn't change as the camera turns, and its centre snaps to shadow-map texels, so edges don't crawl when the
/// camera moves ("stable fit").
enum ShadowCascades {
    /// Far distance of each cascade for a camera and the scene's extent.
    static func splits(camera: RenderCamera, sceneBounds: Bounds?) -> SIMD2<Float> {
        let reach = sceneBounds.map { simd_distance($0.center.float3, camera.position) + Float($0.size.length / 2) } ?? 60
        let far = min(max(reach, 8), 120)
        return SIMD2<Float>(min(far * 0.22, 14), far)
    }

    static func matrices(camera: RenderCamera, aspect: Float, sunToward: SIMD3<Float>, sceneBounds: Bounds?,
                         mapSize: Int) -> (SIMD2<Float>, simd_float4x4, simd_float4x4) {
        let splits = splits(camera: camera, sceneBounds: sceneBounds)
        let first = matrix(camera: camera, aspect: aspect, near: camera.near, far: splits.x, sunToward: sunToward,
                           sceneBounds: sceneBounds, mapSize: mapSize)
        let second = matrix(camera: camera, aspect: aspect, near: splits.x * 0.9, far: splits.y, sunToward: sunToward,
                            sceneBounds: sceneBounds, mapSize: mapSize)
        return (splits, first, second)
    }

    static func matrix(camera: RenderCamera, aspect: Float, near: Float, far: Float, sunToward: SIMD3<Float>, sceneBounds: Bounds?,
                       mapSize: Int) -> simd_float4x4 {
        // Bounding sphere of the slice.
        let tanY = tan(camera.fieldOfView * .pi / 360)
        let tanX = tanY * aspect
        var corners: [SIMD3<Float>] = []
        for distance in [near, far] {
            for sx in [Float(-1), 1] {
                for sy in [Float(-1), 1] {
                    let local = SIMD3<Float>(sx * tanX * distance, sy * tanY * distance, -distance)
                    corners.append(camera.position + camera.orientation.act(local))
                }
            }
        }
        let center = corners.reduce(.zero, +) / Float(corners.count)
        let radius = max(corners.map { simd_distance($0, center) }.max() ?? 1, 0.5)
        let direction = simd_normalize(sunToward)
        let up = abs(direction.y) > 0.95 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
        let view = lookAt(eye: .zero, target: -direction, up: up)
        // Snap the centre to whole texels in light space.
        var lightCenter = view * SIMD4<Float>(center, 1)
        let texel = 2 * radius / Float(mapSize)
        lightCenter.x = (lightCenter.x / texel).rounded() * texel
        lightCenter.y = (lightCenter.y / texel).rounded() * texel
        // Depth range: everything in the scene that can cast into the slice, not just the slice itself.
        var nearDepth = -lightCenter.z - radius
        var farDepth = -lightCenter.z + radius
        if let bounds = sceneBounds {
            for corner in bounds.corners {
                let depth = -(view * SIMD4<Float>(corner.float3, 1)).z
                nearDepth = min(nearDepth, depth)
                farDepth = max(farDepth, depth)
            }
        }
        let projection = orthographic(left: lightCenter.x - radius, right: lightCenter.x + radius, bottom: lightCenter.y - radius,
                                      top: lightCenter.y + radius, near: nearDepth - 1, far: farDepth + 1)
        return projection * view
    }

    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, up))
        let trueUp = simd_cross(right, forward)
        return simd_float4x4(rows: [SIMD4<Float>(right, -simd_dot(right, eye)), SIMD4<Float>(trueUp, -simd_dot(trueUp, eye)),
                                    SIMD4<Float>(-forward, simd_dot(forward, eye)), SIMD4<Float>(0, 0, 0, 1)])
    }

    /// Orthographic projection, depth 0 (near) … 1 (far).
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
        let width = right - left
        let height = top - bottom
        let depth = far - near
        return simd_float4x4(columns: (
            SIMD4<Float>(2 / width, 0, 0, 0),
            SIMD4<Float>(0, 2 / height, 0, 0),
            SIMD4<Float>(0, 0, -1 / depth, 0),
            SIMD4<Float>(-(right + left) / width, -(top + bottom) / height, -near / depth, 1)
        ))
    }
}
