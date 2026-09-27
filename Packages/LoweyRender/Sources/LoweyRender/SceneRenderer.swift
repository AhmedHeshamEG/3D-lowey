import Foundation
import LoweyCore
import os
import RealityKit
import UIKit

/// Marks the entity that represents a scene object (its "node").
public struct LoweyObjectComponent: Component, Sendable {
    public var id: String
    public init(id: String) { self.id = id }
}

/// Marks editor-only helpers (light icons, camera icons). Stripped from snapshots and exports.
public struct LoweyHelperComponent: Component, Sendable {
    public init() {}
}

/// Collision groups used for picking.
public enum PickGroup {
    public static let objects = CollisionGroup(rawValue: 1 << 0)
    public static let gizmo = CollisionGroup(rawValue: 1 << 1)
    public static let guide = CollisionGroup(rawValue: 1 << 2)
}

/// Provides library data to the renderer (manifest + where files live).
@MainActor
public protocol LibraryProviding: AnyObject {
    var manifest: LibraryManifest { get }
    func fileURL(for asset: LibraryAsset) -> URL
    /// Called when a model was loaded and measured for the first time.
    func didMeasure(_ asset: AssetID, info: AssetInfo)
}

/// Turns a LoweyCore scene into RealityKit entities and keeps them in sync, updating only
/// what a `ChangeSet` says changed.
@MainActor
public final class SceneRenderer {
    public let root = Entity()
    public let objectsRoot = Entity()
    public let environment = EnvironmentRig()
    public let assets = AssetLoader()
    public weak var library: LibraryProviding?

    private var nodes: [ObjectID: Entity] = [:]
    private var contents: [ObjectID: Entity] = [:]
    private var contentKeys: [ObjectID: ContentKey] = [:]
    private var meshCache: [MeshKey: (MeshResource, Bounds)] = [:]
    private var document: Document?
    private var fog = FogUniform.none
    private var loadingAssets = Set<AssetID>()
    private var failedAssets = Set<AssetID>()
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "render")

    /// Fired after asynchronous content (a model finishing loading) appears, so overlays can refresh.
    public var onContentChanged: (() -> Void)?

    public static func registerComponents() {
        LoweyObjectComponent.registerComponent()
        LoweyHelperComponent.registerComponent()
    }

    public init() {
        Self.registerComponents()
        root.name = "LoweyWorld"
        objectsRoot.name = "Objects"
        root.addChild(environment.root)
        root.addChild(objectsRoot)
    }

    public var currentDocument: Document? { document }

    // MARK: Sync

    /// Full rebuild (after opening a scene).
    public func load(_ document: Document) {
        for node in nodes.values {
            node.removeFromParent()
        }
        nodes.removeAll()
        contents.removeAll()
        contentKeys.removeAll()
        self.document = nil
        sync(document, changes: .everything(in: document))
    }

    /// Applies a change set.
    public func sync(_ document: Document, changes: ChangeSet) {
        let previousLook = self.document?.effectiveLook
        self.document = document
        let look = document.effectiveLook
        let lookChanged = changes.look || previousLook != look
        if lookChanged {
            environment.apply(look)
            fog = FogUniform(fog: look.fog)
        }
        let scene = document.scene
        // Removals.
        for (id, node) in nodes where scene.objects[id] == nil {
            node.removeFromParent()
            nodes[id] = nil
            contents[id] = nil
            contentKeys[id] = nil
        }
        // Additions and updates, parents before children.
        let dirty: Set<ObjectID> = lookChanged ? Set(scene.objects.keys) : changes.objects
        for id in scene.orderedIDs() where dirty.contains(id) || nodes[id] == nil {
            update(id, in: document)
        }
    }

    private func update(_ id: ObjectID, in document: Document) {
        guard let object = document.scene.objects[id] else { return }
        let node: Entity
        if let existing = nodes[id] {
            node = existing
        } else {
            node = Entity()
            node.name = object.name
            node.components.set(LoweyObjectComponent(id: id.raw))
            nodes[id] = node
        }
        node.name = object.name
        // Parent.
        let parentEntity = object.parent.flatMap { nodes[$0] } ?? objectsRoot
        if node.parent !== parentEntity {
            node.setParent(parentEntity, preserveWorldTransform: false)
        }
        node.transform = object.transform.realityKit
        node.isEnabled = object.isVisible
        // Content.
        let key = contentKey(for: object, document: document)
        if contentKeys[id] != key || contents[id] == nil {
            contents[id]?.removeFromParent()
            let content = buildContent(for: object, key: key, document: document, depth: 0)
            content.name = "content"
            node.addChild(content)
            contents[id] = content
            contentKeys[id] = key
        }
    }

    // MARK: Content

    private enum MeshKey: Hashable {
        case primitive(PrimitiveShape, ShadingStyle)
        case drawing(DrawingRecipe, ShadingStyle)
    }

    /// Everything that determines an object's content entity (transform excluded).
    private struct ContentKey: Hashable {
        var kind: ObjectKind
        var shading: ShadingStyle
        var surface: SurfaceKey?
        var tinted: Bool
        var light: [PropertyKey: PropertyValue]
        var prefabVersion: Int
        var assetState: Int
    }

    private func effectiveShading(_ object: SceneObject, look: Look) -> ShadingStyle {
        switch object.shading {
        case .inherit: look.shading
        case .smooth: .smooth
        case .flat: .flat
        }
    }

    private func surfaceKey(for object: SceneObject, palette: Palette) -> SurfaceKey? {
        guard object.kind.hasSurface else { return nil }
        let color = object.color?.resolved(in: palette)
        if color == nil, object.emissive == nil, object.kind.assetID != nil || object.kind.prefabID != nil { return nil }
        let emissive = object.emissive?.resolved(in: palette)
        return SurfaceKey(
            color: color ?? .blockout,
            emissive: emissive ?? (object.emissiveIntensity > 0 ? color : nil),
            emissiveIntensity: object.emissiveIntensity,
            roughness: object[.roughness]?.floatValue ?? 0.85,
            metallic: object[.metallic]?.floatValue ?? 0,
            fog: fog
        )
    }

    private func contentKey(for object: SceneObject, document: Document) -> ContentKey {
        let look = document.effectiveLook
        var lightProperties: [PropertyKey: PropertyValue] = [:]
        if case .light = object.kind {
            for key in [PropertyKey.lightColor, .lightIntensity, .lightRange, .spotAngle, .lightShadows] {
                lightProperties[key] = object[key]
            }
        }
        var prefabVersion = 0
        if let prefabID = object.kind.prefabID {
            prefabVersion = library?.manifest.prefab(prefabID)?.version ?? -1
        }
        var assetState = 0
        if let assetID = object.kind.assetID {
            assetState = assets.cachedPrototype(assetID) != nil ? 2 : (failedAssets.contains(assetID) ? 3 : 1)
        }
        return ContentKey(
            kind: object.kind,
            shading: effectiveShading(object, look: look),
            surface: surfaceKey(for: object, palette: look.palette),
            tinted: object.color != nil,
            light: lightProperties,
            prefabVersion: prefabVersion,
            assetState: assetState
        )
    }

    private func buildContent(for object: SceneObject, key: ContentKey, document: Document, depth: Int) -> Entity {
        let look = document.effectiveLook
        switch object.kind {
        case .group:
            return Entity()

        case let .primitive(shape):
            return meshEntity(.primitive(shape, key.shading), surface: key.surface)

        case let .drawing(recipe):
            return meshEntity(.drawing(recipe, key.shading), surface: key.surface)

        case let .asset(assetID):
            return assetContent(assetID, object: object, shading: key.shading, surface: key.surface)

        case let .prefab(prefabID):
            let container = Entity()
            guard depth < 6, let prefab = library?.manifest.prefab(prefabID) else {
                container.addChild(placeholder(color: .systemPurple))
                return container
            }
            let byID = Dictionary(uniqueKeysWithValues: prefab.fragment.objects.map { ($0.id, $0) })
            func add(_ id: ObjectID, to parent: Entity) {
                guard let child = byID[id] else { return }
                let node = Entity()
                node.name = child.name
                node.transform = child.transform.realityKit
                node.isEnabled = child.isVisible
                var childForBuild = child
                // An instance-level color tints every part (few decisions, big results).
                if let tint = object.color, child.kind.hasSurface { childForBuild[.color] = .color(tint) }
                let childKey = contentKey(for: childForBuild, document: document)
                node.addChild(buildContent(for: childForBuild, key: childKey, document: document, depth: depth + 1))
                parent.addChild(node)
                for grandchild in child.children {
                    add(grandchild, to: node)
                }
            }
            for rootID in prefab.fragment.roots {
                add(rootID, to: container)
            }
            if depth == 0 { addPickingShape(to: container) }
            return container

        case let .light(type):
            return lightContent(type, object: object, palette: look.palette)

        case .camera:
            let icon = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.3, 0.2, 0.2)),
                                   materials: [MaterialFactory.shared.helper(color: .systemTeal)])
            icon.components.set(LoweyHelperComponent())
            icon.generateCollisionShapes(recursive: false)
            return icon
        }
    }

    private func mesh(_ key: MeshKey) -> (MeshResource, Bounds)? {
        if let cached = meshCache[key] { return cached }
        let data: MeshData = switch key {
        case let .primitive(shape, shading): PrimitiveMesh.make(shape, shading: shading)
        case let .drawing(recipe, shading): DrawingMesher.mesh(for: recipe).shaded(shading)
        }
        guard !data.isEmpty, let resource = try? MeshUpload.resource(from: data), let bounds = data.bounds else { return nil }
        meshCache[key] = (resource, bounds)
        return (resource, bounds)
    }

    private func meshEntity(_ key: MeshKey, surface: SurfaceKey?) -> Entity {
        guard let (resource, bounds) = mesh(key) else { return placeholder(color: .systemRed) }
        let material = MaterialFactory.shared.material(for: surface ?? SurfaceKey(color: .blockout, fog: fog))
        let entity = ModelEntity(mesh: resource, materials: [material])
        let size = bounds.size.simd
        let padded = SIMD3<Float>(max(size.x, 0.02), max(size.y, 0.02), max(size.z, 0.02))
        entity.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: padded).offsetBy(translation: bounds.center.simd)])
        return entity
    }

    private func placeholder(color: UIColor) -> Entity {
        let box = ModelEntity(mesh: .generateBox(size: 1, cornerRadius: 0.05),
                              materials: [MaterialFactory.shared.helper(color: color, opacity: 0.35)])
        box.position = SIMD3<Float>(0, 0.5, 0)
        box.generateCollisionShapes(recursive: false)
        return box
    }

    private func addPickingShape(to entity: Entity) {
        let bounds = entity.visualBounds(recursive: true, relativeTo: entity)
        guard !bounds.isEmpty else { return }
        let size = bounds.extents
        entity.components.set(CollisionComponent(shapes: [
            ShapeResource.generateBox(size: SIMD3<Float>(max(size.x, 0.02), max(size.y, 0.02), max(size.z, 0.02)))
                .offsetBy(translation: bounds.center)
        ]))
    }

    // MARK: Assets

    private func assetContent(_ assetID: AssetID, object: SceneObject, shading: ShadingStyle, surface: SurfaceKey?) -> Entity {
        guard let library, let asset = library.manifest.asset(assetID) else {
            return placeholder(color: .systemOrange)
        }
        guard let prototype = shading == .flat ? assets.facetedPrototype(assetID) : assets.cachedPrototype(assetID) else {
            if failedAssets.contains(assetID) { return placeholder(color: .systemRed) }
            startLoading(asset)
            return placeholder(color: .systemGray)
        }
        let clone = prototype.clone(recursive: true)
        var slot = 0
        AssetLoader.visitModels(clone) { entity in
            guard var model = entity.components[ModelComponent.self] else { return }
            if let surface {
                // Tinted: one Lowey material for the whole model.
                model.materials = Array(repeating: MaterialFactory.shared.material(for: surface), count: max(model.materials.count, 1))
            } else {
                model.materials = model.materials.enumerated().map { index, material in
                    MaterialFactory.shared.converted(material, identity: "\(assetID.raw)#\(slot)#\(index)", fog: fog)
                }
            }
            slot += 1
            entity.components.set(model)
        }
        let container = Entity()
        container.addChild(clone)
        addPickingShape(to: container)
        return container
    }

    private func startLoading(_ asset: LibraryAsset) {
        guard !loadingAssets.contains(asset.id), let library else { return }
        loadingAssets.insert(asset.id)
        let url = library.fileURL(for: asset)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let prototype = try await assets.prototype(for: asset, url: url)
                if asset.bounds == nil || asset.triangleCount == nil {
                    self.library?.didMeasure(asset.id, info: AssetLoader.info(for: prototype))
                }
            } catch {
                logger.error("Loading \(asset.name) failed: \(String(describing: error))")
                failedAssets.insert(asset.id)
            }
            loadingAssets.remove(asset.id)
            refreshObjects { $0.kind.assetID == asset.id || $0.kind.prefabID != nil }
        }
    }

    /// Rebuilds content for objects matching `predicate` (after an asset loads or a prefab changes).
    public func refreshObjects(where predicate: (SceneObject) -> Bool) {
        guard let document else { return }
        var ids = Set<ObjectID>()
        for (id, object) in document.scene.objects where predicate(object) {
            ids.insert(id)
        }
        guard !ids.isEmpty else { return }
        for id in document.scene.orderedIDs() where ids.contains(id) {
            contentKeys[id] = nil
            update(id, in: document)
        }
        onContentChanged?()
    }

    /// Call after a prefab was edited in the library: every instance updates.
    public func prefabChanged(_ id: PrefabID) {
        refreshObjects { $0.kind.prefabID != nil }
    }

    /// Forget a model (re-import) and rebuild its instances.
    public func assetChanged(_ id: AssetID) {
        assets.evict(id)
        failedAssets.remove(id)
        refreshObjects { $0.kind.assetID == id }
    }

    // MARK: Lights

    private func lightContent(_ type: LightType, object: SceneObject, palette: Palette) -> Entity {
        let color = (object[.lightColor]?.colorValue?.resolved(in: palette) ?? .white).uiColor
        let intensity = Float(object[.lightIntensity]?.floatValue ?? 1)
        let range = Float(object[.lightRange]?.floatValue ?? 6)
        let shadows = object[.lightShadows]?.boolValue ?? true
        let container = Entity()
        switch type {
        case .point:
            let light = PointLight()
            light.light.color = color
            light.light.intensity = intensity * 12000
            light.light.attenuationRadius = max(range, 0.1)
            container.addChild(light)
        case .spot:
            let light = SpotLight()
            let angle = Float(object[.spotAngle]?.floatValue ?? 40)
            light.light.color = color
            light.light.intensity = intensity * 20000
            light.light.attenuationRadius = max(range, 0.1)
            light.light.outerAngleInDegrees = angle
            light.light.innerAngleInDegrees = angle * 0.6
            if shadows { light.shadow = SpotLightComponent.Shadow() }
            container.addChild(light)
        case .directional:
            let light = DirectionalLight()
            light.light.color = color
            light.light.intensity = intensity * 2600
            if shadows { light.shadow = DirectionalLightComponent.Shadow(maximumDistance: 40, depthBias: 2) }
            container.addChild(light)
        }
        // Editor icon: a small glowing bulb in the light's colour.
        let icon = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [MaterialFactory.shared.helper(color: color)])
        icon.components.set(LoweyHelperComponent())
        icon.collision = CollisionComponent(shapes: [.generateSphere(radius: 0.12)])
        container.addChild(icon)
        return container
    }

    // MARK: Queries

    public func node(for id: ObjectID) -> Entity? { nodes[id] }

    /// The scene object an entity belongs to (walks up to the nearest object node).
    public func objectID(for entity: Entity) -> ObjectID? {
        var current: Entity? = entity
        while let node = current {
            if let tag = node.components[LoweyObjectComponent.self] { return ObjectID(raw: tag.id) }
            current = node.parent
        }
        return nil
    }

    /// World-space visual bounds of objects (what you see, including loaded models).
    public func visualBounds(of ids: [ObjectID]) -> Bounds? {
        var result: Bounds?
        for id in ids {
            guard let node = nodes[id], node.isEnabledInHierarchy else { continue }
            let box = node.visualBounds(recursive: true, relativeTo: nil, excludeInactive: true)
            guard !box.isEmpty else { continue }
            let bounds = box.loweyBounds
            result = result.map { $0.union(bounds) } ?? bounds
        }
        return result
    }

    /// Geometry of an object in world space (for drawing on its surface).
    public func worldMesh(of id: ObjectID) -> MeshData? {
        guard let node = nodes[id] else { return nil }
        var result = MeshData()
        AssetLoader.visitModels(node) { entity in
            guard entity.components[LoweyHelperComponent.self] == nil,
                  let model = entity.components[ModelComponent.self] else { return }
            let local = MeshUpload.meshData(from: model.mesh)
            let matrix = entity.transformMatrix(relativeTo: nil)
            var world = local
            world.positions = local.positions.map { p in
                let v = matrix * SIMD4<Float>(p, 1)
                return SIMD3<Float>(v.x, v.y, v.z)
            }
            result.append(world)
        }
        return result.isEmpty ? nil : result
    }

    /// A clone of the world without editor helpers, for offscreen rendering.
    public func renderableClone() -> Entity {
        let clone = root.clone(recursive: true)
        Self.stripHelpers(clone)
        return clone
    }

    static func stripHelpers(_ entity: Entity) {
        for child in Array(entity.children) {
            if child.components[LoweyHelperComponent.self] != nil {
                child.removeFromParent()
            } else {
                stripHelpers(child)
            }
        }
    }
}
