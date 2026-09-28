import Foundation
import LoweyCore
import RealityKit

public enum ModelExportFormat: String, CaseIterable, Sendable, Identifiable {
    case glb, usdz

    public var id: String { rawValue }
    public var title: String { self == .glb ? "glTF (.glb)" : "USDZ" }
}

/// 3D export of the selection or the scene. Blockout and drawn objects come from LoweyCore
/// (exact recipes); library models and prefab instances are read back from their loaded
/// entities (geometry baked into world space; textures are not carried over).
@MainActor
public enum ModelExport {
    public static func meshes(_ ids: [ObjectID]?, scene: CoreScene, look: Look, renderer: SceneRenderer) -> [ExportMesh] {
        SceneExport.meshes(ids, in: scene, look: look) { object, _ in
            guard object.kind.assetID != nil || object.kind.prefabID != nil,
                  let content = renderer.node(for: object.id)?.children.first(where: { $0.name == "content" }) else { return [] }
            let tint = object.color?.resolved(in: look.palette) ?? RGBA(0.8, 0.8, 0.8)
            var result: [ExportMesh] = []
            AssetLoader.visitModels(content) { entity in
                guard entity.components[LoweyHelperComponent.self] == nil, let model = entity.components[ModelComponent.self] else { return }
                var mesh = MeshUpload.meshData(from: model.mesh)
                guard !mesh.isEmpty else { return }
                let matrix = entity.transformMatrix(relativeTo: nil)
                mesh.positions = mesh.positions.map { p in
                    let v = matrix * SIMD4<Float>(p, 1)
                    return SIMD3<Float>(v.x, v.y, v.z)
                }
                mesh.computeSmoothNormals()
                result.append(ExportMesh(name: object.name, transform: .identity, mesh: mesh, color: tint))
            }
            return result
        }
    }

    public static func data(_ format: ModelExportFormat, meshes: [ExportMesh]) -> Data {
        switch format {
        case .glb: SceneExport.glb(meshes)
        case .usdz: SceneExport.usdz(meshes)
        }
    }
}
