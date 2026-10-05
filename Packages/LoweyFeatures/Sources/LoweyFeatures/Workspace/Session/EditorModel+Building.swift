import Foundation
import HmmDesign
import LoweyCore

/// Selecting and building: tap to select (groups first, Lego-style), add shapes / lights / cameras / library items,
/// duplicate, copy & paste, group, array, scatter, align, colour, lock, hide, rename, reparent, swap.
extension EditorModel {
    // MARK: Selection

    func select(_ id: ObjectID?, additive: Bool = false) {
        guard let id else {
            if !additive { selection = [] }
            return
        }
        let target = topSelectable(for: id)
        if additive {
            if let index = selection.firstIndex(of: target) { selection.remove(at: index) } else { selection.append(target) }
        } else {
            selection = [target]
        }
        HmmHaptics.play(.selection)
    }

    func setSelection(_ ids: [ObjectID]) {
        selection = ids.filter { scene.objects[$0] != nil }
    }

    func selectAll() {
        setSelection(baseScene.roots.filter { scene.objects[$0]?.isVisible ?? false })
    }

    /// Everything like the selection: the same primitive shape, model, build or kind.
    func selectSimilar() {
        guard let reference = singleSelection ?? selectedObjects.first else { return }
        let similar = baseScene.orderedIDs().filter { id in
            guard let object = scene.objects[id], scene.isEffectivelyVisible(id) else { return false }
            return object.kind.similar(to: reference.kind)
        }
        setSelection(similar)
        app.show("\(similar.count) like “\(reference.name)”")
    }

    /// The highest ancestor that isn't selected yet (tap again to dig into a group).
    private func topSelectable(for id: ObjectID) -> ObjectID {
        let chain = [id] + scene.ancestors(of: id)
        if let selectedIndex = chain.firstIndex(where: { selection.contains($0) }), selectedIndex > 0 {
            return chain[selectedIndex - 1]
        }
        return chain.last ?? id
    }

    // MARK: Adding

    func refreshOperationsLibrary() {
        operations.bounds = SceneBounds(library: library.manifest)
    }

    func addPrimitive(_ shape: PrimitiveShape, at screenPoint: CGPoint? = nil) {
        refreshOperationsLibrary()
        var object = factory.primitive(shape, color: currentColor)
        object.name = ObjectFactory.uniqueName(shape.displayName, in: scene)
        if newShapeScale != 1 { object.transform.scale *= newShapeScale }
        object = operations.placeOnGround(object, at: dropPoint(at: screenPoint))
        if screenPoint == nil { object = operations.nudgedToFreeSpot(object, in: scene) }
        if perform(operations.add(object)) { select(object.id) }
    }

    func addLight(_ type: LightType) {
        var object = factory.light(type, at: dropPoint() + Vec3(0, type == .directional ? 4 : 1.5, 0))
        object.name = ObjectFactory.uniqueName(object.name, in: scene)
        if perform(operations.add(object)) { select(object.id) }
    }

    /// A camera where the view is now; the first one becomes the shot camera.
    func addCamera() {
        guard let stage else { return }
        var object = factory.camera(at: stage.viewpoint)
        object.name = ObjectFactory.uniqueName("Camera", in: scene)
        if perform(.batch("Add camera", [operations.add(object), .setActiveCamera(object.id)])) {
            select(object.id)
            app.show("Camera saved from this view")
        }
    }

    func place(_ item: LibraryItem, at screenPoint: CGPoint? = nil) {
        refreshOperationsLibrary()
        switch item {
        case let .asset(asset):
            if case let .swap(target) = libraryPurpose {
                perform(operations.swap(target, with: asset, in: scene))
                libraryPurpose = .place
                openPanel = nil
                app.show("Swapped for \(asset.name)")
            } else {
                placeObject(factory.asset(asset), named: asset.name, at: screenPoint)
            }
        case let .prefab(prefab):
            placeObject(factory.prefabInstance(prefab), named: prefab.name, at: screenPoint)
        case let .look(saved):
            applyLook(saved.look, sceneOnly: document.scene.look != nil)
            app.show("“\(saved.name)” applied")
        case let .script(script):
            openPanel = nil
            openScript(script)
        }
        library.markUsed(item)
    }

    private func placeObject(_ made: SceneObject, named name: String, at screenPoint: CGPoint?) {
        var object = made
        object.name = ObjectFactory.uniqueName(name, in: scene)
        object = operations.placeOnGround(object, at: dropPoint(at: screenPoint))
        if screenPoint == nil { object = operations.nudgedToFreeSpot(object, in: scene) }
        if perform(operations.add(object)) { select(object.id) }
    }

    /// A library tile dropped on the stage.
    func placeLibraryItem(id: String, at point: CGPoint) {
        guard let item = LibrarySearch.items(in: library.manifest, filter: .all).first(where: { $0.id == id }) else { return }
        let purpose = libraryPurpose
        libraryPurpose = .place
        place(item, at: point)
        libraryPurpose = purpose
    }

    // MARK: Editing the selection

    func duplicateSelection() {
        refreshOperationsLibrary()
        // Right next to the original, so duplicating again builds a row.
        let offset = selectionBounds.map { Vec3(max($0.size.x, 0.2) + 0.1, 0, 0) } ?? Vec3(0.5, 0, 0.5)
        guard let (command, roots) = operations.duplicate(selection, in: scene, offset: offset) else { return }
        if perform(command) { setSelection(roots) }
    }

    func deleteSelection() {
        guard perform(operations.delete(selection, in: scene)) else {
            if !selection.isEmpty { app.show("Locked objects can't be deleted") }
            return
        }
        selection = []
    }

    func copySelection() {
        clipboard = FragmentTools.extract(selection, from: scene)
        app.show("Copied")
    }

    var canPaste: Bool { clipboard != nil }

    func paste() {
        guard let clipboard else { return }
        var ids = IDFactory.random
        var (copy, _) = FragmentTools.reidentified(clipboard, ids: &ids)
        copy = FragmentTools.transformRoots(copy) { transform in
            var moved = transform
            moved.position += Vec3(0.5, 0, 0.5)
            return moved
        }
        if perform(.insert(copy, parent: nil, index: nil)) { setSelection(copy.roots) }
    }

    func groupSelection() {
        refreshOperationsLibrary()
        guard let (command, groupID) = operations.group(selection, in: scene) else { return }
        if perform(command) { setSelection([groupID]) }
    }

    func ungroupSelection() {
        guard let object = singleSelection, object.kind == .group else { return }
        let children = object.children
        if perform(operations.ungroup(object.id, in: scene)) { setSelection(children) }
    }

    func dropSelectionToGround() {
        refreshOperationsLibrary()
        perform(operations.dropToGround(selection, in: scene))
    }

    func array(_ layout: ArrayLayout) {
        refreshOperationsLibrary()
        guard let source = selection.first, let (command, group) = operations.array(source, layout: layout, in: scene) else { return }
        if perform(command) { setSelection([group]) }
    }

    /// The object's own width plus a small gap.
    var arrayStep: Double {
        guard let bounds = selectionBounds else { return 1 }
        return (max(bounds.size.x, bounds.size.z) * 1.15 * 100).rounded() / 100
    }

    func scatterSelection(center: Vec3, radius: Double) {
        refreshOperationsLibrary()
        guard let source = selection.first else { return }
        var settings = ScatterSettings(count: scatter.count, radius: max(radius, 0.3), scaleMin: 1 - scatter.scaleVariation,
                                       scaleMax: 1 + scatter.scaleVariation, spacing: scatter.spacing, seed: UInt64.random(in: 1 ... UInt64.max))
        settings.rotationJitter = 360
        guard let (command, group) = operations.scatter(source, center: center, settings: settings, in: scene) else { return }
        if perform(command) {
            setSelection([group])
            let placed = scene.objects[group]?.children.count ?? 0
            app.show(placed < scatter.count ? "Placed \(placed) (the area is too small for \(scatter.count))" : "Scattered \(placed)")
        }
    }

    func align(_ axis: CoreAxis, _ mode: AlignMode) {
        refreshOperationsLibrary()
        perform(operations.align(selection, axis: axis, mode: mode, in: scene))
    }

    func distribute(_ axis: CoreAxis) {
        refreshOperationsLibrary()
        perform(operations.distribute(selection, axis: axis, in: scene))
    }

    func setColor(_ color: ColorValue?) {
        currentColor = color ?? currentColor
        guard !selection.isEmpty else { return }
        perform(operations.setColor(selection, color, in: scene))
    }

    func setProperty(_ key: PropertyKey, _ value: PropertyValue?, coalesce: String? = nil) {
        perform(.setProperties(selection.map { PropertyChange(object: $0, key: key, value: value) }), coalesceKey: coalesce)
    }

    func toggleLock(_ id: ObjectID) {
        guard let object = scene.objects[id] else { return }
        perform(operations.setFlag([id], key: .locked, !object.isLocked))
    }

    func toggleVisible(_ id: ObjectID) {
        guard let object = scene.objects[id] else { return }
        perform(operations.setFlag([id], key: .visible, !object.isVisible))
    }

    func rename(_ id: ObjectID, to name: String) {
        guard !name.isEmpty, scene.objects[id]?.name != name else { return }
        perform(.rename(id, name))
    }

    func reparent(_ ids: [ObjectID], to parent: ObjectID?) {
        perform(operations.reparent(ids, to: parent, in: scene))
    }

    /// Opens the library to swap the selected blockout for a model.
    func beginSwap() {
        guard let target = selection.first else { return }
        libraryPurpose = .swap(target)
        modelPage = .library
        openPanel = .model
    }
}

extension ObjectKind {
    /// Kinds "Select similar" groups together.
    func similar(to other: ObjectKind) -> Bool {
        switch (self, other) {
        case let (.primitive(a), .primitive(b)): a == b
        case let (.asset(a), .asset(b)): a == b
        case let (.prefab(a), .prefab(b)): a == b
        case (.light, .light), (.camera, .camera), (.drawing, .drawing), (.text, .text), (.overlay, .overlay),
             (.particles, .particles), (.card, .card), (.mesh, .mesh), (.sketch, .sketch), (.dimension, .dimension), (.group, .group): true
        default: false
        }
    }
}
