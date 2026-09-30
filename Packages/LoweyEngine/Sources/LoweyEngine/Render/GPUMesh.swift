import Foundation
import LoweyCore
import Metal

/// A mesh on the GPU: interleaved vertices (position, normal, uv, shadow bias), 32-bit indices, and for skinned
/// meshes a second buffer of joints + weights. Keeps its `MeshData` for bounds, picking and "draw on object".
final class GPUMesh {
    static let vertexStride = 36
    static let skinStride = 24

    let vertices: MTLBuffer
    let indices: MTLBuffer
    let skin: MTLBuffer?
    let indexCount: Int
    let data: MeshData
    let bounds: Bounds
    /// Bytes on the GPU (for the cache budget).
    let byteSize: Int

    var isSkinned: Bool { skin != nil }

    init?(device: MTLDevice, mesh: MeshData, shadowBias: [Float] = [], joints: [SIMD4<UInt16>] = [], weights: [SIMD4<Float>] = [],
          label: String) {
        guard !mesh.isEmpty, let bounds = mesh.bounds else { return nil }
        let count = mesh.positions.count
        var interleaved = [Float](repeating: 0, count: count * 9)
        for index in 0 ..< count {
            let base = index * 9
            let position = mesh.positions[index]
            let normal = index < mesh.normals.count ? mesh.normals[index] : SIMD3<Float>(0, 1, 0)
            let uv = index < mesh.uvs.count ? mesh.uvs[index] : .zero
            interleaved[base] = position.x
            interleaved[base + 1] = position.y
            interleaved[base + 2] = position.z
            interleaved[base + 3] = normal.x
            interleaved[base + 4] = normal.y
            interleaved[base + 5] = normal.z
            interleaved[base + 6] = uv.x
            interleaved[base + 7] = uv.y
            interleaved[base + 8] = index < shadowBias.count ? shadowBias[index] : 0
        }
        guard let vertices = device.makeBuffer(bytes: interleaved, length: interleaved.count * 4, options: .storageModeShared),
              let indices = device.makeBuffer(bytes: mesh.indices, length: max(mesh.indices.count, 1) * 4, options: .storageModeShared)
        else { return nil }
        vertices.label = "\(label) vertices"
        indices.label = "\(label) indices"
        var skinBuffer: MTLBuffer?
        if joints.count == count, weights.count == count {
            var packed = Data(capacity: count * Self.skinStride)
            for index in 0 ..< count {
                var joint = joints[index]
                var weight = weights[index]
                withUnsafeBytes(of: &joint) { packed.append(contentsOf: $0) }
                withUnsafeBytes(of: &weight) { packed.append(contentsOf: $0) }
            }
            skinBuffer = packed.withUnsafeBytes { raw in
                raw.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: packed.count, options: .storageModeShared) }
            }
            skinBuffer?.label = "\(label) skin"
        }
        self.vertices = vertices
        self.indices = indices
        skin = skinBuffer
        indexCount = mesh.indices.count
        data = mesh
        self.bounds = bounds
        byteSize = vertices.length + indices.length + (skinBuffer?.length ?? 0)
    }
}

/// Everything that decides a mesh's geometry (the transform and colour never do).
indirect enum MeshKey: Hashable {
    case primitive(PrimitiveShape, faceted: Bool)
    case bevelled(PrimitiveShape, size: SIMD3<Int32>, radius: Int32, segments: Int)
    case drawing(DrawingRecipe)
    case blockText(TextRecipe)
    case systemText(TextRecipe)
    case card(width: Int32, height: Int32, depth: Int32)
    case picture(width: Int32, height: Int32)
    case asset(AssetID, part: Int)
    case painted(MeshKey, dabs: [ShadowDab])

    /// Millimetre quantisation for size-dependent meshes (bevels, cards).
    static func mm(_ value: Double) -> Int32 {
        Int32((value * 1000).rounded())
    }
}

/// Meshes kept for reuse, bounded by bytes (not count), least-recently-used first out, emptied under memory
/// pressure. Replaces v1's fixed 4000-entry purge.
final class MeshCache {
    private var entries: [MeshKey: (mesh: GPUMesh, lastUse: UInt64)] = [:]
    private var clock: UInt64 = 0
    private(set) var bytes = 0
    var budget: Int

    init(budget: Int = 384 * 1024 * 1024) {
        self.budget = budget
    }

    var count: Int { entries.count }

    func mesh(_ key: MeshKey, make: () -> GPUMesh?) -> GPUMesh? {
        clock &+= 1
        if let entry = entries[key] {
            entries[key] = (entry.mesh, clock)
            return entry.mesh
        }
        guard let mesh = make() else { return nil }
        entries[key] = (mesh, clock)
        bytes += mesh.byteSize
        if bytes > budget { evict(toFit: budget * 3 / 4) }
        return mesh
    }

    /// Drops the least recently used meshes until at most `limit` bytes remain.
    func evict(toFit limit: Int) {
        guard bytes > limit else { return }
        for (key, entry) in entries.sorted(by: { $0.value.lastUse < $1.value.lastUse }) {
            entries[key] = nil
            bytes -= entry.mesh.byteSize
            if bytes <= limit { break }
        }
    }

    /// Memory pressure: keep only what the last frames used.
    func trim() {
        let recent = clock > 600 ? clock - 600 : 0
        for (key, entry) in entries where entry.lastUse < recent {
            entries[key] = nil
            bytes -= entry.mesh.byteSize
        }
    }

    func removeAll() {
        entries.removeAll()
        bytes = 0
    }
}
