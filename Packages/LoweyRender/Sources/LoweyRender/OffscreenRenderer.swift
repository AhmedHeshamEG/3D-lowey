import CoreGraphics
import CoreImage
import Foundation
import LoweyCore
import Metal
import os
import RealityKit
import UIKit

/// Snapshot aspect ratios (and later, video framings).
public enum Framing: String, CaseIterable, Sendable, Identifiable {
    case landscape = "16:9"
    case portrait = "9:16"
    case square = "1:1"

    public var id: String { rawValue }

    /// Pixel size with the long side = `longSide`.
    public func pixelSize(longSide: Int) -> (width: Int, height: Int) {
        switch self {
        case .landscape: (longSide, Int((Double(longSide) * 9 / 16).rounded()))
        case .portrait: (Int((Double(longSide) * 9 / 16).rounded()), longSide)
        case .square: (longSide, longSide)
        }
    }

    /// The export frame inside a viewport (what the framing guide shows).
    public func guideRect(in size: CGSize) -> CGRect {
        let target = CGFloat(aspect)
        var width = size.width * 0.86
        var height = width / target
        if height > size.height * 0.8 {
            height = size.height * 0.8
            width = height * target
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    public var aspect: Double {
        switch self {
        case .landscape: 16.0 / 9.0
        case .portrait: 9.0 / 16.0
        case .square: 1
        }
    }
}

public enum OffscreenError: Error, CustomStringConvertible {
    case noMetal
    case textureCreation
    case readback

    public var description: String {
        switch self {
        case .noMetal: "Metal is not available"
        case .textureCreation: "Couldn't create the render target"
        case .readback: "Couldn't read the rendered image"
        }
    }
}

/// Renders a world to an image at any size, at any time, without the on-screen view.
///
/// Built on `RealityRenderer` (iPadOS 18+): the same path Phase 2 uses to export video
/// frame by frame at a fixed timestep. See DECISIONS.md ("Offscreen rendering spike").
@MainActor
public final class OffscreenRenderer {
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "offscreen")
    private let device: MTLDevice?
    private lazy var ciContext = CIContext()

    public init() {
        device = MTLCreateSystemDefaultDevice()
    }

    public struct Camera: Sendable {
        public var position: SIMD3<Float>
        public var orientation: simd_quatf
        /// Vertical field of view in degrees for the *reference* aspect.
        public var fieldOfView: Float

        public init(position: SIMD3<Float>, orientation: simd_quatf, fieldOfView: Float) {
            self.position = position
            self.orientation = orientation
            self.fieldOfView = fieldOfView
        }

        /// The editor camera for a viewpoint.
        @MainActor
        public init(viewpoint: Viewpoint) {
            let pose = StageView.cameraPose(for: viewpoint)
            self.init(position: pose.eye.simd, orientation: pose.rotation.simd, fieldOfView: Float(pose.fieldOfView))
        }
    }

    /// Renders `world` (a detached clone — it's consumed) to a CGImage.
    public func render(
        world: Entity, camera: Camera, width: Int, height: Int,
        environment: EnvironmentResource?, environmentExponent: Float, background: UIColor,
        warmupFrames: Int = 3
    ) async throws -> CGImage {
        guard let device else { throw OffscreenError.noMetal }
        let renderer = try RealityRenderer()
        renderer.entities.append(world)
        let cameraEntity = Entity()
        cameraEntity.components.set(PerspectiveCameraComponent(near: 0.02, far: 60000, fieldOfViewInDegrees: camera.fieldOfView))
        cameraEntity.position = camera.position
        cameraEntity.orientation = camera.orientation
        renderer.entities.append(cameraEntity)
        renderer.activeCamera = cameraEntity
        if let environment {
            renderer.lighting.resource = environment
            renderer.lighting.intensityExponent = environmentExponent
        }
        renderer.cameraSettings.colorBackground = .color(background.cgColor)
        renderer.cameraSettings.antialiasing = .multisample4X

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw OffscreenError.textureCreation }
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))

        // A few frames so async resources (textures, IBL) settle.
        for _ in 0 ..< max(warmupFrames, 1) {
            try await renderFrame(renderer, output: output)
        }
        return try image(from: texture, width: width, height: height)
    }

    private func renderFrame(_ renderer: RealityRenderer, output: RealityRenderer.CameraOutput) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try renderer.updateAndRender(
                    deltaTime: 1.0 / 30.0,
                    cameraOutput: output,
                    whenScheduled: nil,
                    onComplete: { _ in continuation.resume() },
                    actionsBeforeRender: [],
                    actionsAfterRender: []
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func image(from texture: MTLTexture, width: Int, height: Int) throws -> CGImage {
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { throw OffscreenError.readback }
        return image
    }

    // MARK: Conveniences

    /// Renders what the stage shows (without helpers) at a framing. With a `viewportSize`, the
    /// image covers exactly the framing guide drawn over the stage (what you see is what you get).
    public func snapshot(
        of renderer: SceneRenderer, viewpoint: Viewpoint, framing: Framing, longSide: Int, viewportSize: CGSize? = nil
    ) async throws -> CGImage {
        await renderer.environment.waitForEnvironment()
        let size = framing.pixelSize(longSide: longSide)
        var camera = Camera(viewpoint: viewpoint)
        if let viewportSize, viewportSize.height > 0 {
            let guide = framing.guideRect(in: viewportSize)
            let fraction = Double(guide.height / viewportSize.height)
            let half = atan(tan(Double(camera.fieldOfView) * .pi / 360) * fraction)
            camera.fieldOfView = Float(half * 360 / .pi)
        }
        let look = renderer.currentDocument?.effectiveLook ?? .default
        return try await render(
            world: renderer.renderableClone(), camera: camera, width: size.width, height: size.height,
            environment: renderer.environment.environment, environmentExponent: renderer.environment.ambientExponent,
            background: look.sky.horizon.uiColor
        )
    }

    /// Renders a single entity (library thumbnail) in a neutral studio, framed from a 3/4 view.
    public func thumbnail(of entity: Entity, size: Int = 384, environment: EnvironmentResource?) async throws -> CGImage {
        let holder = Entity()
        let model = entity.clone(recursive: true)
        SceneRenderer.stripHelpers(model)
        holder.addChild(model)
        let bounds = model.visualBounds(recursive: true, relativeTo: holder)
        let center = bounds.isEmpty ? SIMD3<Float>(0, 0.5, 0) : bounds.center
        let radius = bounds.isEmpty ? 0.8 : max(simd_length(bounds.extents) / 2, 0.05)
        let key = DirectionalLight()
        key.light.intensity = 3200
        key.light.color = .white
        key.look(at: .zero, from: SIMD3<Float>(2, 4, 3), relativeTo: nil)
        holder.addChild(key)
        let fov: Float = 30
        let distance = radius / sin(fov * .pi / 360) * 1.05
        let direction = simd_normalize(SIMD3<Float>(0.8, 0.55, 1.0))
        let position = center + direction * distance
        // Level horizon (no roll).
        let levelled = Self.levelledOrientation(looking: simd_normalize(center - position))
        return try await render(
            world: holder, camera: Camera(position: position, orientation: levelled, fieldOfView: fov),
            width: size, height: size, environment: environment, environmentExponent: 0,
            background: UIColor(red: 0.16, green: 0.17, blue: 0.2, alpha: 1)
        )
    }

    static func levelledOrientation(looking forward: SIMD3<Float>) -> simd_quatf {
        let yaw = atan2(-forward.x, -forward.z)
        let pitch = asin(max(-1, min(1, forward.y)))
        return simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
    }

    public static func pngData(_ image: CGImage) -> Data? {
        UIImage(cgImage: image).pngData()
    }
}
