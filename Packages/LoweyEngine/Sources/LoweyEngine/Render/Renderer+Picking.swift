import CoreGraphics
import LoweyCore
import Metal
import simd

/// What's under a point: the scene object, where on its surface, and which way the surface faces.
public struct PickHit: Sendable, Equatable {
    public var object: ObjectID
    public var point: Vec3
    public var normal: Vec3
    public var distance: Double
}

public extension LoweyRenderer {
    /// Reads the last frame's ID and depth buffers around a pixel (a small window, so a finger finds thin things) and
    /// returns the object nearest the centre. Exact: the ID buffer is what was drawn, pixel for pixel.
    func pick(at pixel: SIMD2<Int>, radius: Int = 6) -> PickHit? {
        guard let targets, let scene = lastScene, let camera = lastCamera else { return nil }
        let x0 = min(max(pixel.x - radius, 0), targets.width - 1)
        let y0 = min(max(pixel.y - radius, 0), targets.height - 1)
        let x1 = min(max(pixel.x + radius, 0), targets.width - 1)
        let y1 = min(max(pixel.y + radius, 0), targets.height - 1)
        let width = x1 - x0 + 1
        let height = y1 - y0 + 1
        guard let ids = device.device.makeBuffer(length: width * height * 4, options: .storageModeShared),
              let depths = device.device.makeBuffer(length: width * height * 8, options: .storageModeShared),
              let commandBuffer = device.queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        let origin = MTLOrigin(x: x0, y: y0, z: 0)
        let size = MTLSize(width: width, height: height, depth: 1)
        blit.copy(from: targets.ids, sourceSlice: 0, sourceLevel: 0, sourceOrigin: origin, sourceSize: size, to: ids,
                  destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
        blit.copy(from: targets.normalDepth, sourceSlice: 0, sourceLevel: 0, sourceOrigin: origin, sourceSize: size, to: depths,
                  destinationOffset: 0, destinationBytesPerRow: width * 8, destinationBytesPerImage: width * height * 8)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let packed = ids.contents().bindMemory(to: UInt32.self, capacity: width * height)
        let normals = depths.contents().bindMemory(to: Float16.self, capacity: width * height * 4)
        var best: (index: Int, distance: Int)?
        for row in 0 ..< height {
            for column in 0 ..< width {
                let index = row * width + column
                guard PackedID.object(packed[index]) != 0 else { continue }
                let dx = x0 + column - pixel.x
                let dy = y0 + row - pixel.y
                let distance = dx * dx + dy * dy
                if best == nil || distance < best?.distance ?? .max { best = (index, distance) }
            }
        }
        guard let best, let object = scene.objectID(forPacked: packed[best.index]) else { return nil }
        let hitPixel = CGPoint(x: CGFloat(x0 + best.index % width) + 0.5, y: CGFloat(y0 + best.index / width) + 0.5)
        let ray = camera.ray(through: hitPixel, in: CGSize(width: targets.width, height: targets.height))
        let viewDepth = Double(Float(normals[best.index * 4 + 3]))
        let along = max(ray.direction.dot(Vec3(camera.forward)), 1e-4)
        let distance = viewDepth / along
        let viewNormal = SIMD3<Float>(Float(normals[best.index * 4]), Float(normals[best.index * 4 + 1]), Float(normals[best.index * 4 + 2]))
        let worldNormal = camera.orientation.act(simd_length(viewNormal) > 0.01 ? simd_normalize(viewNormal) : SIMD3<Float>(0, 1, 0))
        return PickHit(object: object, point: ray.point(at: distance), normal: Vec3(worldNormal).normalized, distance: distance)
    }

    /// The whole ID buffer of the last frame (packed ids, top row first) and its size.
    func idBuffer() -> (ids: [UInt32], width: Int, height: Int)? {
        guard let targets, let buffer = device.device.makeBuffer(length: targets.width * targets.height * 4, options: .storageModeShared),
              let commandBuffer = device.queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        let size = MTLSize(width: targets.width, height: targets.height, depth: 1)
        blit.copy(from: targets.ids, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: size, to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: targets.width * 4, destinationBytesPerImage: targets.width * targets.height * 4)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let pointer = buffer.contents().bindMemory(to: UInt32.self, capacity: targets.width * targets.height)
        return (Array(UnsafeBufferPointer(start: pointer, count: targets.width * targets.height)), targets.width, targets.height)
    }

    /// The object indices whose pixels fall inside a screen polygon (lasso) in the last frame, by bounds centre.
    func visibleObjects() -> [ObjectID] {
        lastScene?.objectIDs ?? []
    }

    /// World bounds of objects as last drawn (what you see, loaded models included).
    func visualBounds(of ids: Set<ObjectID>) -> Bounds? {
        guard let scene = lastScene else { return nil }
        var result: Bounds?
        for item in scene.items {
            guard let object = scene.objectID(forPacked: item.uniforms.ids.x), ids.contains(object) else { continue }
            result = result.map { $0.union(item.worldBounds) } ?? item.worldBounds
        }
        return result
    }

    /// An object's geometry in world space as last drawn (drawing on its surface). Skinned parts are posed on the GPU,
    /// so with `staticOnly` an object that has any comes back nil (the caller uses its catalogued box instead).
    func worldMesh(of id: ObjectID, staticOnly: Bool = false) -> MeshData? {
        guard let scene = lastScene else { return nil }
        if staticOnly, scene.items.contains(where: {
            scene.objectID(forPacked: $0.uniforms.ids.x) == id && ($0.uniforms.ids.z & ObjectFlags.skinned.rawValue) != 0
        }) { return nil }
        var result = MeshData()
        for item in scene.items where scene.objectID(forPacked: item.uniforms.ids.x) == id {
            var mesh = item.mesh.data
            let matrix = item.uniforms.model
            mesh.positions = mesh.positions.map { position in
                let world = matrix * SIMD4<Float>(position, 1)
                return SIMD3<Float>(world.x, world.y, world.z)
            }
            let normalMatrix = item.uniforms.normalMatrix
            mesh.normals = mesh.normals.map { normal in
                let world = normalMatrix * SIMD4<Float>(normal, 0)
                return simd_normalize(SIMD3<Float>(world.x, world.y, world.z))
            }
            result.append(mesh)
        }
        return result.isEmpty ? nil : result
    }

    /// Helpers (lights, cameras, emitters) as last drawn.
    var helpers: [HelperItem] { lastScene?.helpers ?? [] }
}
