import simd

// Swift mirrors of the uniform structs in Shaders/LoweyCommon.h and the kernels. Every member is a SIMD4, a
// simd_uint4 or a simd_float4x4, so Swift and Metal agree on the layout without padding rules.

struct FrameUniforms {
    var view = matrix_identity_float4x4
    var projection = matrix_identity_float4x4
    var viewProjection = matrix_identity_float4x4
    var inverseViewProjection = matrix_identity_float4x4
    var shadowMatrix0 = matrix_identity_float4x4
    var shadowMatrix1 = matrix_identity_float4x4
    var cameraPosition = SIMD4<Float>.zero
    var viewport = SIMD4<Float>.zero
    var sunDirection = SIMD4<Float>(0, 1, 0, 1)
    var sunColor = SIMD4<Float>(1, 1, 1, 0)
    var skyTop = SIMD4<Float>.zero
    var skyHorizon = SIMD4<Float>.zero
    var skyBottom = SIMD4<Float>.zero
    var ambient = SIMD4<Float>(1, 1, 1, 1)
    var groundBounce = SIMD4<Float>(0.4, 0.4, 0.4, 60)
    var fog = SIMD4<Float>.zero
    var cascades = SIMD4<Float>.zero
    var misc = SIMD4<Float>.zero
}

struct LookUniforms: Equatable {
    var bands = SIMD4<Float>.zero
    var shadow = SIMD4<Float>.zero
    var rim = SIMD4<Float>.zero
    var specular = SIMD4<Float>.zero
    var model = SIMD4<Float>.zero
    var lines = SIMD4<Float>.zero
    var lineInk = SIMD4<Float>.zero
    var lineShape = SIMD4<Float>.zero
    var comic = SIMD4<Float>.zero
    var finish = SIMD4<Float>.zero
    var grade = SIMD4<Float>.zero
}

struct ObjectUniforms {
    var model = matrix_identity_float4x4
    var normalMatrix = matrix_identity_float4x4
    var baseColor = SIMD4<Float>(0.8, 0.8, 0.8, 1)
    var emissive = SIMD4<Float>.zero
    /// x = smoothing (−1 = the Look's), y = rim strength (−1 = the Look's), z = glossy, w = line weight.
    var params = SIMD4<Float>(-1, -1, 0, 1)
    /// x = object index (1-based), y = look index, z = flags, w = first joint.
    var ids = SIMD4<UInt32>.zero
}

struct LightData {
    var position = SIMD4<Float>.zero
    var color = SIMD4<Float>.zero
    var direction = SIMD4<Float>.zero
    var params = SIMD4<Float>.zero
}

struct AOParams {
    var projection = SIMD4<Float>.zero
    var size = SIMD4<Float>.zero
}

struct LineUniforms {
    var size = SIMD4<Float>.zero
    var scale = SIMD4<Float>.zero
    var selection = SIMD4<Float>.zero
    var extraInk = SIMD4<Float>.zero
}

struct PostUniforms {
    var size = SIMD4<Float>.zero
    var grade = SIMD4<Float>(1, 0, 0, 0)
    var bloom = SIMD4<Float>(0, 1, 0, 0)
    var film = SIMD4<Float>.zero
    var texture = SIMD4<Float>.zero
    var lens = SIMD4<Float>.zero
    var pixels = SIMD4<Float>.zero
}

struct CompositeUniforms {
    var size = SIMD4<Float>.zero
    var transition = SIMD4<Float>.zero
    var shake = SIMD4<Float>.zero
    var effects = SIMD4<Float>.zero
    var flashColor = SIMD4<Float>.zero
    var guides = SIMD4<Float>.zero
    var options = SIMD4<Float>.zero
}

struct EditorUniforms {
    var viewProjection = matrix_identity_float4x4
    var cameraPosition = SIMD4<Float>.zero
}

struct EditorItemUniforms {
    var model = matrix_identity_float4x4
    var color = SIMD4<Float>(1, 1, 1, 1)
    var params = SIMD4<Float>.zero
}

/// Object flags (ObjectUniforms.ids.z), as in LoweyCommon.h.
struct ObjectFlags: OptionSet {
    let rawValue: UInt32
    static let accent = ObjectFlags(rawValue: 1)
    static let textured = ObjectFlags(rawValue: 2)
    static let selected = ObjectFlags(rawValue: 4)
    static let skinned = ObjectFlags(rawValue: 8)
    static let unlit = ObjectFlags(rawValue: 16)
    static let glossy = ObjectFlags(rawValue: 32)
    /// Ink strokes: line art, so the line pass draws no outlines around them.
    static let ink = ObjectFlags(rawValue: 64)
}

/// Buffer indices, as in LoweyCommon.h.
enum BufferIndex {
    static let vertices = 0
    static let skin = 1
    static let objects = 2
    static let frame = 3
    static let joints = 4
    static let looks = 5
    static let lights = 6
    static let cascade = 7
}

/// ID buffer unpacking, as in LoweyCommon.h.
enum PackedID {
    static func object(_ id: UInt32) -> UInt32 { id & 0xFFFFF }
    static func look(_ id: UInt32) -> UInt32 { (id >> 20) & 0xF }
    static func flags(_ id: UInt32) -> UInt32 { (id >> 24) & 0xFF }
}
