import Foundation
import LoweyCore
import os
import RealityKit
import UIKit

/// Most meshes the renderer keeps for reuse (animated faces make new ones most frames).
private let meshCacheLimit = 1500

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
    public static var objects: CollisionGroup { CollisionGroup(rawValue: 1 << 0) }
    public static var gizmo: CollisionGroup { CollisionGroup(rawValue: 1 << 1) }
    public static var guide: CollisionGroup { CollisionGroup(rawValue: 1 << 2) }
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

    /// Editor helpers (light bulbs, camera boxes). Off for export renderers, and on the stage while it shows the shot
    /// (looking through a camera, Export): the video never has other cameras or light bulbs in it.
    public var showsHelpers = true {
        didSet { if showsHelpers != oldValue { Self.setHelpers(root, enabled: showsHelpers) } }
    }

    /// Depth world: every surface writes its distance (v = 0.5 / d) instead of its colour (lens blur, outlines).
    public var depthPass = false {
        didSet { environment.depthPass = depthPass }
    }

    private var particleEntities: [ObjectID: [ModelEntity]] = [:]
    /// Each card's picture plane, its texture and the image it shows (textures change only when the frame does).
    private var cardFaces: [ObjectID: CardFace] = [:]
    /// Pictures and video frames for cards: a file name in the project's assets, or a `VideoFrameKey`.
    public var mediaImage: ((String) -> CGImage?)?

    private final class CardFace {
        let entity: ModelEntity
        var texture: TextureResource?
        var image: CGImage?

        init(entity: ModelEntity) {
            self.entity = entity
        }
    }

    /// Hides one object (the camera you are looking through).
    public var hiddenObject: ObjectID? {
        didSet {
            if let oldValue, let node = nodes[oldValue], let object = document?.scene.objects[oldValue] { node.isEnabled = object.isVisible }
            if let hiddenObject { nodes[hiddenObject]?.isEnabled = false }
        }
    }

    private var jointMaps: [ObjectID: JointMap] = [:]
    private var posed = Set<ObjectID>()
    private var clipControllers: [ObjectID: (name: String, controller: AnimationPlaybackController)] = [:]

    /// How one skinned model's RealityKit joints map to a Core skeleton.
    private struct JointMap {
        var entity: ObjectIdentifier
        var models: [(ModelEntity, [Int?], [RealityKit.Transform])]
    }

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
            particleEntities[id] = nil
            cardFaces[id] = nil
        }
        // Additions and updates, parents before children.
        let dirty: Set<ObjectID> = lookChanged ? Set(scene.objects.keys) : changes.objects
        for id in scene.orderedIDs() where dirty.contains(id) || nodes[id] == nil {
            update(id, in: document)
        }
        if lightBudget != nil, !lights.isEmpty { applyLightBudget() }
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
            node.setParent(parentEntity, preservingWorldTransform: false)
        }
        node.transform = object.transform.realityKit
        node.isEnabled = object.isVisible && hiddenObject != id
        let opacity = object.opacity
        if opacity < 0.999 {
            node.components.set(OpacityComponent(opacity: Float(max(opacity, 0))))
        } else if node.components.has(OpacityComponent.self) {
            node.components.remove(OpacityComponent.self)
        }
        // Content.
        let key = contentKey(for: object, document: document)
        if let old = contentKeys[id], old != key, old.differsOnlyInSurface(from: key), let model = contents[id] as? ModelEntity,
           let surface = key.surface {
            // Animated colour / glow: swap the material, keep the entity.
            model.model?.materials = [MaterialFactory.shared.material(for: surface)]
            contentKeys[id] = key
        } else if contentKeys[id] != key || contents[id] == nil {
            contents[id]?.removeFromParent()
            particleEntities[id] = nil
            cardFaces[id] = nil
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
        case blockText(TextRecipe)
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
        /// Characters of 3D text shown (typewriter).
        var revealed: Int
        /// Glow of an imported model (it glows in its own colours; primitives carry glow in `surface`).
        var assetGlow: Double = 0

        func differsOnlyInSurface(from other: ContentKey) -> Bool {
            var copy = self
            copy.surface = other.surface
            return copy == other && surface != nil && other.surface != nil
        }
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
            // Quantised so animated glow reuses a bounded set of materials.
            emissiveIntensity: (object.emissiveIntensity * 20).rounded() / 20,
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
        var revealed = 0
        if case let .text(recipe) = object.kind {
            let reveal = min(max(object[.reveal]?.floatValue ?? 1, 0), 1)
            revealed = Int((Double(recipe.text.count) * reveal).rounded(.down))
        }
        return ContentKey(
            kind: object.kind,
            shading: effectiveShading(object, look: look),
            surface: surfaceKey(for: object, palette: look.palette),
            tinted: object.color != nil,
            light: lightProperties,
            prefabVersion: prefabVersion,
            assetState: assetState,
            revealed: revealed,
            assetGlow: object.kind.assetID != nil ? (object.emissiveIntensity * 20).rounded() / 20 : 0
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
            icon.isEnabled = showsHelpers
            return icon

        case let .text(recipe):
            var shown = recipe
            shown.text = String(recipe.text.prefix(key.revealed))
            if shown.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return Entity() }
            if recipe.coreMeshable { return meshEntity(.blockText(shown), surface: key.surface) }
            return systemText(shown, surface: key.surface)

        case .overlay:
            // Drawn by the compositor in frame space; nothing in the world.
            return Entity()

        case let .card(recipe):
            return cardContent(recipe, id: depth == 0 ? object.id : nil, surface: key.surface)

        case .particles:
            // Filled every frame by `applyParticles`.
            let container = Entity()
            let icon = ModelEntity(mesh: .generateSphere(radius: 0.08), materials: [MaterialFactory.shared.helper(color: .systemOrange, opacity: 0.6)])
            icon.components.set(LoweyHelperComponent())
            icon.generateCollisionShapes(recursive: false)
            icon.isEnabled = showsHelpers
            container.addChild(icon)
            return container
        }
    }

    /// Smooth outline text in any script (Arabic included) through the system fonts.
    private func systemText(_ recipe: TextRecipe, surface: SurfaceKey?) -> Entity {
        let size = CGFloat(max(recipe.size, 0.01))
        let font: UIFont = switch recipe.style {
        case .rounded:
            UIFont.systemFont(ofSize: size, weight: .heavy).withDesign(.rounded)
        case .serif:
            UIFont.systemFont(ofSize: size, weight: .bold).withDesign(.serif)
        case .mono:
            UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        case .bold, .blocky:
            UIFont.systemFont(ofSize: size, weight: .black)
        }
        let alignment: CTTextAlignment = switch recipe.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        let mesh = MeshResource.generateText(recipe.text, extrusionDepth: Float(recipe.size * recipe.depth), font: font,
                                             containerFrame: .zero, alignment: alignment, lineBreakMode: .byWordWrapping)
        let material = depthPass ? MaterialFactory.shared.depthMaterial
            : MaterialFactory.shared.material(for: surface ?? SurfaceKey(color: .blockout, fog: fog))
        let model = ModelEntity(mesh: mesh, materials: [material])
        // Base-centred like every Lowey object: stand the text on the ground, centred on its pivot.
        let bounds = mesh.bounds
        let xOffset: Float = switch recipe.alignment {
        case .left: -bounds.min.x
        case .center: -bounds.center.x
        case .right: -bounds.max.x
        }
        model.position = SIMD3<Float>(xOffset, -bounds.min.y, -bounds.center.z)
        model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: pointwiseMax(bounds.extents, SIMD3<Float>(repeating: 0.02)))
                .offsetBy(translation: bounds.center)])
        let container = Entity()
        container.addChild(model)
        return container
    }

    // MARK: Cards

    /// A thin slab (the card, lit, in its colour) with the picture on its front (unlit, so it reads like the picture).
    private func cardContent(_ recipe: CardRecipe, id: ObjectID?, surface: SurfaceKey?) -> Entity {
        let size = recipe.cardSize
        let container = Entity()
        let frameMaterial = depthPass ? MaterialFactory.shared.depthMaterial
            : MaterialFactory.shared.material(for: surface ?? SurfaceKey(color: RGBA(0.96, 0.95, 0.92), fog: fog))
        let slab = ModelEntity(mesh: .generateBox(width: Float(size.width), height: Float(size.height), depth: Float(size.depth),
                                                  cornerRadius: Float(min(size.depth * 0.45, 0.012))),
                               materials: [frameMaterial])
        slab.position = SIMD3<Float>(0, Float(size.height / 2), 0)
        container.addChild(slab)
        let picture = recipe.pictureSize
        let face = ModelEntity(mesh: .generatePlane(width: Float(picture.width), height: Float(picture.height)),
                               materials: [depthPass ? MaterialFactory.shared.depthMaterial : UnlitMaterial(color: UIColor(white: 0.18, alpha: 1))])
        face.name = "picture"
        face.position = SIMD3<Float>(0, Float(size.height / 2), Float(size.depth / 2) + 0.0015)
        container.addChild(face)
        container.components.set(CollisionComponent(shapes: [
            ShapeResource.generateBox(size: SIMD3<Float>(Float(size.width), Float(size.height), Float(max(size.depth, 0.04))))
                .offsetBy(translation: SIMD3<Float>(0, Float(size.height / 2), 0))
        ]))
        if let id, !depthPass { cardFaces[id] = CardFace(entity: face) }
        return container
    }

    /// Shows each card's picture, or its video's frame at `time` (after `sync`). A texture is replaced only when the image
    /// changes; a frame that isn't decoded yet keeps the last one on the card.
    public func applyCards(_ scene: CoreScene, time: Double) {
        guard !cardFaces.isEmpty, let mediaImage else { return }
        for (id, face) in cardFaces {
            guard let object = scene.objects[id], case let .card(recipe) = object.kind, let key = recipe.frameKey(at: time),
                  let image = mediaImage(key), image !== face.image else { continue }
            face.image = image
            let fitted = Self.fitted(image, maxSide: recipe.video != nil ? 1280 : 2048)
            if let texture = face.texture {
                try? texture.replace(withImage: fitted, options: .init(semantic: .color))
            } else if let texture = try? TextureResource(image: fitted, options: .init(semantic: .color)) {
                face.texture = texture
                var material = UnlitMaterial()
                material.color = .init(tint: .white, texture: .init(texture))
                face.entity.model?.materials = [material]
            }
        }
    }

    /// Big photos are drawn down to `maxSide` pixels (a 12 MP picture as a texture is 48 MB of memory for nothing).
    static func fitted(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let scale = Double(maxSide) / Double(longest)
        let width = max(Int(Double(image.width) * scale), 1)
        let height = max(Int(Double(image.height) * scale), 1)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    // MARK: Particles

    /// Rebuilds particle meshes for `time` (after `sync`). Particles are a pure function of time, so this is
    /// exact while scrubbing and in export. Colours are grouped into a few bands, one mesh + material each.
    public func applyParticles(_ scene: CoreScene, timeline: Timeline, time: Double) {
        guard !depthPass else { return }
        for (id, object) in scene.objects {
            guard case let .particles(recipe) = object.kind, let content = contents[id] else { continue }
            let visible = scene.isEffectivelyVisible(id)
            let track = timeline.track(for: id, .emission)
            let amount = max(object.transform.scale.x, 0)
            let particles = visible ? ParticleSimulator.particles(recipe, at: time, amount: amount) { birth in
                track?.value(at: birth)?.floatValue ?? object[.emission]?.floatValue ?? 1
            } : []
            let bands = ParticleMesher.bands(particles, recipe: recipe)
            var entities = particleEntities[id] ?? []
            while entities.count < bands.count {
                let entity = ModelEntity()
                entity.name = "particles"
                content.addChild(entity)
                entities.append(entity)
            }
            for (index, entity) in entities.enumerated() {
                guard index < bands.count, let resource = try? MeshUpload.resource(from: bands[index].mesh) else {
                    entity.isEnabled = false
                    continue
                }
                let band = bands[index]
                var material = UnlitMaterial(color: band.color.uiColor)
                if band.opacity < 0.999 { material.blending = .transparent(opacity: .init(floatLiteral: Float(band.opacity))) }
                entity.model = ModelComponent(mesh: resource, materials: [material])
                entity.isEnabled = true
            }
            // Undo the object's scale for the particles themselves (scale = amount), keep rotation and position.
            let inverse = SIMD3<Float>(repeating: 1) / pointwiseMax(object.transform.scale.simd, SIMD3<Float>(repeating: 0.001))
            for entity in entities {
                entity.scale = inverse
            }
            particleEntities[id] = entities
        }
    }

    private func mesh(_ key: MeshKey) -> (MeshResource, Bounds)? {
        if let cached = meshCache[key] { return cached }
        let data: MeshData = switch key {
        case let .primitive(shape, shading): PrimitiveMesh.make(shape, shading: shading)
        case let .drawing(recipe, shading): DrawingMesher.mesh(for: recipe).shaded(shading)
        case let .blockText(recipe): BlockFont.mesh(for: recipe)
        }
        guard !data.isEmpty, let resource = try? MeshUpload.resource(from: data), let bounds = data.bounds else { return nil }
        // Animated faces make a new shape most frames: keep the cache bounded (meshes on screen stay alive in their entities).
        if meshCache.count >= meshCacheLimit { meshCache.removeAll(keepingCapacity: true) }
        meshCache[key] = (resource, bounds)
        return (resource, bounds)
    }

    private func meshEntity(_ key: MeshKey, surface: SurfaceKey?) -> Entity {
        guard let (resource, bounds) = mesh(key) else { return placeholder(color: .systemRed) }
        let material = depthPass ? MaterialFactory.shared.depthMaterial
            : MaterialFactory.shared.material(for: surface ?? SurfaceKey(color: .blockout, fog: fog))
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
            if depthPass {
                model.materials = Array(repeating: MaterialFactory.shared.depthMaterial, count: max(model.materials.count, 1))
            } else if let surface {
                // Tinted: one Lowey material for the whole model.
                model.materials = Array(repeating: MaterialFactory.shared.material(for: surface), count: max(model.materials.count, 1))
            } else {
                let glow = (object.emissiveIntensity * 20).rounded() / 20
                model.materials = model.materials.enumerated().map { index, material in
                    MaterialFactory.shared.converted(material, identity: "\(assetID.raw)#\(slot)#\(index)", fog: fog, glow: glow)
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

    /// Waits until every model that started loading is in (exports never render placeholders).
    public func waitForAssets(timeout: TimeInterval = 30) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !loadingAssets.isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
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

    /// One scene light, for the live stage's light budget.
    private final class LightSlot {
        weak var light: Entity?
        let radius: Float
        let directional: Bool
        /// Shadows as the object asks for them, and a way to switch them.
        let wantsShadow: Bool
        let setShadow: (Bool) -> Void
        var shadowOn: Bool

        init(light: Entity, radius: Float, directional: Bool, wantsShadow: Bool, setShadow: @escaping (Bool) -> Void) {
            self.light = light
            self.radius = radius
            self.directional = directional
            self.wantsShadow = wantsShadow
            self.setShadow = setShadow
            shadowOn = wantsShadow
        }
    }

    private var lights: [LightSlot] = []
    private var budgetView: (eye: SIMD3<Float>, forward: SIMD3<Float>)?

    /// Live stage only (nil = every light shines, as in exports): how many point / spot lights shine at once and how
    /// many of them cast shadows. The ones nearest to what you're looking at win. A big set with twenty lamps spread
    /// over five rooms then lights (and shadow-maps) only the room you're in, instead of all of them every frame.
    public var lightBudget: (lights: Int, shadows: Int)? {
        didSet { applyLightBudget() }
    }

    /// Where the stage looks from (called on every camera move; cheap: a handful of lights, changes only on a switch).
    public func budgetLights(eye: SIMD3<Float>, forward: SIMD3<Float>) {
        budgetView = (eye, forward)
        applyLightBudget()
    }

    private func applyLightBudget() {
        lights.removeAll { $0.light == nil || $0.light?.parent == nil }
        guard let budget = lightBudget, let view = budgetView else {
            for slot in lights {
                slot.light?.isEnabled = true
                if slot.shadowOn != slot.wantsShadow {
                    slot.setShadow(slot.wantsShadow)
                    slot.shadowOn = slot.wantsShadow
                }
            }
            return
        }
        var ranked: [(slot: LightSlot, score: Float)] = []
        for slot in lights {
            guard let light = slot.light, light.parent?.isEnabledInHierarchy == true else { continue }
            if slot.directional {
                ranked.append((slot, -1))
                continue
            }
            let position = light.position(relativeTo: nil)
            let offset = position - view.eye
            let gap = max(simd_length(offset) - slot.radius, 0)
            // Wholly behind the camera: it can't light anything in view.
            let behind = simd_dot(offset, view.forward) < -slot.radius
            ranked.append((slot, behind ? gap + 10000 : gap))
        }
        ranked.sort { $0.score < $1.score }
        var shining = 0
        var shadows = 0
        for (slot, _) in ranked {
            let on = slot.directional || shining < budget.lights
            if !slot.directional, on { shining += 1 }
            if slot.light?.isEnabled != on { slot.light?.isEnabled = on }
            var shadow = false
            if on, slot.wantsShadow, shadows < budget.shadows {
                shadow = true
                shadows += 1
            }
            if shadow != slot.shadowOn {
                slot.setShadow(shadow)
                slot.shadowOn = shadow
            }
        }
    }

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
            lights.append(LightSlot(light: light, radius: max(range, 0.1), directional: false, wantsShadow: false) { _ in })
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
            lights.append(LightSlot(light: light, radius: max(range, 0.1), directional: false, wantsShadow: shadows) { [weak light] on in
                light?.shadow = on ? SpotLightComponent.Shadow() : nil
            })
        case .directional:
            let light = DirectionalLight()
            light.light.color = color
            light.light.intensity = intensity * 2600
            if shadows { light.shadow = DirectionalLightComponent.Shadow(maximumDistance: 40, depthBias: 2) }
            container.addChild(light)
            lights.append(LightSlot(light: light, radius: .infinity, directional: true, wantsShadow: shadows) { [weak light] on in
                light?.shadow = on ? DirectionalLightComponent.Shadow(maximumDistance: 40, depthBias: 2) : nil
            })
        }
        // Editor icon: a small glowing bulb in the light's colour.
        let icon = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [MaterialFactory.shared.helper(color: color)])
        icon.components.set(LoweyHelperComponent())
        icon.collision = CollisionComponent(shapes: [.generateSphere(radius: 0.12)])
        icon.isEnabled = showsHelpers
        container.addChild(icon)
        return container
    }

    // MARK: Characters

    /// Applies skeletal poses (from `Animator`) to skinned models. Objects that were posed before but
    /// have no pose now go back to their rest pose.
    public func applyPoses(_ poses: [ObjectID: [CoreTransform]], rigs: [AssetID: RigAsset]) {
        guard let document else { return }
        for id in posed.subtracting(poses.keys) {
            if let map = jointMaps[id] {
                for (model, _, rest) in map.models {
                    model.jointTransforms = rest
                }
            }
        }
        posed = Set(poses.keys)
        for (id, pose) in poses {
            guard let assetID = document.scene.objects[id]?.kind.assetID, let rig = rigs[assetID],
                  let content = contents[id] else { continue }
            let map = jointMap(for: id, content: content, skeleton: rig.skeleton)
            for (model, indices, rest) in map.models {
                var transforms = model.jointTransforms
                guard transforms.count == indices.count, rest.count == indices.count else { continue }
                for (index, core) in indices.enumerated() {
                    guard let core, core < pose.count, core < rig.skeleton.joints.count else { continue }
                    // Relative to the model's own rest pose, so armature conventions don't matter.
                    let delta = CoreTransform.relative(world: pose[core], toParent: rig.skeleton.joints[core].rest)
                    let restCore = CoreTransform(rest[index])
                    transforms[index] = (restCore * delta).realityKit
                }
                model.jointTransforms = transforms
            }
        }
    }

    private func jointMap(for id: ObjectID, content: Entity, skeleton: Skeleton) -> JointMap {
        if let existing = jointMaps[id], existing.entity == ObjectIdentifier(content) { return existing }
        var lookup: [String: Int] = [:]
        for (index, joint) in skeleton.joints.enumerated() {
            lookup[Self.jointKey(joint.name)] = index
        }
        var models: [(ModelEntity, [Int?], [RealityKit.Transform])] = []
        AssetLoader.visitModels(content) { entity in
            guard let model = entity as? ModelEntity, !model.jointNames.isEmpty else { return }
            var indices = model.jointNames.map { lookup[Self.jointKey($0)] }
            if indices.allSatisfy({ $0 == nil }), model.jointNames.count == skeleton.joints.count {
                // Unnamed joints: same count, same order.
                indices = Array(skeleton.joints.indices)
            }
            models.append((model, indices, model.jointTransforms))
        }
        let map = JointMap(entity: ObjectIdentifier(content), models: models)
        jointMaps[id] = map
        return map
    }

    /// "Armature/Hips/Spine.001" becomes "spine001": last path component, letters and digits only.
    static func jointKey(_ name: String) -> String {
        let last = name.split(separator: "/").last.map(String.init) ?? name
        return String(last.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Clips on models without Core rig data (USDZ): RealityKit's own animation, paused and scrubbed.
    public func applyClipFallback(_ timeline: Timeline, at time: Double, skipping handled: Set<ObjectID>) {
        guard let document else { return }
        for track in timeline.clipTracks where !handled.contains(track.target) {
            guard let content = contents[track.target], document.scene.objects[track.target] != nil,
                  let best = track.weights(at: time).max(by: { $0.weight < $1.weight }) else { continue }
            let segment = best.segment
            var animation: AnimationResource?
            AssetLoader.visit(content) { entity in
                if animation == nil { animation = entity.availableAnimations.first { $0.name == segment.clip.name } }
            }
            guard let animation else { continue }
            let controller: AnimationPlaybackController
            if let existing = clipControllers[track.target], existing.name == segment.clip.name, existing.controller.isValid {
                controller = existing.controller
            } else {
                clipControllers[track.target]?.controller.stop()
                // Paused and scrubbed: the segment's own looping maps timeline time to clip time.
                controller = content.playAnimation(animation, transitionDuration: 0, startsPaused: true)
                clipControllers[track.target] = (segment.clip.name, controller)
            }
            controller.time = segment.clipTime(at: time, clipDuration: controller.duration)
        }
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

    /// Shows or hides every object helper (camera boxes, light bulbs, particle emitters) in the world.
    static func setHelpers(_ entity: Entity, enabled: Bool) {
        for child in entity.children {
            if child.components[LoweyHelperComponent.self] != nil {
                child.isEnabled = enabled
            } else {
                setHelpers(child, enabled: enabled)
            }
        }
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
