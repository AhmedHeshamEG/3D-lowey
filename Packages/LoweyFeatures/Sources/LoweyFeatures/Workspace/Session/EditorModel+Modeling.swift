import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// The Model tool (Model ▸ Edit): pick faces, edges and corners, booleans on solids, and the state the stage's marks
/// and floating numbers read. Sketching is `EditorModel+Sketching`, push/pull `EditorModel+PushPull`.
extension EditorModel {
    /// Starts the Model tool in a mode (from the Shape page or the bottom bar).
    func startModeling(_ mode: ModelingMode) {
        HmmHaptics.play(.selection)
        modeling.pending = nil
        modeling.offsetSource = nil
        modeling.measure = []
        modeling.build = []
        modeling.snapMark = nil
        if mode.pickMode != modeling.mode.pickMode { modeling.elements = nil }
        modeling.mode = mode
        if tool != .model { tool = .model }
        if let kind = mode.sketchKind { app.show(String.LocalizationValue(kind.hint(points: 0))) }
        if let build = mode.buildTool { app.show(String.LocalizationValue(build.hint)) }
        if mode == .measure { app.show("Tap the first point") }
        refreshModelOverlay()
    }

    /// Leaves the Model tool (the bar's ✕): back to selecting objects.
    func stopModeling() {
        tool = .select
    }

    /// Called whenever the stage tool changes.
    func modelToolChanged() {
        guard tool != .model else { return }
        cancelPushPull()
        modeling = ModelingState(mode: modeling.mode)
        stage?.showModelOverlay([])
    }

    func modelCameraMoved() {
        refreshModelOverlay()
        if modeling.hasPick || modeling.lastCurve != nil || modeling.pending != nil { viewRevision &+= 1 }
    }

    /// A tap with the Model tool: draw with a sketch shape, else pick a face, edge or corner.
    func modelTap(at point: CGPoint) {
        switch modeling.mode {
        case .sketch: sketchTap(at: point)
        case .pick: pickElement(at: point, additive: false)
        case .measure: measureTap(at: point)
        case .build: buildTap(at: point)
        }
    }

    // MARK: Lengths

    func format(_ metres: Double) -> String {
        units.format(metres)
    }

    /// A typed length in metres (`25mm`, `2*12`…), or nil with a message.
    func parseLength(_ text: String) -> Double? {
        do {
            return try LengthExpression.evaluate(text, defaultUnit: units)
        } catch {
            app.show("Type a length, like 25 or 2*12 or 1.5 cm", kind: .error)
            HmmHaptics.play(.error)
            return nil
        }
    }

    // MARK: Modelled objects

    /// An object's editable mesh and its world transform, as the stage shows it now.
    func modelMesh(of id: ObjectID) -> (mesh: EditableMesh, world: CoreTransform)? {
        guard let object = scene.objects[id], let mesh = ModelingOperations.editableMesh(of: object) else { return nil }
        return (mesh, scene.worldTransform(of: id))
    }

    /// The selected objects that can be modelled (booleans need two or more).
    var modelableSelection: [ObjectID] {
        selection.filter { id in baseScene.objects[id].map(ModelingOperations.canModel) ?? false }
    }

    /// The single selected object, when it's a shape that isn't an editable mesh yet, or a placed library model.
    var convertibleSelection: ObjectID? {
        guard let object = singleSelection else { return nil }
        if object.kind.assetID != nil { return object.id }
        guard ModelingOperations.canModel(object) else { return nil }
        if case .mesh = object.kind { return nil }
        return object.id
    }

    func makeSelectionEditable() {
        guard let id = convertibleSelection else { return }
        if baseScene.objects[id]?.kind.assetID != nil {
            makeModelEditable(id)
        } else {
            runModeling { try ModelingOperations.makeEditable(id, in: baseScene) }
        }
    }

    func combineSelection(_ operation: MeshBoolean.Operation) {
        let ids = modelableSelection
        guard ids.count >= 2 else {
            app.show("Select two or more shapes first (touch and hold to add one)")
            return
        }
        if runModeling({ try ModelingOperations.boolean(ids, operation, in: baseScene) }) {
            setSelection([ids[0]])
        }
    }

    /// Performs a modelling command, or explains why it couldn't be done.
    @discardableResult
    func runModeling(_ make: () throws -> EditCommand) -> Bool {
        do {
            let command = try make()
            guard perform(command) else { return false }
            HmmHaptics.play(.commit)
            return true
        } catch {
            let message = (error as? ModelingOperations.Failure)?.description ?? String(describing: error)
            app.show(String.LocalizationValue(message), kind: .error)
            HmmHaptics.play(.error)
            return false
        }
    }

    // MARK: Picking faces, edges and corners

    /// A tap in a pick mode: the face, edge or corner under it (added to the pick with `additive`).
    func pickElement(at point: CGPoint, additive: Bool) {
        guard let stage, let mode = modeling.mode.pickMode else { return }
        if let region = sketchRegion(at: point) {
            selectRegion(region)
            return
        }
        guard let (id, _) = stage.pickObject(at: point), let (mesh, world) = modelMesh(of: id), let ray = stage.worldRay(at: point) else {
            if !additive { clearModelPick() }
            return
        }
        let local = Ray(origin: world.inverseApply(to: ray.origin), direction: world.inverseApplyDirection(ray.direction))
        let screen = Vec2(Double(point.x), Double(point.y))
        guard let picked = MeshPicking.pick(local, screenPoint: screen, mode: mode, in: mesh, project: { [weak stage] in
            stage?.screenPoint(of: world.apply(to: $0)).map { Vec2(Double($0.x), Double($0.y)) }
        }) else { return }
        if selection != [id] { setSelection([id]) }
        var elements = picked
        if additive, modeling.target == id, var current = modeling.elements, current.mode == mode {
            // Touch and hold adds what's under the finger, or takes it out again.
            current.vertices.formSymmetricDifference(picked.vertices)
            current.edges.formSymmetricDifference(picked.edges)
            current.faces.formSymmetricDifference(picked.faces)
            elements = current
        }
        modeling.region = nil
        modeling.pull = nil
        modeling.target = id
        modeling.elements = elements
        HmmHaptics.play(.selection)
    }

    /// A Pencil loop in a pick mode: everything of the target (or the selected object) inside it that faces you.
    func pickElements(inLoop loop: [CGPoint]) {
        guard let stage, let mode = modeling.mode.pickMode, let id = modeling.target ?? singleSelection?.id,
              let (mesh, world) = modelMesh(of: id) else { return }
        let eye = Vec3(stage.camera.position)
        let caught = MeshSelection.lasso(loop.map { Vec2(Double($0.x), Double($0.y)) }, mode: mode, in: mesh, project: { [weak stage] in
            stage?.screenPoint(of: world.apply(to: $0)).map { Vec2(Double($0.x), Double($0.y)) }
        }, facing: { face in
            let normal = world.applyDirection(mesh.normal(of: face))
            return normal.dot(eye - world.apply(to: mesh.centroid(of: face))) > 0
        })
        guard !caught.isEmpty else { return }
        if selection != [id] { setSelection([id]) }
        modeling.region = nil
        modeling.target = id
        modeling.elements = caught
        HmmHaptics.play(.selection)
    }

    func clearModelPick() {
        cancelPushPull()
        modeling.clearPick()
        modeling.target = nil
    }

    func growPick() { changePick { $0.grown(in: $1) } }
    func shrinkPick() { changePick { $0.shrunk(in: $1) } }
    func selectSimilarElements() { changePick { $0.similar(in: $1) } }

    private func changePick(_ change: (MeshSelection, EditableMesh) -> MeshSelection) {
        guard let id = modeling.target, let elements = modeling.elements, let (mesh, _) = modelMesh(of: id) else { return }
        modeling.elements = change(elements, mesh)
        HmmHaptics.play(.selection)
    }

    /// After an edit the mesh may be renumbered: keep only picks that still exist.
    func validateModelPick() {
        if let id = modeling.target {
            if let (mesh, _) = modelMesh(of: id) {
                modeling.elements = modeling.elements?.valid(in: mesh)
            } else {
                modeling.target = nil
                modeling.elements = nil
            }
        }
        if let region = modeling.region, sketch(region.sketch)?.regions.indices.contains(region.index) != true { modeling.region = nil }
        if let curve = modeling.lastCurve, sketch(curve.sketch)?.curves.indices.contains(curve.index) != true { modeling.lastCurve = nil }
    }

    /// The one face picked (push/pull drags it), in its object.
    var pickedFace: (object: ObjectID, face: Int)? {
        guard let id = modeling.target, let elements = modeling.elements, elements.mode == .face, elements.faces.count == 1,
              let face = elements.faces.first else { return nil }
        return (id, face)
    }

    /// What the inspector says about the pick: "Face · 800 mm²", "2 edges · 40 mm".
    var pickSummary: String? {
        if let region = modeling.region, let sketch = sketch(region.sketch), sketch.regions.indices.contains(region.index) {
            return String(localized: "Area · \(formatArea(sketch.regions[region.index].area))")
        }
        guard let id = modeling.target, let elements = modeling.elements, !elements.isEmpty, let (local, world) = modelMesh(of: id) else { return nil }
        let mesh = local.transformed(by: world)
        switch elements.mode {
        case .face:
            let area = elements.faces.filter(mesh.faces.indices.contains).reduce(0) { $0 + mesh.area(of: $1) }
            return elements.faces.count == 1 ? String(localized: "Face · \(formatArea(area))")
                : String(localized: "\(elements.faces.count) faces · \(formatArea(area))")
        case .edge:
            let length = elements.edges.reduce(0) { $0 + mesh.length(of: $1) }
            return elements.edges.count == 1 ? String(localized: "Edge · \(format(length))")
                : String(localized: "\(elements.edges.count) edges · \(format(length))")
        case .vertex:
            return String(localized: "\(elements.vertices.count) corners")
        }
    }

    /// An area in the project's units ("800 mm²"): `format` divides by the unit once, so it's handed area / unit.
    func formatArea(_ squareMetres: Double) -> String {
        units.format(squareMetres / units.metres, symbol: false) + " \(units.symbol)²"
    }

    /// The selection's size in the project's units ("40 × 10 × 20 mm"): width, height, depth of its world bounds.
    var selectionSizeText: String? {
        // Core's exact bounds first: the renderer's may still be a frame behind an edit.
        guard let bounds = operations.bounds.worldBounds(of: selection, in: scene) ?? selectionBounds else { return nil }
        let size = bounds.size
        let parts = [size.x, size.y, size.z].map { units.format($0, symbol: false) }
        return "\(parts.joined(separator: " × ")) \(units.symbol)"
    }
}
