import Foundation
import LoweyCore

/// The 3D formats Maquette writes.
public enum ModelExportFormat: String, CaseIterable, Sendable, Identifiable, Codable {
    case glb, usdz, obj, stl
    case threeMF = "3mf"
    case blender

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .glb: "glTF (.glb)"
        case .usdz: "USDZ"
        case .obj: "OBJ"
        case .stl: "STL"
        case .threeMF: "3MF"
        case .blender: "Blender"
        }
    }

    /// One line on what it's for.
    public var purpose: String {
        switch self {
        case .glb: "For Blender, game engines and other 3D apps: objects, materials, cameras, lights and animation."
        case .usdz: "For Apple's Quick Look and Reality Composer: opens on any iPhone or iPad."
        case .obj: "The oldest format every 3D app opens: shapes and colours."
        case .stl: "For 3D printing: every slicer reads it. Millimetres, standing on the bed."
        case .threeMF: "For 3D printing: millimetres, a colour per part, closed shapes slicers trust."
        case .blender: "Render on your computer: a folder Blender turns into the scene with its Look, lights and cameras."
        }
    }

    public var isForPrinting: Bool { self == .stl || self == .threeMF }
}

/// 3D export of the selection or the scene. Blockout and drawn objects come from LoweyCore (exact recipes);
/// library models use their loaded parts (geometry and colours, textures not carried over).
@MainActor
public enum ModelExport {
    /// The meshes as placed in the world (USDZ, OBJ, STL, 3MF).
    public static func meshes(_ ids: [ObjectID]?, scene: CoreScene, look: Look, catalog: AssetCatalog,
                              models: ModelLibrary = .shared) -> [ExportMesh] {
        SceneExport.meshes(ids, in: scene, look: look) { object, world in
            localParts(object, look: look, catalog: catalog, models: models).map { part in
                ExportMesh(name: object.name, transform: world, mesh: part.mesh, color: part.material.color, emissive: part.material.emissive,
                           emissiveStrength: part.material.emissiveStrength, roughness: part.material.roughness, metallic: part.material.metallic)
            }
        }
    }

    /// A library model's or a prefab's pieces in the object's own space (the glTF scene keeps them under their node).
    public static func localParts(_ object: SceneObject, look: Look, catalog: AssetCatalog, models: ModelLibrary = .shared) -> [GLTFScene.LocalPart] {
        if let prefabID = object.kind.prefabID, let prefab = catalog.manifest.prefab(prefabID) {
            // A prefab instance: its fragment as a little scene, baked into the instance's space.
            let fragment = CoreScene(id: SceneID(raw: "prefab"), name: prefab.name,
                                     objects: Dictionary(uniqueKeysWithValues: prefab.fragment.objects.map { ($0.id, $0) }),
                                     roots: prefab.fragment.roots)
            return meshes(nil, scene: fragment, look: look, catalog: catalog, models: models).map { part in
                GLTFScene.LocalPart(name: part.name, mesh: part.mesh.transformed(part.transform),
                                    material: ExportMaterial(color: part.color, emissive: part.emissive, emissiveStrength: part.emissiveStrength,
                                                             roughness: part.roughness, metallic: part.metallic))
            }
        }
        guard let assetID = object.kind.assetID, let asset = catalog.manifest.asset(assetID),
              let model = models.model(asset, catalog: catalog) else { return [] }
        let tint = object.color?.resolved(in: look.palette)
        return model.parts.map { part in
            var mesh = part.mesh
            mesh.computeSmoothNormals()
            let material = model.materials.indices.contains(part.material) ? model.materials[part.material] : ImportedMaterial()
            return GLTFScene.LocalPart(name: part.name, mesh: mesh,
                                       material: ExportMaterial(color: tint ?? material.baseColor, emissive: nil, emissiveStrength: 0,
                                                                roughness: material.roughness, metallic: material.metallic))
        }
    }

    /// The files of one export, named after `name`: one file, or an OBJ with its materials.
    public static func files(_ format: ModelExportFormat, ids: [ObjectID]?, scene: CoreScene, look: Look, preset: LookPreset,
                             catalog: AssetCatalog, models: ModelLibrary = .shared, name: String) -> [(name: String, data: Data)] {
        let parts: (SceneObject) -> [GLTFScene.LocalPart] = { localParts($0, look: look, catalog: catalog, models: models) }
        switch format {
        case .glb:
            return [("\(name).glb", GLTFScene.glb(ids, in: scene, look: look, parts: parts))]
        case .blender:
            let selected = ids.map { scene.restricted(to: $0) } ?? scene
            return [("\(name) for Blender.zip", BlenderPackage.archive(selected, look: look, preset: preset, parts: parts))]
        default:
            break
        }
        let meshes = meshes(ids, scene: scene, look: look, catalog: catalog, models: models)
        guard !meshes.isEmpty else { return [] }
        switch format {
        case .usdz: return [("\(name).usdz", SceneExport.usdz(meshes))]
        case .stl: return [("\(name).stl", STLFile.binary(meshes, name: name))]
        case .threeMF: return [("\(name).3mf", ThreeMFFile.data(meshes))]
        case .obj:
            let (obj, mtl) = OBJFile.text(meshes, materialFile: "\(name).mtl")
            return [("\(name).obj", Data(obj.utf8)), ("\(name).mtl", Data(mtl.utf8))]
        case .glb, .blender: return []
        }
    }
}

extension CoreScene {
    /// The scene with only these objects (and what's under them) at the top, placed where they are in the world.
    func restricted(to ids: [ObjectID]) -> CoreScene {
        var copy = self
        var keep = Set<ObjectID>()
        for id in ids {
            keep.formUnion(subtree(of: id))
        }
        copy.objects = objects.filter { keep.contains($0.key) || $0.value.kind == .camera }
        let tops = ids.filter { id in objects[id]?.parent.map { !keep.contains($0) } ?? true }
        for id in tops {
            copy.objects[id]?.parent = nil
            copy.objects[id]?.transform = worldTransform(of: id)
        }
        let cameras = copy.objects.values.filter { $0.kind == .camera && !keep.contains($0.id) }.map(\.id)
        for id in cameras {
            copy.objects[id]?.parent = nil
            copy.objects[id]?.transform = worldTransform(of: id)
            copy.objects[id]?.children = []
        }
        copy.roots = tops + cameras.sorted { $0.raw < $1.raw }
        return copy
    }
}
