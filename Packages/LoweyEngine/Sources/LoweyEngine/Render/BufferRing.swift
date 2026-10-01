import Dispatch
import Metal
import simd

/// The frame's GPU data, filled once and shared by both shots of a transition.
struct FrameBuffers {
    let objects: MTLBuffer
    let joints: MTLBuffer
    let lineWeights: MTLBuffer
    let looks: [LookUniforms]
    let lights: [LightData]
}

/// Triple-buffered per-frame buffers: the CPU fills one slot while the GPU reads the others, and never waits on
/// the GPU mid-frame (it waits only when all three are in flight).
final class BufferRing {
    final class Slot {
        let device: MTLDevice
        var objects: MTLBuffer?
        var joints: MTLBuffer?
        var lineWeights: MTLBuffer?

        init(device: MTLDevice) {
            self.device = device
        }

        private func buffer(_ existing: inout MTLBuffer?, bytes: Int, label: String) throws -> MTLBuffer {
            let needed = max(bytes, 256)
            if let existing, existing.length >= needed { return existing }
            // Grow by half again, so a growing scene doesn't reallocate every frame.
            guard let made = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared) else { throw RenderError.texture }
            made.label = label
            existing = made
            return made
        }

        func fill(scene: RenderScene, ordered: [DrawItem]) throws -> FrameBuffers {
            let objectStride = MemoryLayout<ObjectUniforms>.stride
            let objectBuffer = try buffer(&objects, bytes: ordered.count * objectStride, label: "objects")
            let objectPointer = objectBuffer.contents().bindMemory(to: ObjectUniforms.self, capacity: ordered.count)
            for (index, item) in ordered.enumerated() {
                objectPointer[index] = item.uniforms
            }
            let jointBuffer = try buffer(&joints, bytes: scene.joints.count * MemoryLayout<simd_float4x4>.stride, label: "joints")
            if !scene.joints.isEmpty {
                let pointer = jointBuffer.contents().bindMemory(to: simd_float4x4.self, capacity: scene.joints.count)
                for (index, matrix) in scene.joints.enumerated() {
                    pointer[index] = matrix
                }
            }
            let weightBuffer = try buffer(&lineWeights, bytes: scene.lineWeights.count * 4, label: "line weights")
            let weights = weightBuffer.contents().bindMemory(to: Float.self, capacity: scene.lineWeights.count)
            for (index, weight) in scene.lineWeights.enumerated() {
                weights[index] = weight
            }
            let looks = scene.looks.isEmpty ? [LookResolver.uniforms(.ink)] : scene.looks
            return FrameBuffers(objects: objectBuffer, joints: jointBuffer, lineWeights: weightBuffer, looks: looks,
                                lights: scene.lights.isEmpty ? [LightData()] : scene.lights)
        }
    }

    private let slots: [Slot]
    private var index = 0
    private let semaphore = DispatchSemaphore(value: 3)

    init(device: MTLDevice) {
        slots = (0 ..< 3).map { _ in Slot(device: device) }
    }

    /// The next free slot; released when `commandBuffer` completes.
    func next(for commandBuffer: MTLCommandBuffer) -> Slot {
        semaphore.wait()
        let semaphore = semaphore
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }
        index = (index + 1) % slots.count
        return slots[index]
    }
}
