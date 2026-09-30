import Foundation
import LoweyCore

public enum ModelExportFormat: String, CaseIterable, Sendable, Identifiable {
    case glb, usdz

    public var id: String { rawValue }
    public var title: String { self == .glb ? "glTF (.glb)" : "USDZ" }
}

/// 3D export of the selection or the scene. Blockout and drawn objects come from LoweyCore (exact recipes);
/// library models use their loaded parts (geometry baked into world space, colours kept, textures not carried over).
@MainActor
public enum ModelExport {
    public static func meshes(_ ids: [ObjectID]?, scene: CoreScene, look: Look, catalog: AssetCatalog,
                              models: ModelLibrary = .shared) -> [ExportMesh] {
        SceneExport.meshes(ids, in: scene, look: look) { object, world in
            if let prefabID = object.kind.prefabID, let prefab = catalog.manifest.prefab(prefabID) {
                // A prefab instance: its fragment exported as a little scene, placed where the instance is.
                let fragment = CoreScene(id: SceneID(raw: "prefab"), name: prefab.name,
                                         objects: Dictionary(uniqueKeysWithValues: prefab.fragment.objects.map { ($0.id, $0) }),
                                         roots: prefab.fragment.roots)
                return meshes(nil, scene: fragment, look: look, catalog: catalog, models: models).map { part in
                    var placed = part
                    placed.transform = world * part.transform
                    return placed
                }
            }
            guard let assetID = object.kind.assetID, let asset = catalog.manifest.asset(assetID),
                  let model = models.model(asset, catalog: catalog) else { return [] }
            let tint = object.color?.resolved(in: look.palette)
            return model.parts.map { part in
                var mesh = part.mesh.transformed(world)
                mesh.computeSmoothNormals()
                let material = model.materials.indices.contains(part.material) ? model.materials[part.material] : ImportedMaterial()
                return ExportMesh(name: object.name, transform: .identity, mesh: mesh, color: tint ?? material.baseColor)
            }
        }
    }

    public static func data(_ format: ModelExportFormat, meshes: [ExportMesh]) -> Data {
        switch format {
        case .glb: SceneExport.glb(meshes)
        case .usdz: SceneExport.usdz(meshes)
        }
    }
}
