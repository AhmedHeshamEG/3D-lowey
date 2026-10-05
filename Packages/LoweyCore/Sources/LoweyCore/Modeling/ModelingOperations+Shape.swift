import Foundation

public extension PropertyKey {
    /// Live symmetry of a modelled object: "x", "y" or "z" (the plane through its pivot square to that axis). Every
    /// Model edit keeps the side it touched and makes the other side its mirror image.
    static let symmetry: PropertyKey = "symmetry"
}

/// The shape operations (bevel, round, inset, shell, mirror, symmetry), each one labelled undo step.
public extension ModelingOperations {
    enum ShapeFailure: Error, Equatable, CustomStringConvertible {
        case inset(Inset.Failure)
        case bevel(EdgeBevel.Failure)
        case shell(Shell.Failure)
        case architecture(Architecture.Failure)

        public var description: String {
            switch self {
            case let .inset(failure): failure.description
            case let .bevel(failure): failure.description
            case let .shell(failure): failure.description
            case let .architecture(failure): failure.description
            }
        }
    }

    static func symmetry(of object: SceneObject) -> SymmetryAxis? {
        object[.symmetry]?.stringValue.flatMap(SymmetryAxis.init(rawValue:))
    }

    // MARK: Faces and edges

    /// Moves faces along their normals together (several picks, and their mirror images under symmetry).
    static func pushPull(_ id: ObjectID, faces: [Int], distance: Double, in scene: Scene) throws(Failure) -> EditCommand {
        guard let object = scene.objects[id], let (mesh, bakes) = bakedMesh(of: object) else { throw .notEditable }
        let moved: EditableMesh
        do {
            moved = try PushPull.apply(mesh, faces: faces, distance: distance)
        } catch {
            throw .pushPull(error)
        }
        let result = try keepingSymmetry(moved, of: object, near: centroid(ofFaces: faces, in: mesh), bakesScale: bakes)
        return .batch("Push/pull", setMesh(id, result, bakesScale: bakes))
    }

    static func inset(_ id: ObjectID, faces: Set<Int>, distance: Double, in scene: Scene) throws(Failure) -> EditCommand {
        try reshape(id, label: "Inset", in: scene, near: { centroid(ofFaces: Array(faces), in: $0) }) { mesh throws(Failure) in
            do throws(Inset.Failure) {
                return try Inset.apply(mesh, faces: faces, distance: distance)
            } catch {
                throw .shape(.inset(error))
            }
        }
    }

    static func bevel(_ id: ObjectID, edges: Set<MeshEdge>, size: Double, style: EdgeBevel.Style, in scene: Scene) throws(Failure) -> EditCommand {
        try reshape(id, label: style.label, in: scene, near: { mesh in
            let ends = edges.flatMap { [$0.a, $0.b] }.filter(mesh.vertices.indices.contains)
            return ends.isEmpty ? nil : ends.reduce(Vec3.zero) { $0 + mesh.vertices[$1] } / Double(ends.count)
        }) { mesh throws(Failure) in
            do throws(EdgeBevel.Failure) {
                return try EdgeBevel.apply(mesh, edges: edges, size: size, style: style)
            } catch {
                throw .shape(.bevel(error))
            }
        }
    }

    /// Hollows the object to walls `thickness` thick, leaving `open` faces off.
    static func shell(_ id: ObjectID, thickness: Double, open: Set<Int>, in scene: Scene) throws(Failure) -> EditCommand {
        try reshape(id, label: "Shell", in: scene, near: { open.isEmpty ? nil : centroid(ofFaces: Array(open), in: $0) }) { mesh throws(Failure) in
            do throws(Shell.Failure) {
                return try Shell.apply(mesh, thickness: thickness, open: open)
            } catch {
                throw .shape(.shell(error))
            }
        }
    }

    // MARK: Mirror and symmetry

    /// A mirror image of the object across a plane in the world. When it touches the plane (a half modelled against
    /// a face), the two halves join into one solid; otherwise the mirror image is a new object beside it.
    static func mirror(_ id: ObjectID, across plane: MirrorPlane, in scene: Scene, ids: inout IDFactory) throws(Failure) -> EditCommand {
        guard let object = scene.objects[id], let local = editableMesh(of: object) else { throw .notEditable }
        let world = scene.worldTransform(of: id)
        let solid = local.transformed(by: world)
        let mirrored = MeshMirror.reflected(solid, across: plane)
        let size = max(solid.bounds?.size.maxComponent ?? 1, 1e-3)
        let nearest = solid.vertices.map { abs(plane.height(of: $0)) }.min() ?? .infinity
        if nearest <= size * 1e-6 {
            do {
                let joined = try MeshBoolean.combine(solid, mirrored, .union)
                return .batch("Mirror", [.setKind(id, .mesh(joined.untransformed(by: world)))])
            } catch {
                throw .boolean(error)
            }
        }
        var copy = newSolid(mirrored, id: ids.next())
        copy.name = object.name
        let placement: Set<PropertyKey> = [.position, .rotation, .scale, .symmetry]
        for (key, value) in object.properties where !placement.contains(key) {
            copy[key] = value
        }
        return .batch("Mirror", [.insert(SceneFragment(object: copy), parent: nil, index: nil)])
    }

    /// Switches live symmetry on (about one axis) or off. Switching on moves the pivot to the middle of the shape on
    /// that axis, so the plane runs through it, and makes the shape symmetric right away, keeping the bigger side.
    static func setSymmetry(_ id: ObjectID, _ axis: SymmetryAxis?, in scene: Scene) throws(Failure) -> EditCommand {
        guard let object = scene.objects[id], let (mesh, bakes) = bakedMesh(of: object) else { throw .notEditable }
        guard let axis else {
            return .batch("Symmetry off", [.setProperties([PropertyChange(object: id, key: .symmetry, value: nil)])])
        }
        let bounds = mesh.bounds ?? Bounds(min: .zero, max: .zero)
        let shift = axis.normal * bounds.center.dot(axis.normal)
        let centred = EditableMesh(vertices: mesh.vertices.map { $0 - shift }, faces: mesh.faces)
        let plane = axis.plane
        let positive = centred.vertices.map { max(plane.height(of: $0), 0) }.reduce(0, +)
        let negative = centred.vertices.map { max(-plane.height(of: $0), 0) }.reduce(0, +)
        let symmetric: EditableMesh
        do {
            symmetric = try MeshMirror.symmetrize(centred, across: plane, keepPositive: positive >= negative)
        } catch {
            throw .boolean(error)
        }
        var commands = setMesh(id, symmetric, bakesScale: bakes)
        // The shape moved by -shift inside the object, so the object moves by +shift: nothing moves on screen.
        var transform = object.transform
        let scale = bakes ? Vec3.one : transform.scale
        transform.position += transform.rotation.act(shift.scaled(by: scale))
        commands.append(.setProperties([
            PropertyChange(object: id, key: .position, value: .vec3(transform.position)),
            PropertyChange(object: id, key: .symmetry, value: .enumeration(axis.rawValue))
        ]))
        return .batch("Symmetry", commands)
    }

    // MARK: Helpers

    /// Runs a mesh operation on the object's baked mesh and keeps its symmetry, as one labelled step.
    internal static func reshape(_ id: ObjectID, label: String, in scene: Scene, near: (EditableMesh) -> Vec3?,
                                 _ operation: (EditableMesh) throws(Failure) -> EditableMesh) throws(Failure) -> EditCommand {
        guard let object = scene.objects[id], let (mesh, bakes) = bakedMesh(of: object) else { throw .notEditable }
        let changed = try operation(mesh)
        let result = try keepingSymmetry(changed, of: object, near: near(mesh), bakesScale: bakes)
        return .batch(label, setMesh(id, result, bakesScale: bakes))
    }

    /// Under live symmetry, the side the edit touched is kept and mirrored onto the other.
    internal static func keepingSymmetry(_ mesh: EditableMesh, of object: SceneObject, near point: Vec3?,
                                         bakesScale: Bool) throws(Failure) -> EditableMesh {
        guard let axis = symmetry(of: object) else { return mesh }
        // The plane runs through the pivot in the object's space; a baked scale doesn't move it.
        let plane = axis.plane
        let keepPositive = point.map { plane.height(of: $0) >= -1e-12 } ?? true
        do {
            return try MeshMirror.symmetrize(mesh, across: plane, keepPositive: keepPositive)
        } catch {
            throw .boolean(error)
        }
    }

    internal static func centroid(ofFaces faces: [Int], in mesh: EditableMesh) -> Vec3? {
        let valid = faces.filter(mesh.faces.indices.contains)
        guard !valid.isEmpty else { return nil }
        return valid.reduce(Vec3.zero) { $0 + mesh.centroid(of: $1) } / Double(valid.count)
    }
}
