import Foundation
import LoweyCore
import simd

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
    /// The meshes as placed in the world (USDZ, OBJ, STL, 3MF); `painted` gives painted objects their paint mesh and
    /// texture (left out for printing).
    public static func meshes(_ ids: [ObjectID]?, scene: CoreScene, look: Look, catalog: AssetCatalog, models: ModelLibrary = .shared,
                              painted: (SceneObject) -> PaintedExport? = { _ in nil },
                              posed: (SceneObject) -> [GLTFScene.LocalPart]? = { _ in nil }) -> [ExportMesh] {
        SceneExport.meshes(ids, in: scene, look: look, extra: { object, world in
            localParts(object, look: look, catalog: catalog, models: models).map { part in
                ExportMesh(name: object.name, transform: world, mesh: part.mesh, color: part.material.color, emissive: part.material.emissive,
                           emissiveStrength: part.material.emissiveStrength, roughness: part.material.roughness, metallic: part.material.metallic)
            }
        }, painted: painted, posed: posed)
    }

    /// A rigged object's surface as its skeleton bends it, in its own space with its materials: `pose` is the animator's
    /// pose (the scene as shown), else the joints as turned by hand (the scene as edited). Nil when the object has no rig
    /// whose weights fit, and for a drawing already bent by the animator.
    public static func posedParts(_ object: SceneObject, pose: [LoweyCore.Transform]?, look: Look, catalog: AssetCatalog,
                                  models: ModelLibrary = .shared, file: (String) -> Data?) -> [GLTFScene.LocalPart]? {
        guard let rig = object.rig else { return nil }
        let skeleton = rig.skeleton
        let bind = skeleton.modelRest
        let posedModel = skeleton.modelSpace(RigPoses.posed(pose ?? skeleton.restPose, skeleton: skeleton, by: object))
        if case let .drawing(recipe) = object.kind {
            guard pose == nil, let weights = rig.points, let bent = RigPoses.bend(recipe, weights: weights, bind: bind, pose: posedModel) else { return nil }
            var shaped = object
            shaped.kind = .drawing(bent)
            return SceneExport.localMesh(of: shaped, look: look).map {
                [GLTFScene.LocalPart(name: object.name, mesh: $0, material: SceneExport.material(of: object, look: look))]
            }
        }
        guard let name = rig.skin, let weights = file(name).flatMap({ try? SkinWeights(data: $0) }) else { return nil }
        if object.kind.assetID != nil {
            let pieces = localParts(object, look: look, catalog: catalog, models: models)
            guard pieces.reduce(0, { $0 + $1.mesh.positions.count }) == weights.count else { return nil }
            var start = 0
            return pieces.map { piece in
                let range = start ..< start + piece.mesh.positions.count
                start = range.upperBound
                let slice = SkinWeights(joints: Array(weights.joints[range]), weights: Array(weights.weights[range]))
                return GLTFScene.LocalPart(name: piece.name, mesh: Skinning.deform(piece.mesh, weights: slice, bind: bind, pose: posedModel),
                                           material: piece.material)
            }
        }
        guard let source = PaintSource.mesh(of: object), source.positions.count == weights.count else { return nil }
        var mesh = Skinning.deform(source, weights: weights, bind: bind, pose: posedModel)
        if let factor = PaintSource.toObjectSpace(of: object) {
            mesh.positions = mesh.positions.map { $0 * factor }
            mesh.normals = mesh.normals.map { simd_normalize($0 / factor) }
        }
        return [GLTFScene.LocalPart(name: object.name, mesh: mesh, material: SceneExport.material(of: object, look: look))]
    }

    /// A painted object's paint mesh and texture (its shape from Core, or a placed model's parts as one).
    /// A rigged object's paint lies on its surface as `pose` bends it (see `posedParts`).
    public static func painted(_ object: SceneObject, look: Look, catalog: AssetCatalog, models: ModelLibrary = .shared,
                               file: (String) -> Data?, pose: [LoweyCore.Transform]? = nil) -> PaintedExport? {
        guard object.paint != nil else { return nil }
        var source = PaintSource.mesh(of: object)
        var base = object.color?.resolved(in: look.palette) ?? .blockout
        if source == nil, let id = object.kind.assetID, let asset = catalog.manifest.asset(id), let model = models.model(asset, catalog: catalog) {
            source = AssetPaint.mergedMesh(model)
            if object.color == nil { base = .white }
        }
        var posed: MeshData?
        if let source, let rig = object.rig, let name = rig.skin, let weights = file(name).flatMap({ try? SkinWeights(data: $0) }),
           weights.count == source.positions.count {
            let skeleton = rig.skeleton
            let model = skeleton.modelSpace(RigPoses.posed(pose ?? skeleton.restPose, skeleton: skeleton, by: object))
            posed = Skinning.deform(source, weights: weights, bind: skeleton.modelRest, pose: model)
        }
        return PaintExport.painted(object, source: source, base: base, file: file, posed: posed, encode: PaintPixels.png)
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
    /// `paintFile` reads the project's paint files: painted objects carry their texture (glTF, Blender, USDZ, OBJ).
    /// Rigged objects leave as they're posed: `poses` are the animator's (the scene as shown); without them, the joints as
    /// turned by hand.
    public static func files(_ format: ModelExportFormat, ids: [ObjectID]?, scene: CoreScene, look: Look, preset: LookPreset,
                             catalog: AssetCatalog, models: ModelLibrary = .shared, name: String,
                             paintFile: @escaping (String) -> Data? = { _ in nil },
                             poses: [ObjectID: [LoweyCore.Transform]] = [:]) -> [(name: String, data: Data)] {
        let parts: (SceneObject) -> [GLTFScene.LocalPart] = { localParts($0, look: look, catalog: catalog, models: models) }
        let paintOf: (SceneObject) -> PaintedExport? = {
            Self.painted($0, look: look, catalog: catalog, models: models, file: paintFile, pose: poses[$0.id])
        }
        let posed: (SceneObject) -> [GLTFScene.LocalPart]? = {
            posedParts($0, pose: poses[$0.id], look: look, catalog: catalog, models: models, file: paintFile)
        }
        switch format {
        case .glb:
            return [("\(name).glb", GLTFScene.glb(ids, in: scene, look: look, parts: parts, painted: paintOf, posed: posed))]
        case .blender:
            let selected = ids.map { scene.restricted(to: $0) } ?? scene
            return [("\(name) for Blender.zip", BlenderPackage.archive(selected, look: look, preset: preset, parts: parts, painted: paintOf,
                                                                       posed: posed))]
        default:
            break
        }
        let carriesColour = format == .usdz || format == .obj
        let meshes = meshes(ids, scene: scene, look: look, catalog: catalog, models: models, painted: carriesColour ? paintOf : { _ in nil },
                            posed: posed)
        guard !meshes.isEmpty else { return [] }
        switch format {
        case .usdz: return [("\(name).usdz", SceneExport.usdz(meshes))]
        case .stl: return [("\(name).stl", STLFile.binary(meshes, name: name))]
        case .threeMF: return [("\(name).3mf", ThreeMFFile.data(meshes))]
        case .obj:
            let (obj, mtl) = OBJFile.text(meshes, materialFile: "\(name).mtl")
            return [("\(name).obj", Data(obj.utf8)), ("\(name).mtl", Data(mtl.utf8))] + OBJFile.textures(meshes)
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
