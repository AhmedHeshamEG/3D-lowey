import Foundation

/// One mesh to export, already in its final (world) placement.
public struct ExportMesh: Hashable, Sendable {
    public var name: String
    public var transform: Transform
    public var mesh: MeshData
    public var color: RGBA
    public var emissive: RGBA?
    public var emissiveStrength: Double
    public var roughness: Double
    public var metallic: Double

    public init(name: String, transform: Transform, mesh: MeshData, color: RGBA, emissive: RGBA? = nil, emissiveStrength: Double = 0,
                roughness: Double = 0.85, metallic: Double = 0) {
        self.name = name
        self.transform = transform
        self.mesh = mesh
        self.color = color
        self.emissive = emissive
        self.emissiveStrength = emissiveStrength
        self.roughness = roughness
        self.metallic = metallic
    }
}

/// An object's surface as an exporter sees it: base colour, glow, roughness and metal, resolved through the Look.
public struct ExportMaterial: Hashable, Sendable {
    public var color: RGBA
    public var emissive: RGBA?
    public var emissiveStrength: Double
    public var roughness: Double
    public var metallic: Double

    public init(color: RGBA, emissive: RGBA? = nil, emissiveStrength: Double = 0, roughness: Double = 0.85, metallic: Double = 0) {
        self.color = color
        self.emissive = emissive
        self.emissiveStrength = emissiveStrength
        self.roughness = roughness
        self.metallic = metallic
    }
}

/// 3D export (glTF binary and USDZ) of the selection or the whole scene, written in pure Swift.
public enum SceneExport {
    /// Meshes for blockout and drawn objects. Other kinds (library models, prefab instances) come
    /// from `extra`, which the render layer fills from the loaded entities.
    public static func meshes(
        _ ids: [ObjectID]?, in scene: Scene, look: Look, extra: (SceneObject, Transform) -> [ExportMesh] = { _, _ in [] }
    ) -> [ExportMesh] {
        let roots = ids ?? scene.roots
        var visited = Set<ObjectID>()
        var result: [ExportMesh] = []
        for root in roots {
            for id in scene.subtree(of: root) where visited.insert(id).inserted {
                guard let object = scene.objects[id], scene.isEffectivelyVisible(id) else { continue }
                let world = scene.worldTransform(of: id)
                if let data = localMesh(of: object, look: look), !data.isEmpty {
                    let surface = material(of: object, look: look)
                    result.append(ExportMesh(
                        name: object.name, transform: world, mesh: data, color: surface.color, emissive: surface.emissive,
                        emissiveStrength: surface.emissiveStrength, roughness: surface.roughness, metallic: surface.metallic
                    ))
                } else {
                    result += extra(object, world)
                }
            }
        }
        return result
    }

    /// The object's own triangles in its own space (blockout shapes, drawings, modelled meshes, block text); nil for
    /// kinds that come from elsewhere (models, prefabs) or have no surface.
    public static func localMesh(of object: SceneObject, look: Look) -> MeshData? {
        let shading: ShadingStyle = switch object.shading {
        case .inherit: look.shading
        case .smooth: .smooth
        case .flat: .flat
        }
        return switch object.kind {
        case let .primitive(shape): PrimitiveMesh.make(shape, shading: shading)
        case let .drawing(recipe): DrawingMesher.mesh(for: recipe).shaded(shading)
        case let .mesh(mesh): mesh.renderMesh()
        case let .text(recipe) where recipe.coreMeshable: BlockFont.mesh(for: recipe)
        default: nil
        }
    }

    public static func material(of object: SceneObject, look: Look) -> ExportMaterial {
        let color = object.color?.resolved(in: look.palette) ?? .blockout
        let emissive = object.emissive?.resolved(in: look.palette) ?? (object.emissiveIntensity > 0 ? color : nil)
        return ExportMaterial(color: color, emissive: emissive, emissiveStrength: object.emissiveIntensity,
                              roughness: object[.roughness]?.floatValue ?? 0.85, metallic: object[.metallic]?.floatValue ?? 0)
    }

    static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func srgb(_ c: Double) -> Double {
        let value = min(max(c, 0), 1)
        return value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}
