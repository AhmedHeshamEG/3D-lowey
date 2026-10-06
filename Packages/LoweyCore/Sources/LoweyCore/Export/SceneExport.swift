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
    /// Painted colour (an opaque PNG over the mesh's uvs); `color` multiplies it, so it's white then.
    public var texture: Data?

    public init(name: String, transform: Transform, mesh: MeshData, color: RGBA, emissive: RGBA? = nil, emissiveStrength: Double = 0,
                roughness: Double = 0.85, metallic: Double = 0, texture: Data? = nil) {
        self.name = name
        self.transform = transform
        self.mesh = mesh
        self.color = color
        self.emissive = emissive
        self.emissiveStrength = emissiveStrength
        self.roughness = roughness
        self.metallic = metallic
        self.texture = texture
    }
}

/// An object's surface as an exporter sees it: base colour, glow, roughness and metal, resolved through the Look.
public struct ExportMaterial: Hashable, Sendable {
    public var color: RGBA
    public var emissive: RGBA?
    public var emissiveStrength: Double
    public var roughness: Double
    public var metallic: Double
    /// Painted colour (an opaque PNG); `color` multiplies it.
    public var texture: Data?

    public init(color: RGBA, emissive: RGBA? = nil, emissiveStrength: Double = 0, roughness: Double = 0.85, metallic: Double = 0,
                texture: Data? = nil) {
        self.color = color
        self.emissive = emissive
        self.emissiveStrength = emissiveStrength
        self.roughness = roughness
        self.metallic = metallic
        self.texture = texture
    }

    /// The material over a painted texture: white (the texture carries the colour), the rest as it was.
    public func painted(_ texture: Data) -> ExportMaterial {
        var material = self
        material.color = RGBA(1, 1, 1, color.a)
        material.texture = texture
        return material
    }
}

/// 3D export (glTF binary and USDZ) of the selection or the whole scene, written in pure Swift.
public enum SceneExport {
    /// Meshes for blockout and drawn objects. Other kinds (library models, prefab instances) come
    /// from `extra`, which the render layer fills from the loaded entities. `painted` gives a painted object's paint
    /// mesh and texture (left out for printing, which wants the closed shape).
    /// `posed` gives a rigged object's surface as its skeleton bends it (in its own space, with its materials).
    public static func meshes(
        _ ids: [ObjectID]?, in scene: Scene, look: Look, extra: (SceneObject, Transform) -> [ExportMesh] = { _, _ in [] },
        painted: (SceneObject) -> PaintedExport? = { _ in nil }, posed: (SceneObject) -> [GLTFScene.LocalPart]? = { _ in nil }
    ) -> [ExportMesh] {
        let roots = ids ?? scene.roots
        var visited = Set<ObjectID>()
        var result: [ExportMesh] = []
        for root in roots {
            for id in scene.subtree(of: root) where visited.insert(id).inserted {
                guard let object = scene.objects[id], scene.isEffectivelyVisible(id) else { continue }
                let world = scene.worldTransform(of: id)
                if let paint = painted(object) {
                    let surface = material(of: object, look: look).painted(paint.texture)
                    result.append(ExportMesh(
                        name: object.name, transform: world, mesh: paint.mesh, color: surface.color, emissive: surface.emissive,
                        emissiveStrength: surface.emissiveStrength, roughness: surface.roughness, metallic: surface.metallic, texture: paint.texture
                    ))
                } else if let pieces = posed(object) {
                    result += pieces.map { piece in
                        ExportMesh(name: object.name, transform: world, mesh: piece.mesh, color: piece.material.color, emissive: piece.material.emissive,
                                   emissiveStrength: piece.material.emissiveStrength, roughness: piece.material.roughness,
                                   metallic: piece.material.metallic)
                    }
                } else if let data = localMesh(of: object, look: look), !data.isEmpty {
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
