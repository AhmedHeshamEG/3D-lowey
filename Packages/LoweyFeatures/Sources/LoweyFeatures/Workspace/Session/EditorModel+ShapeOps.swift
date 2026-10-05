import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// The shape operations on the Model tool's pick (bevel, round, inset, shell), mirror and symmetry, checking a part
/// for printing, and making a placed library model editable. Each is done at once with a sensible size; its size then
/// floats beside it, and typing a new one does it again from the same pick.
extension EditorModel {
    /// A first size that suits the project's units: a millimetre in a print project, five centimetres in a room.
    var defaultShapeSize: Double {
        switch units {
        case .millimetre: 0.001
        case .centimetre: 0.005
        case .metre: 0.05
        case .inch: 0.0254 / 8
        case .foot: 0.0254
        }
    }

    func bevelPick(_ style: EdgeBevel.Style) {
        guard let id = modeling.target, let elements = modeling.elements, elements.mode == .edge, !elements.edges.isEmpty,
              let (mesh, world) = modelMesh(of: id) else {
            app.show("Pick the edges first (Edge, then tap or loop them)")
            return
        }
        let ends = elements.edges.flatMap { [$0.a, $0.b] }.filter(mesh.vertices.indices.contains)
        let anchor = world.apply(to: ends.reduce(Vec3.zero) { $0 + mesh.vertices[$1] } / Double(max(ends.count, 1)))
        runShapeOp(ShapeOpRecord(kind: style == .round ? .round : .bevel, object: id, edges: elements.edges, amount: defaultShapeSize,
                                 anchor: anchor), fitting: true)
    }

    func insetPick() {
        guard let (id, faces, anchor) = pickedFaces() else { return }
        runShapeOp(ShapeOpRecord(kind: .inset, object: id, faces: faces, amount: defaultShapeSize * 2, anchor: anchor), fitting: true)
    }

    /// Hollows the picked object; picked faces are left open.
    func shellPick() {
        guard let id = modeling.target ?? singleSelection.flatMap({ ModelingOperations.canModel($0) ? $0.id : nil }) else {
            app.show("Select a solid first")
            return
        }
        let faces = modeling.elements?.mode == .face && modeling.target == id ? modeling.elements?.faces ?? [] : []
        let anchor = modelMesh(of: id).flatMap { mesh, world in mesh.bounds.map { world.apply(to: $0.center) } } ?? .zero
        runShapeOp(ShapeOpRecord(kind: .shell, object: id, faces: faces, amount: defaultShapeSize * 2, anchor: anchor), fitting: true)
    }

    private func pickedFaces() -> (ObjectID, Set<Int>, Vec3)? {
        guard let id = modeling.target, let elements = modeling.elements, elements.mode == .face, !elements.faces.isEmpty,
              let (mesh, world) = modelMesh(of: id) else {
            app.show("Pick the faces first (Face, then tap or loop them)")
            return nil
        }
        let valid = elements.faces.filter(mesh.faces.indices.contains)
        let centre = valid.reduce(Vec3.zero) { $0 + mesh.centroid(of: $1) } / Double(max(valid.count, 1))
        return (id, elements.faces, world.apply(to: centre))
    }

    /// Does the operation. With `fitting`, a first size that doesn't fit is halved (up to four times) before giving up.
    @discardableResult
    func runShapeOp(_ record: ShapeOpRecord, fitting: Bool = false) -> Bool {
        guard prepareShapeObject(record.object) else { return false }
        var attempt = record
        for _ in 0 ..< (fitting ? 5 : 1) {
            if let command = try? shapeCommand(attempt) {
                guard perform(command) else { return false }
                HmmHaptics.play(.commit)
                modeling.clearPick()
                modeling.target = record.object
                modeling.shapeOp = attempt
                viewRevision &+= 1
                return true
            }
            attempt.amount /= 2
        }
        // Explain with the size that was asked for.
        runModeling { try shapeCommand(record) }
        return false
    }

    /// A shape becomes an editable mesh (with its scale baked in) before its first shape operation, as push/pull does.
    private func prepareShapeObject(_ id: ObjectID) -> Bool {
        guard let object = baseScene.objects[id] else { return false }
        if case .mesh = object.kind { return true }
        return runModeling { try ModelingOperations.makeEditable(id, in: baseScene) }
    }

    private func shapeCommand(_ record: ShapeOpRecord) throws(ModelingOperations.Failure) -> EditCommand {
        switch record.kind {
        case .bevel: try ModelingOperations.bevel(record.object, edges: record.edges, size: record.amount, style: .chamfer, in: baseScene)
        case .round: try ModelingOperations.bevel(record.object, edges: record.edges, size: record.amount, style: .round, in: baseScene)
        case .inset: try ModelingOperations.inset(record.object, faces: record.faces, distance: record.amount, in: baseScene)
        case .shell: try ModelingOperations.shell(record.object, thickness: record.amount, open: record.faces, in: baseScene)
        }
    }

    /// A typed size for the operation just done: it's undone and done again from the same pick.
    func resizeShapeOp(to metres: Double) {
        guard var record = modeling.shapeOp, metres > 1e-9, session.undoLabel == record.kind.title else { return }
        undo()
        record.amount = metres
        if !runShapeOp(record) { modeling.shapeOp = nil }
    }

    // MARK: Mirror and symmetry

    /// Mirrors the selected solid across the picked face, or across the world's middle on an axis.
    func mirrorSelection(_ axis: SymmetryAxis?) {
        guard let id = modeling.target ?? modelableSelection.first else {
            app.show("Select a solid first")
            return
        }
        let plane: MirrorPlane = if axis == nil, let (face, mesh, world) = pickedFaceGeometry(of: id) {
            MirrorPlane(origin: world.apply(to: mesh.vertices[mesh.faces[face].outline[0]]), normal: world.applyDirection(mesh.normal(of: face)))
        } else {
            MirrorPlane(origin: .zero, normal: (axis ?? .x).normal)
        }
        var ids = operations.ids
        let done = runModeling { try ModelingOperations.mirror(id, across: plane, in: baseScene, ids: &ids) }
        operations.ids = ids
        if done { modeling.clearPick() }
    }

    private func pickedFaceGeometry(of id: ObjectID) -> (Int, EditableMesh, CoreTransform)? {
        guard let (target, face) = pickedFace, target == id, let (mesh, world) = modelMesh(of: id), mesh.faces.indices.contains(face) else { return nil }
        return (face, mesh, world)
    }

    /// The live symmetry of the selected solid.
    var selectionSymmetry: SymmetryAxis? {
        (modeling.target.flatMap { baseScene.objects[$0] } ?? singleSelection).flatMap(ModelingOperations.symmetry)
    }

    func setSymmetry(_ axis: SymmetryAxis?) {
        guard let id = modeling.target ?? modelableSelection.first else {
            app.show("Select a solid first")
            return
        }
        guard prepareShapeObject(id) else { return }
        if runModeling({ try ModelingOperations.setSymmetry(id, axis, in: baseScene) }) { modeling.clearPick() }
    }

    // MARK: 3D printing

    /// Checks the selected solids (or every solid) against the printer: watertight, walls, the bed.
    func checkForPrinting() {
        let ids = modelableSelection.isEmpty ? baseScene.objects.values.filter(ModelingOperations.canModel).map(\.id) : modelableSelection
        let meshes = ids.compactMap { ModelingOperations.worldMesh(of: $0, in: baseScene) }
        guard !meshes.isEmpty else {
            app.show("There's no solid to check yet")
            return
        }
        var report = PrintCheck.check(meshes[0], bed: precision.bed)
        for mesh in meshes.dropFirst() {
            let more = PrintCheck.check(mesh, bed: precision.bed)
            report.isWatertight = report.isWatertight && more.isWatertight
            report.openEdges += more.openEdges
            report.tangledEdges += more.tangledEdges
            report.insideOut = report.insideOut || more.insideOut
            report.volume += more.volume
            if !more.thinFaces.isEmpty { report.thinFaces.insert(-1) }
            report.thinnestWall = [report.thinnestWall, more.thinnestWall].compactMap(\.self).min()
        }
        if let bed = precision.bed, let all = meshes.compactMap(\.bounds).reduce(nil as Bounds?, { $0.map { $0.union($1) } ?? $1 }) {
            report.fitsBed = bed.fits(all)
        }
        precision.printChecked = ids
        precision.printReport = report
        HmmHaptics.play(report.isReady ? .commit : .selection)
    }

    /// Repairs every checked solid that isn't watertight (one undo step each), then checks again.
    func repairForPrinting() {
        let broken = precision.printChecked.filter { id in
            ModelingOperations.worldMesh(of: id, in: baseScene).map { !PrintCheck.check($0, bed: nil).isWatertight } ?? false
        }
        for id in broken {
            runModeling { try ModelingOperations.repairForPrinting(id, in: baseScene) }
        }
        checkForPrinting()
    }

    // MARK: Library models

    /// A placed library model taken apart into editable parts (keeping its glTF hierarchy and animation).
    func makeModelEditable(_ id: ObjectID) {
        guard let object = baseScene.objects[id], let assetID = object.kind.assetID, let asset = library.catalog.manifest.asset(assetID) else { return }
        var ids = operations.ids
        defer { operations.ids = ids }
        let url = library.catalog.fileURL(asset)
        var parts: SceneFragment?
        var tracks: [Track] = []
        do {
            if asset.format == .glb || asset.format == .gltf {
                let result = try GLTFSceneReader.read(Data(contentsOf: url), baseURL: url.deletingLastPathComponent(), ids: &ids)
                (parts, tracks) = (result.fragment, result.tracks)
            } else if let model = library.models.model(asset, catalog: library.catalog) {
                parts = try ModelingOperations.editableParts(of: model, ids: &ids)
            }
        } catch {
            let message = (error as? CustomStringConvertible)?.description ?? error.localizedDescription
            app.show(String.LocalizationValue(message), kind: .error)
            return
        }
        guard let parts, let command = ModelingOperations.replace(id, withParts: parts, tracks: tracks, in: baseScene), perform(command) else {
            app.show("That model can't be taken apart yet: it's still loading")
            return
        }
        HmmHaptics.play(.commit)
    }
}
