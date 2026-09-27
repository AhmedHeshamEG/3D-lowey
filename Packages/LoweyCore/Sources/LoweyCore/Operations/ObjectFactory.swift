import Foundation

/// Builds new objects with sensible defaults (few decisions, good results).
public struct ObjectFactory: Sendable {
    public var ids: IDFactory

    public init(ids: IDFactory = .random) {
        self.ids = ids
    }

    public mutating func primitive(_ shape: PrimitiveShape, at position: Vec3 = .zero, color: ColorValue? = nil) -> SceneObject {
        var object = SceneObject(id: ids.next(), name: shape.displayName, kind: .primitive(shape),
                                 transform: Transform(position: position))
        object[.color] = .color(color ?? .rgba(.blockout))
        return object
    }

    public mutating func asset(_ asset: LibraryAsset, at position: Vec3 = .zero) -> SceneObject {
        SceneObject(id: ids.next(), name: asset.name, kind: .asset(asset.id), transform: Transform(position: position))
    }

    public mutating func prefabInstance(_ prefab: Prefab, at position: Vec3 = .zero) -> SceneObject {
        SceneObject(id: ids.next(), name: prefab.name, kind: .prefab(prefab.id), transform: Transform(position: position))
    }

    public mutating func group(named name: String = "Group", at position: Vec3 = .zero) -> SceneObject {
        SceneObject(id: ids.next(), name: name, kind: .group, transform: Transform(position: position))
    }

    public mutating func drawing(_ recipe: DrawingRecipe, transform: Transform, color: ColorValue) -> SceneObject {
        let name: String = switch recipe.style {
        case .tube: "Stroke"
        case .ribbon: "Ribbon"
        case .extrude: "Extrusion"
        case .lathe: "Lathe"
        }
        var object = SceneObject(id: ids.next(), name: name, kind: .drawing(recipe), transform: transform)
        object[.color] = .color(color)
        return object
    }

    public mutating func light(_ type: LightType, at position: Vec3, color: RGBA = RGBA(hex: "#FFB347")!) -> SceneObject {
        let name: String = switch type {
        case .directional: "Sun light"
        case .point: "Lamp light"
        case .spot: "Spot light"
        }
        var object = SceneObject(id: ids.next(), name: name, kind: .light(type), transform: Transform(position: position))
        object[.lightColor] = .color(.rgba(color))
        object[.lightIntensity] = .float(type == .directional ? 1 : 1.5)
        object[.lightRange] = .float(type == .directional ? 0 : 6)
        object[.lightShadows] = .bool(true)
        if type == .spot {
            object[.spotAngle] = .float(40)
            object.transform.rotation = Quat(angle: -.pi / 2, axis: .unitX) // pointing down
        }
        if type == .directional {
            object.transform.rotation = Quat(eulerDegrees: Vec3(-50, 30, 0))
        }
        return object
    }

    public mutating func camera(at viewpoint: Viewpoint) -> SceneObject {
        var object = SceneObject(id: ids.next(), name: "Camera", kind: .camera,
                                 transform: Transform(position: viewpoint.eye, rotation: viewpoint.rotation))
        object[.fieldOfView] = .float(viewpoint.fieldOfView)
        return object
    }

    /// "Cube" → "Cube 2" when "Cube" exists.
    public static func uniqueName(_ base: String, in scene: Scene) -> String {
        let names = Set(scene.objects.values.map(\.name))
        guard names.contains(base) else { return base }
        var counter = 2
        while names.contains("\(base) \(counter)") {
            counter += 1
        }
        return "\(base) \(counter)"
    }
}

/// Copying subtrees with fresh ids.
public enum FragmentTools {
    /// Extracts the given objects (and their descendants) as a fragment. Roots get their
    /// *world* transforms so the fragment can be inserted anywhere. Ids nested inside other
    /// listed ids are dropped (they come along as descendants).
    public static func extract(_ ids: [ObjectID], from scene: Scene) -> SceneFragment {
        let ordered = scene.orderedIDs()
        let requested = Set(ids)
        let topLevel = ordered.filter { id in
            requested.contains(id) && !scene.ancestors(of: id).contains(where: requested.contains)
        }
        var objects: [SceneObject] = []
        for root in topLevel {
            for (offset, node) in scene.subtree(of: root).enumerated() {
                guard var object = scene.objects[node] else { continue }
                if offset == 0 {
                    object.transform = scene.worldTransform(of: node)
                    object.parent = nil
                }
                objects.append(object)
            }
        }
        return SceneFragment(objects: objects, roots: topLevel)
    }

    /// Same structure, new ids (parents/children remapped).
    public static func reidentified(_ fragment: SceneFragment, ids: inout IDFactory) -> (SceneFragment, [ObjectID: ObjectID]) {
        var map: [ObjectID: ObjectID] = [:]
        for object in fragment.objects {
            map[object.id] = ids.next()
        }
        let objects = fragment.objects.map { object -> SceneObject in
            var copy = object
            copy.id = map[object.id] ?? object.id
            copy.parent = object.parent.flatMap { map[$0] }
            copy.children = object.children.compactMap { map[$0] }
            return copy
        }
        return (SceneFragment(objects: objects, roots: fragment.roots.compactMap { map[$0] }), map)
    }

    /// Applies `transform` on top of every root's transform (world-space move of the fragment).
    public static func transformRoots(_ fragment: SceneFragment, by transform: (Transform) -> Transform) -> SceneFragment {
        let roots = Set(fragment.roots)
        var copy = fragment
        copy.objects = fragment.objects.map { object in
            guard roots.contains(object.id) else { return object }
            var moved = object
            moved.transform = transform(object.transform)
            return moved
        }
        return copy
    }
}
