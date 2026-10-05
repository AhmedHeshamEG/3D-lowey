import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore

/// Ink strokes: Pencil lines in 3D on the drawing guide. Strokes join the selected ink drawing (a new one starts when
/// nothing ink is selected), the eraser splits them, and picked strokes can be moved, smoothed, thickened or deleted.
/// Every edit is one `setKind` command, one undo step per gesture.
extension EditorModel {
    /// The ink drawing new strokes join and the stroke tools edit: the single selected ink drawing.
    var activeInk: SceneObject? {
        guard selection.count == 1, let id = selection.first, let object = baseScene.objects[id], object.isInk,
              !baseScene.isEffectivelyLocked(id) else { return nil }
        return object
    }

    func inkRecipe(_ object: SceneObject) -> DrawingRecipe? {
        if case let .drawing(recipe) = object.kind, recipe.style == .ink { return recipe }
        return nil
    }

    // MARK: Drawing

    /// A finished stroke from points and pressures alone (scripts and tests; the Pencil gives full samples).
    func commitInkStroke(points: [Vec3], pressures: [Double]) {
        let samples = points.enumerated().map { index, point in
            BrushInput(point: point, pressure: pressures.indices.contains(index) ? pressures[index] : 1, time: Double(index) / 240)
        }
        commitInkStroke(samples, seed: Self.strokeSeed())
    }

    /// The path the current ink brush makes of Pencil samples (world points on the guide): the same function draws
    /// the live stroke and the one that's kept.
    func inkPath(_ samples: [BrushInput<Vec3>]) -> BrushPath<Vec3> {
        BrushStroker.path(samples, brush: currentBrush(for: .ink), size: ink.width, streamline: ink.smoothing * 0.6,
                          minimumSpacing: ink.width * 0.25)
    }

    /// A finished Pencil stroke: joins the selected ink drawing, or starts one. With the brush's first use in this
    /// project it's one undo step.
    func commitInkStroke(_ samples: [BrushInput<Vec3>], seed: UInt64) {
        commitInkStrokes([samples], seed: seed)
    }

    /// A stroke and its symmetry copies (the guide plane's guide), as one undo step; each copy keeps its own seed.
    func commitInkStrokes(_ copies: [[BrushInput<Vec3>]], seed: UInt64) {
        let paths = copies.map(inkPath).filter { !$0.points.isEmpty }
        guard let first = paths.first else { return }
        let (key, brushCommand) = projectBrush(currentBrush(for: .ink))
        func stroke(_ path: BrushPath<Vec3>, index: Int, map: (Vec3) -> Vec3, scale: Double) -> DrawingRecipe.Stroke {
            DrawingRecipe.Stroke(points: path.points.map(map), widths: path.widths.map { $0 / scale }, alphas: path.alphas, brush: key,
                                 seed: seed &+ UInt64(index))
        }
        if let target = activeInk, var recipe = inkRecipe(target) {
            let world = displayed.scene.worldTransform(of: target.id)
            let scale = max(abs(world.scale.x), abs(world.scale.y), abs(world.scale.z), 1e-4)
            for (index, path) in paths.enumerated() {
                recipe = InkEditing.appending(stroke(path, index: index, map: { world.inverseApply(to: $0) }, scale: scale), to: recipe)
            }
            performStroke(.setKind(target.id, .drawing(recipe)), brush: brushCommand)
            return
        }
        let origin = first.points[0]
        let strokes = paths.enumerated().map { stroke($1, index: $0, map: { $0 - origin }, scale: 1) }
        // Facing the camera it was drawn from (the ribbons' plane when there's no camera: export, picking).
        let normal = stage.map { (Vec3($0.camera.position) - origin).normalized } ?? .unitZ
        var object = factory.drawing(DrawingRecipe(style: .ink, strokes: strokes, normal: normal), transform: CoreTransform(position: origin),
                                     color: currentColor)
        if ink.opacity < 0.999 { object[.opacity] = .float(ink.opacity) }
        object.name = ObjectFactory.uniqueName(object.name, in: scene)
        if performStroke(operations.add(object), brush: brushCommand) { selection = [object.id] }
    }

    // MARK: Erasing

    /// Erases the ink points within the eraser around `screenPoints` (one undo step per gesture). With an ink drawing
    /// selected only that one is erased, else every visible ink drawing.
    func eraseInk(at screenPoints: [CGPoint], gesture: String) {
        guard let stage, !screenPoints.isEmpty else { return }
        let radius = CGFloat(ink.eraserRadius)
        for object in inkTargets() {
            guard let recipe = inkRecipe(object) else { continue }
            let world = displayed.scene.worldTransform(of: object.id)
            let erased = InkEditing.erasing(recipe) { strokeIndex, pointIndex in
                guard let screen = stage.screenPoint(of: world.apply(to: recipe.strokes[strokeIndex].points[pointIndex])) else { return false }
                return screenPoints.contains { hypot($0.x - screen.x, $0.y - screen.y) <= radius }
            }
            guard erased != recipe else { continue }
            if erased.strokes.isEmpty {
                perform(operations.delete([object.id], in: baseScene), coalesceKey: gesture)
            } else {
                perform(.setKind(object.id, .drawing(erased)), coalesceKey: gesture)
            }
        }
        inkStrokes = []
    }

    private func inkTargets() -> [SceneObject] {
        if let active = activeInk { return [active] }
        return baseScene.orderedIDs().compactMap { id in
            guard let object = baseScene.objects[id], object.isInk, displayed.scene.isEffectivelyVisible(id),
                  !baseScene.isEffectivelyLocked(id) else { return nil }
            return object
        }
    }

    // MARK: Picking strokes

    /// Picks strokes: a tap picks the strokes passing near it, a loop picks the strokes it encloses. The drawing they
    /// belong to becomes the selection.
    func selectInkStrokes(path: [CGPoint]) {
        guard let stage, let first = path.first else { return }
        let isTap = path.allSatisfy { hypot($0.x - first.x, $0.y - first.y) < 12 }
        for object in inkTargets() {
            guard let recipe = inkRecipe(object) else { continue }
            let world = displayed.scene.worldTransform(of: object.id)
            let picked = InkEditing.strokes(of: recipe) { point in
                guard let screen = stage.screenPoint(of: world.apply(to: point)) else { return false }
                return isTap ? hypot(screen.x - first.x, screen.y - first.y) < 16 : Self.polygon(path, contains: screen)
            }
            guard !picked.isEmpty else { continue }
            selection = [object.id]
            inkStrokes = picked
            HmmHaptics.play(.selection)
            return
        }
        inkStrokes = []
    }

    /// Whether a screen point is on one of the picked strokes (a drag starting there moves them).
    func isOnPickedStroke(_ point: CGPoint) -> Bool {
        selectedStrokePaths().contains { path in path.contains { hypot($0.x - point.x, $0.y - point.y) < 22 } }
    }

    /// The picked strokes on screen (drawn highlighted over the stage).
    func selectedStrokePaths() -> [[CGPoint]] {
        guard let stage, let object = activeInk, let recipe = inkRecipe(object), !inkStrokes.isEmpty else { return [] }
        let world = displayed.scene.worldTransform(of: object.id)
        return inkStrokes.sorted().compactMap { index in
            guard recipe.strokes.indices.contains(index) else { return nil }
            return recipe.strokes[index].points.compactMap { stage.screenPoint(of: world.apply(to: $0)) }
        }
    }

    static func polygon(_ polygon: [CGPoint], contains point: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: Editing picked strokes

    /// Moves the picked strokes by a world offset (a drag; coalesced into one undo step).
    func moveInkStrokes(byWorld offset: Vec3, gesture: String) {
        editInkStrokes(gesture: gesture) { recipe, world in
            let local = world.inverseApply(to: offset) - world.inverseApply(to: .zero)
            return InkEditing.moving(inkStrokes, by: local, in: recipe)
        }
    }

    func smoothInkStrokes() {
        editInkStrokes { recipe, _ in InkEditing.smoothing(inkStrokes, by: 0.6, in: recipe) }
    }

    func scaleInkStrokes(by factor: Double) {
        editInkStrokes { recipe, _ in InkEditing.scalingWidths(inkStrokes, by: factor, in: recipe) }
    }

    func deleteInkStrokes() {
        guard let object = activeInk, let recipe = inkRecipe(object), !inkStrokes.isEmpty else { return }
        let remaining = InkEditing.removing(inkStrokes, from: recipe)
        if remaining.strokes.isEmpty {
            perform(operations.delete([object.id], in: baseScene))
        } else {
            perform(.setKind(object.id, .drawing(remaining)))
        }
        inkStrokes = []
        HmmHaptics.play(.commit)
    }

    private func editInkStrokes(gesture: String? = nil, _ change: (DrawingRecipe, CoreTransform) -> DrawingRecipe) {
        guard let object = activeInk, let recipe = inkRecipe(object), !inkStrokes.isEmpty else { return }
        let edited = change(recipe, displayed.scene.worldTransform(of: object.id))
        guard edited != recipe else { return }
        perform(.setKind(object.id, .drawing(edited)), coalesceKey: gesture)
    }

    /// The selected ink drawing's opacity (the sidebar slider; one undo step per drag).
    func setInkOpacity(_ value: Double) {
        guard let object = activeInk else { return }
        perform(.setProperties([PropertyChange(object: object.id, key: .opacity, value: .float(value))]), coalesceKey: "ink-opacity")
    }

    /// The selected ink drawing writes itself on from the playhead (the Typewriter preset on ink).
    func writeOnInk() {
        guard activeInk != nil else { return }
        applyPreset(.typewriter)
    }
}
