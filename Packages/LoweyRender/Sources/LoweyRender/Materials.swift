import Foundation
import LoweyCore
import Metal
import os
import RealityKit
import UIKit

/// Fog settings baked into every lit material (so the live view and offscreen renders match).
public struct FogUniform: Hashable, Sendable {
    public var color: RGBA
    /// 1 / distance; 0 disables fog.
    public var density: Double

    public init(fog: Fog) {
        color = fog.color
        density = fog.enabled && fog.distance > 0 ? min(1 / fog.distance, 0.999) : 0
    }

    public static let none = FogUniform(fog: Fog(enabled: false))
}

/// Everything that decides how a Lowey surface looks.
public struct SurfaceKey: Hashable, Sendable {
    public var color: RGBA
    public var emissive: RGBA?
    public var emissiveIntensity: Double
    public var roughness: Double
    public var metallic: Double
    public var fog: FogUniform

    public init(color: RGBA, emissive: RGBA? = nil, emissiveIntensity: Double = 0, roughness: Double = 0.85,
                metallic: Double = 0, fog: FogUniform = .none) {
        self.color = color
        self.emissive = emissive
        self.emissiveIntensity = emissiveIntensity
        self.roughness = roughness
        self.metallic = metallic
        self.fog = fog
    }
}

/// Creates and caches materials. Identical surfaces share one material instance so
/// RealityKit can batch/instance their draws.
///
/// Surfaces use `CustomMaterial` with the `loweySurface` shader (Shaders/LoweyShaders.metal):
/// it adds per-pixel distance fog and HDR glow. If the shader library is missing, everything
/// falls back to `PhysicallyBasedMaterial` (no fog) — the app keeps working.
@MainActor
public final class MaterialFactory {
    public static let shared = MaterialFactory()

    private let logger = Logger(subsystem: "com.hesham.lowey", category: "materials")
    private var cache: [SurfaceKey: any RealityKit.Material] = [:]
    private var convertedCache: [String: any RealityKit.Material] = [:]
    private lazy var surfaceShader: CustomMaterial.SurfaceShader? = Self.loadShader(logger: logger)

    /// True when the fog shader loaded (shown in diagnostics).
    public var customShaderAvailable: Bool { surfaceShader != nil }

    /// The package's compiled Metal library (surface shaders + post-processing kernels).
    public private(set) lazy var shaderLibrary: MTLLibrary? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let candidates = [try? device.makeDefaultLibrary(bundle: Bundle.module), device.makeDefaultLibrary()]
        return candidates.compactMap { $0 }.first { $0.functionNames.contains("loweySurface") }
    }()

    private var depthCache: (any RealityKit.Material)?
    /// True when the depth shader compiled (false = depth effects fall back to a flat, far depth).
    public private(set) var depthShaderAvailable = false

    /// Unlit material writing v = 0.5 / distance (the depth world for lens blur and outlines).
    public var depthMaterial: any RealityKit.Material {
        if let depthCache { return depthCache }
        var material: any RealityKit.Material = UnlitMaterial(color: .black)
        if let library = shaderLibrary {
            let shader = CustomMaterial.SurfaceShader(named: "loweyDepth", in: library)
            do {
                material = try CustomMaterial(surfaceShader: shader, geometryModifier: nil, lightingModel: .unlit)
                depthShaderAvailable = true
            } catch {
                logger.error("Depth material failed: \(error.localizedDescription)")
            }
        }
        depthCache = material
        return material
    }

    private static func loadShader(logger: Logger) -> CustomMaterial.SurfaceShader? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        // The package's own metallib first, then the app's (if a host app ships the shader).
        let candidates = [try? device.makeDefaultLibrary(bundle: Bundle.module), device.makeDefaultLibrary()]
        guard let library = candidates.compactMap({ $0 }).first(where: { $0.functionNames.contains("loweySurface") }) else {
            logger.error("loweySurface shader not found — fog disabled")
            return nil
        }
        return CustomMaterial.SurfaceShader(named: "loweySurface", in: library)
    }

    /// Packs fog density + glow into the shader's single custom float4:
    /// rgb = fog color, w = round(glow × 100) + density (density < 1).
    static func customValue(fog: FogUniform, emissiveIntensity: Double) -> SIMD4<Float> {
        let glow = (min(max(emissiveIntensity, 0), 100) * 100).rounded()
        return SIMD4<Float>(Float(fog.color.r), Float(fog.color.g), Float(fog.color.b), Float(glow + fog.density))
    }

    public func material(for key: SurfaceKey) -> any RealityKit.Material {
        if let cached = cache[key] { return cached }
        // Animated colours and glow create many surfaces; entities keep the ones they use.
        if cache.count > 4000 { cache.removeAll() }
        let material = makeMaterial(for: key)
        cache[key] = material
        return material
    }

    private func makeMaterial(for key: SurfaceKey) -> any RealityKit.Material {
        var pbr = PhysicallyBasedMaterial()
        pbr.baseColor = .init(tint: key.color.uiColor)
        pbr.roughness = .init(floatLiteral: Float(key.roughness))
        pbr.metallic = .init(floatLiteral: Float(key.metallic))
        if let emissive = key.emissive, key.emissiveIntensity > 0 {
            pbr.emissiveColor = .init(color: emissive.uiColor)
            pbr.emissiveIntensity = Float(key.emissiveIntensity)
        }
        guard let shader = surfaceShader else { return pbr }
        do {
            var custom = try CustomMaterial(from: pbr, surfaceShader: shader, geometryModifier: nil)
            custom.custom.value = Self.customValue(fog: key.fog, emissiveIntensity: key.emissive != nil ? key.emissiveIntensity : 0)
            if let emissive = key.emissive, key.emissiveIntensity > 0 {
                custom.emissiveColor = .init(color: emissive.uiColor)
            }
            return custom
        } catch {
            logger.error("CustomMaterial failed: \(error.localizedDescription) — using PBR")
            return pbr
        }
    }

    /// Converts an imported asset's material so it receives fog, keeping its textures.
    /// `identity` must uniquely identify the source material (asset id + slot path).
    public func converted(_ material: any RealityKit.Material, identity: String, fog: FogUniform) -> any RealityKit.Material {
        guard let shader = surfaceShader, !(material is UnlitMaterial) else { return material }
        let key = "\(identity)|\(fog.color.hex)|\(fog.density)"
        if let cached = convertedCache[key] { return cached }
        do {
            var custom = try CustomMaterial(from: material, surfaceShader: shader, geometryModifier: nil)
            custom.custom.value = Self.customValue(fog: fog, emissiveIntensity: 1)
            convertedCache[key] = custom
            return custom
        } catch {
            convertedCache[key] = material
            return material
        }
    }

    /// Unlit, possibly translucent material for helpers (grid, gizmos, selection box).
    public func helper(color: UIColor, opacity: Float = 1) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    /// Drops cached materials (after a look change the fog uniform changes anyway).
    public func purge() {
        cache.removeAll()
        convertedCache.removeAll()
    }
}
