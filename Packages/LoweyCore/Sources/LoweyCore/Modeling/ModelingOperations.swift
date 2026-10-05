import Foundation

/// The Model tools as commands: each returns one `EditCommand` (one undo step, one journal entry) built from
/// `setKind`, `insert`, `delete` and `setProperties`, so the journal, undo and the bridge need nothing new.
public enum ModelingOperations {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notEditable
        case needsTwoSolids
        case noSuchRegion
        case pushPull(PushPull.Failure)
        case boolean(MeshBoolean.Failure)
        case shape(ShapeFailure)

        public var description: String {
            switch self {
            case .notEditable: "This kind of object can't be modelled."
            case .needsTwoSolids: "Select two or more solids."
            case .noSuchRegion: "That area isn't closed."
            case let .pushPull(failure): failure.description
            case let .boolean(failure): failure.description
            case let .shape(failure): failure.description
            }
        }
    }

    // MARK: Editable meshes

    /// The object's shape as an editable mesh in its own space (before its scale), when it has one.
    public static func editableMesh(of object: SceneObject) -> EditableMesh? {
        switch object.kind {
        case let .mesh(mesh): mesh
        case let .primitive(shape): EditableMesh.primitive(shape)
        case let .drawing(recipe) where recipe.style != .ink: MeshBuilder.mesh(from: DrawingMesher.mesh(for: recipe))
        default: nil
        }
    }

    public static func canModel(_ object: SceneObject) -> Bool {
        switch object.kind {
        case .mesh, .primitive: true
        case let .drawing(recipe): recipe.style != .ink
        default: false
        }
    }

    /// The mesh as modelling sees it: in the object's space with its scale baked in, so typed lengths are real
    /// lengths. Objects with children keep their scale (baking it would resize the children).
    static func bakedMesh(of object: SceneObject) -> (mesh: EditableMesh, bakesScale: Bool)? {
        guard let mesh = editableMesh(of: object) else { return nil }
        let scale = object.transform.scale
        guard object.children.isEmpty, !scale.isApproximately(.one, tolerance: 1e-12) else { return (mesh, false) }
        return (mesh.scaled(by: scale), true)
    }

    /// Replaces an object's shape with a mesh (and its scale with 1 when the mesh has it baked in).
    static func setMesh(_ id: ObjectID, _ mesh: EditableMesh, bakesScale: Bool) -> [EditCommand] {
        var commands: [EditCommand] = [.setKind(id, .mesh(mesh))]
        if bakesScale { commands.append(.setProperties([PropertyChange(object: id, key: .scale, value: .vec3(.one))])) }
        return commands
    }

    /// Turns a shape into an editable mesh (Model ▸ Make editable; the other tools do it on the way).
    public static func makeEditable(_ id: ObjectID, in scene: Scene) throws(Failure) -> EditCommand {
        guard let object = scene.objects[id], let (mesh, bakes) = bakedMesh(of: object) else { throw .notEditable }
        return .batch("Make editable", setMesh(id, mesh, bakesScale: bakes))
    }

    // MARK: Push/pull

    /// Moves a face of an object along its normal by an exact distance (metres); under live symmetry its mirror image
    /// moves with it.
    public static func pushPull(_ id: ObjectID, face: Int, distance: Double, in scene: Scene) throws(Failure) -> EditCommand {
        try pushPull(id, faces: [face], distance: distance, in: scene)
    }

    // MARK: Booleans

    /// Combines solids into the first one (which keeps its name, look and place); the others are removed.
    public static func boolean(_ ids: [ObjectID], _ operation: MeshBoolean.Operation, in scene: Scene) throws(Failure) -> EditCommand {
        let solids = ids.compactMap { id -> (ObjectID, EditableMesh)? in
            guard let object = scene.objects[id], let mesh = editableMesh(of: object) else { return nil }
            return (id, mesh.transformed(by: scene.worldTransform(of: id)))
        }
        guard solids.count >= 2, let keeper = solids.first else { throw .needsTwoSolids }
        var result = keeper.1
        do {
            for other in solids.dropFirst() {
                result = try MeshBoolean.combine(result, other.1, operation)
            }
        } catch {
            throw .boolean(error)
        }
        let local = result.untransformed(by: scene.worldTransform(of: keeper.0))
        return .batch(operation.label, [.setKind(keeper.0, .mesh(local)), .delete(solids.dropFirst().map(\.0))])
    }

    // MARK: Sketches

    /// Pulls a sketch region into a solid (positive distance) or cuts it into the object it was drawn on (negative).
    /// On empty space it makes a new object; the region's curves are used up.
    public static func pull(sketch id: ObjectID, region index: Int, distance: Double, in scene: Scene,
                            ids: inout IDFactory) throws(Failure) -> EditCommand {
        guard let object = scene.objects[id], case let .sketch(sketch) = object.kind else { throw .noSuchRegion }
        let regions = sketch.regions
        guard regions.indices.contains(index), abs(distance) > 1e-9 else { throw .noSuchRegion }
        let region = regions[index]
        var commands: [EditCommand] = []
        if let target = sketch.target, let targetObject = scene.objects[target], let mesh = editableMesh(of: targetObject) {
            let world = scene.worldTransform(of: target)
            let solid = mesh.transformed(by: world)
            let prism = distance > 0 ? sketch.prism(of: region, distance: distance) : cutPrism(sketch, region, depth: distance, into: solid)
            do {
                let combined = try MeshBoolean.combine(solid, prism, distance > 0 ? .union : .subtract)
                commands.append(.setKind(target, .mesh(combined.untransformed(by: world))))
            } catch {
                throw .boolean(error)
            }
        } else {
            let prism = sketch.prism(of: region, distance: distance)
            commands.append(.insert(SceneFragment(object: newSolid(prism, id: ids.next())), parent: nil, index: nil))
        }
        let rest = sketch.removing(region)
        commands.append(rest.curves.isEmpty ? .delete([id]) : .setKind(id, .sketch(rest)))
        return .batch(distance > 0 || sketch.target == nil ? "Pull" : "Cut", commands)
    }

    /// The prism a cut removes. It starts a hair above the surface, and when its far end lands exactly on a face of
    /// the solid (cutting "through"), it goes a hair past it: faces exactly on top of each other would leave a skin.
    static func cutPrism(_ sketch: Sketch, _ region: SketchRegion, depth: Double, into solid: EditableMesh) -> EditableMesh {
        let epsilon = max(solid.bounds?.size.maxComponent ?? 1, 1e-3) * 1e-6
        let reachesFace = solid.vertices.contains { abs(sketch.plane.height(of: $0) - depth) < epsilon }
        return sketch.prism(of: region, from: epsilon, to: reachesFace ? depth - epsilon : depth)
    }

    /// A new object holding a world-space mesh, its pivot at the middle of its base.
    static func newSolid(_ world: EditableMesh, id: ObjectID) -> SceneObject {
        let bounds = world.bounds ?? Bounds(min: .zero, max: .zero)
        let pivot = Vec3(bounds.center.x, bounds.min.y, bounds.center.z)
        let local = EditableMesh(vertices: world.vertices.map { $0 - pivot }, faces: world.faces)
        return SceneObject(id: id, name: "Solid", kind: .mesh(local), transform: Transform(position: pivot))
    }

    /// A new sketch object on a plane (drawn on `target`'s face, or on a guide plane when nil).
    public static func newSketch(on plane: PlaneFrame, curves: [SketchCurve], target: ObjectID?, id: ObjectID) -> SceneObject {
        SceneObject(id: id, name: "Sketch", kind: .sketch(Sketch(plane: plane, curves: curves, target: target)))
    }

    /// Adds curves to a sketch (one undo step per drawn curve).
    public static func addCurves(_ curves: [SketchCurve], to id: ObjectID, in scene: Scene) -> EditCommand? {
        guard let object = scene.objects[id], case var .sketch(sketch) = object.kind else { return nil }
        sketch.curves += curves
        return .batch("Draw", [.setKind(id, .sketch(sketch))])
    }
}
