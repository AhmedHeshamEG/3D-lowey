import CoreGraphics
import Foundation
import LoweyCore
import os
import RealityKit
import UIKit

/// Sky dome, stars, ground, sun and ambient light built from a `Look`.
@MainActor
public final class EnvironmentRig {
    public let root = Entity()
    private let sky = ModelEntity()
    private let ground = ModelEntity()
    private let sun = DirectionalLight()
    private var lastLook: Look?
    private var environmentTask: Task<Void, Never>?
    private var skyTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "environment")

    /// Image-based light generated from the sky (applied by the owner to ARView / RealityRenderer).
    public private(set) var environment: EnvironmentResource?
    public private(set) var ambientExponent: Float = 0
    /// Called when a new environment resource is ready.
    public var onEnvironmentChanged: ((EnvironmentResource?, Float) -> Void)?

    public static let skyRadius: Float = 400

    public init() {
        root.name = "Environment"
        sky.name = "Sky"
        ground.name = "Ground"
        sun.name = "Sun"
        root.addChild(sky)
        root.addChild(ground)
        root.addChild(sun)
        if let dome = try? MeshUpload.resource(from: Self.skyDome(), name: "sky") {
            sky.model = ModelComponent(mesh: dome, materials: [UnlitMaterial(color: .gray)])
        }
        if let disc = try? MeshUpload.resource(from: Self.groundDisc(), name: "ground") {
            ground.model = ModelComponent(mesh: disc, materials: [SimpleMaterial(color: .gray, isMetallic: false)])
        }
        ground.position = SIMD3<Float>(0, -0.002, 0)
    }

    /// Applies a look. Cheap if nothing relevant changed.
    public func apply(_ look: Look) {
        guard look != lastLook else { return }
        let previous = lastLook
        lastLook = look
        let fog = FogUniform(fog: look.fog)

        // Sun.
        let direction = look.lighting.sunDirection.simd
        sun.light.color = look.lighting.sunColor.uiColor
        sun.light.intensity = Float(look.lighting.sunIntensity) * 2600 * exposureFactor(look)
        sun.look(at: -direction, from: .zero, relativeTo: nil)
        if look.lighting.sunShadows, look.lighting.sunIntensity > 0.05 {
            sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 40, depthBias: 2)
        } else {
            sun.shadow = nil
        }

        // Ground.
        ground.isEnabled = look.ground.visible && !backdropHidden
        let groundScale = Float(max(look.ground.size, 1))
        ground.scale = SIMD3<Float>(groundScale, 1, groundScale)
        let groundKey = SurfaceKey(color: look.ground.color, roughness: 0.95, fog: fog)
        ground.model?.materials = [MaterialFactory.shared.material(for: groundKey)]

        // Sky (+ ambient light from the same gradient) only when sky/fog changed.
        if previous?.sky != look.sky || previous?.fog != look.fog || previous?.lighting.ambientIntensity != look.lighting.ambientIntensity
            || previous?.lighting.exposure != look.lighting.exposure {
            // Flat colour immediately (no flash of the old sky), then the full gradient.
            sky.model?.materials = [UnlitMaterial(color: look.sky.horizon.uiColor)]
            skyTask?.cancel()
            if let image = Self.skyImage(look: look, width: 1024, height: 512, stars: true) {
                skyTask = Task { @MainActor [weak self] in
                    guard let texture = try? await TextureResource(
                        image: image, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
                    ), let self, !Task.isCancelled else { return }
                    var material = UnlitMaterial()
                    material.color = .init(tint: .white, texture: .init(texture))
                    sky.model?.materials = [material]
                }
            }
            ambientExponent = Float(log2(max(look.lighting.ambientIntensity, 0.02))) + Float(look.lighting.exposure)
            rebuildEnvironment(for: look)
        }
    }

    private func exposureFactor(_ look: Look) -> Float {
        Float(pow(2, look.lighting.exposure))
    }

    private func rebuildEnvironment(for look: Look) {
        environmentTask?.cancel()
        guard let image = Self.skyImage(look: look, width: 256, height: 128, stars: false, forLighting: true) else { return }
        let exponent = ambientExponent
        environmentTask = Task { @MainActor [weak self] in
            do {
                let resource = try await EnvironmentResource(equirectangular: image, withName: "lowey-sky")
                guard let self, !Task.isCancelled else { return }
                environment = resource
                onEnvironmentChanged?(resource, exponent)
            } catch {
                self?.logger.error("Environment generation failed: \(error.localizedDescription)")
            }
        }
    }

    /// Keeps the sky dome centred on the camera so it's always "infinitely" far away.
    public func follow(camera position: Vec3) {
        sky.position = position.simd
        let needed = Float((position.length + 50) / Double(Self.skyRadius))
        sky.scale = SIMD3<Float>(repeating: max(1, needed))
    }

    /// Hides the sky dome and ground (transparent-background exports keep only the objects).
    public var backdropHidden = false {
        didSet {
            sky.isEnabled = !backdropHidden
            ground.isEnabled = !backdropHidden && (lastLook?.ground.visible ?? true)
        }
    }

    /// Waits until the image-based light for the current look exists (for offscreen renders).
    public func waitForEnvironment() async {
        await skyTask?.value
        await environmentTask?.value
    }

    // MARK: Geometry

    /// Inward-facing UV sphere for the sky.
    static func skyDome() -> MeshData {
        var mesh = MeshData()
        let segments = 48
        let rings = 24
        let radius = skyRadius
        for ring in 0 ... rings {
            let v = Float(ring) / Float(rings)
            let phi = v * Float.pi
            for segment in 0 ... segments {
                let u = Float(segment) / Float(segments)
                let theta = u * 2 * Float.pi
                let direction = SIMD3<Float>(sin(phi) * sin(theta), cos(phi), sin(phi) * cos(theta))
                // RealityKit samples textures with v flipped relative to image rows.
                mesh.addVertex(direction * radius, normal: -direction, uv: SIMD2<Float>(u, 1 - v))
            }
        }
        let stride = UInt32(segments + 1)
        for ring in 0 ..< UInt32(rings) {
            for segment in 0 ..< UInt32(segments) {
                let a = ring * stride + segment
                let b = a + stride
                // Reversed winding: visible from inside.
                mesh.addTriangle(a, a + 1, b)
                mesh.addTriangle(a + 1, b + 1, b)
            }
        }
        return mesh
    }

    /// Unit-radius flat disc (scaled by the ground size).
    static func groundDisc() -> MeshData {
        var mesh = MeshData()
        let segments = 64
        let up = SIMD3<Float>(0, 1, 0)
        let center = mesh.addVertex(.zero, normal: up, uv: SIMD2<Float>(0.5, 0.5))
        for segment in 0 ... segments {
            let angle = Float(segment) / Float(segments) * 2 * Float.pi
            mesh.addVertex(SIMD3<Float>(sin(angle), 0, cos(angle)), normal: up,
                           uv: SIMD2<Float>(0.5 + sin(angle) / 2, 0.5 + cos(angle) / 2))
        }
        for segment in 0 ..< UInt32(segments) {
            mesh.addTriangle(center, segment + 1, segment + 2)
        }
        return mesh
    }

    // MARK: Sky image

    /// Equirectangular sky: top → horizon → bottom gradient, fog-tinted horizon, optional stars.
    public static func skyImage(look: Look, width: Int, height: Int, stars: Bool, forLighting: Bool = false) -> CGImage? {
        var sky = look.sky
        if forLighting {
            // Ambient light from a near-black night sky is nothing at all; lift it toward a neutral
            // moonlit grey so dark moods stay readable (the visible sky is unchanged).
            let lift = RGBA(0.5, 0.53, 0.62)
            sky.top = sky.top.lerp(to: lift, 0.3)
            sky.horizon = sky.horizon.lerp(to: lift, 0.3)
            sky.bottom = sky.bottom.lerp(to: lift, 0.2)
        }
        var horizon = sky.horizon
        var bottom = sky.bottom
        if look.fog.enabled {
            horizon = horizon.lerp(to: look.fog.color, 0.6)
            bottom = bottom.lerp(to: look.fog.color, 0.8)
        }
        let exposure = pow(2, look.lighting.exposure)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0 ..< height {
            // Row 0 = straight up.
            let elevation = 1 - 2 * (Double(row) + 0.5) / Double(height) // +1 up … -1 down
            let color: RGBA
            if elevation >= 0 {
                let t = pow(elevation, 0.55)
                color = horizon.lerp(to: sky.top, t)
            } else {
                let t = pow(-elevation, 0.35)
                color = horizon.lerp(to: bottom, t)
            }
            let r = UInt8(min(color.r * exposure, 1) * 255)
            let g = UInt8(min(color.g * exposure, 1) * 255)
            let b = UInt8(min(color.b * exposure, 1) * 255)
            for column in 0 ..< width {
                let index = (row * width + column) * 4
                pixels[index] = r
                pixels[index + 1] = g
                pixels[index + 2] = b
                pixels[index + 3] = 255
            }
        }
        if stars, sky.stars > 0 {
            var random = SeededRandom(seed: 1941)
            let count = Int(Double(width * height) * 0.004 * sky.stars)
            for _ in 0 ..< count {
                let column = Int(random.unit() * Double(width))
                // Stars only above the horizon, denser toward the zenith.
                let row = Int(pow(random.unit(), 1.6) * Double(height) * 0.48)
                let brightness = random.range(0.45, 1.0)
                let size = random.unit() > 0.92 ? 2 : 1
                for dy in 0 ..< size {
                    for dx in 0 ..< size {
                        let x = (column + dx) % width
                        let y = min(row + dy, height - 1)
                        let index = (y * width + x) * 4
                        let value = UInt8(brightness * 255)
                        pixels[index] = max(pixels[index], value)
                        pixels[index + 1] = max(pixels[index + 1], value)
                        pixels[index + 2] = max(pixels[index + 2], UInt8(min(Double(value) * 1.05, 255)))
                    }
                }
            }
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
