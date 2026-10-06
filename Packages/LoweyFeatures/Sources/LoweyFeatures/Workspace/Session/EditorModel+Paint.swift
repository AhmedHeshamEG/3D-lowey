import CoreGraphics
import Foundation
import LoweyCore
import LoweyEngine

/// Paint ▸ Colour (CONTEXT §10.4): making an object ready to paint (laid flat by xatlas, a placed model's own colours
/// baked into a first layer), strokes committed as tiles in the order they were painted, fill, the eyedropper and
/// pictures projected from the camera. Every change is one command; the tiles' files are written first.
extension EditorModel {
    /// The project's paint files, readable from any thread (the renderer, exports).
    var paintFiles: @Sendable (String) -> Data? {
        let folder = assetsFolder
        return { name in try? Data(contentsOf: folder.appendingPathComponent(name)) }
    }

    /// The object Paint ▸ Colour works on: the last one painted while it's still there, else the selection's first
    /// paintable object.
    var paintTarget: SceneObject? {
        if let id = colourPaint.target, let object = displayed.scene.objects[id], object.isPaintable { return object }
        return selection.lazy.compactMap { self.displayed.scene.objects[$0] }.first(where: \.isPaintable)
    }

    /// The layer the Pencil paints on: the one chosen for the object, else its top layer.
    func paintLayer(of object: SceneObject) -> PaintLayer? {
        guard let paint = object.paint else { return nil }
        if let chosen = colourPaint.layers[object.id], let layer = paint.layer(chosen) { return layer }
        return paint.layers.last
    }

    func choosePaintLayer(_ id: String, on object: ObjectID) {
        colourPaint.layers[object] = id
    }

    // MARK: Getting ready

    /// Makes an object paintable (in the background: unwrapping a big model takes a moment). Placed models keep their
    /// own colours as a first layer, "Model", with an empty layer above for the paint.
    func preparePaint(_ id: ObjectID) {
        guard let object = baseScene.objects[id], object.isPaintable, object.paint == nil, !colourPaint.preparing.contains(id) else { return }
        colourPaint.target = id
        colourPaint.preparing.insert(id)
        app.show("Getting \(object.name) ready to paint")
        let folder = assetsFolder
        Task {
            let made = await makePaintable(object)
            colourPaint.preparing.remove(id)
            guard let made else { return }
            do {
                try await Self.write(made.files, to: folder)
            } catch {
                app.show("Couldn't save the painting's files: \(error.localizedDescription)", kind: .error)
                return
            }
            guard baseScene.objects[id]?.paint == nil else { return }
            perform(.batch("Start painting", [.setPaint(id, made.paint)]))
            colourPaint.layers[id] = made.paint.layers.last?.id
        }
    }

    /// The first paint of an object and its files, made off the main thread.
    private func makePaintable(_ object: SceneObject) async -> (paint: ObjectPaint, files: PaintOperations.Files)? {
        if let assetID = object.kind.assetID {
            guard let asset = library.catalog.manifest.asset(assetID), let model = await library.models.load(asset, catalog: library.catalog) else {
                app.show("This model hasn't loaded yet", kind: .error)
                return nil
            }
            guard let merged = AssetPaint.mergedMesh(model) else {
                app.show("This model moves with a skeleton: painting on characters arrives with rigging", kind: .error)
                return nil
            }
            return await Task.detached(priority: .userInitiated) { Self.paintableModel(model, merged: merged) }.value
        }
        guard let mesh = PaintSource.mesh(of: object) else { return nil }
        let stretch = PaintSource.stretch(of: object)
        let result = await Task.detached(priority: .userInitiated) { () -> (ObjectPaint, PaintOperations.Files)? in
            guard let prepared = try? PaintOperations.prepare(mesh: mesh, stretch: stretch, keepOwnUVs: false) else { return nil }
            return (prepared.paint, prepared.files)
        }.value
        if result == nil { app.show("This shape couldn't be laid flat for painting", kind: .error) }
        return result.map { (paint: $0.0, files: $0.1) }
    }

    /// A placed model's surface: its own uvs when they're clean, its colours baked into "Model", "Layer 1" on top.
    nonisolated static func paintableModel(_ model: ImportedModel, merged: MeshData) -> (paint: ObjectPaint, files: PaintOperations.Files)? {
        guard var (paint, unwrap, files) = try? PaintOperations.prepare(mesh: merged, keepOwnUVs: true) else { return nil }
        let baked = AssetPaint.bake(model, merged: merged, unwrap: unwrap, size: paint.surface.size)
        var base = PaintLayer(id: "model", name: "Model")
        for (index, tile) in PaintComposer.tiles(of: baked, surface: paint.surface) {
            let png = PaintPixels.png(tile)
            let name = PaintFiles.tileName(for: png)
            files[name] = png
            base[index] = name
        }
        paint.layers.insert(base, at: 0)
        return (paint, files)
    }

    nonisolated static func write(_ files: PaintOperations.Files, to folder: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            for (name, data) in files {
                let url = folder.appendingPathComponent(name)
                guard !FileManager.default.fileExists(atPath: url.path) else { continue }
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
        }.value
    }

    // MARK: Strokes

    /// A finished stroke's tiles become files, then one `paintTiles` command. Strokes commit strictly in the order they
    /// were painted (a later stroke's tiles hold the earlier one's paint).
    func commitPaintStroke(_ pending: Task<PaintedTiles?, Never>) {
        let previous = paintCommits
        let folder = assetsFolder
        paintCommits = Task {
            await previous?.value
            guard let painted = await pending.value else { return }
            let files = await Task.detached(priority: .userInitiated) {
                painted.tiles.map { index, tile -> (PaintTileIndex, String, Data) in
                    let png = PaintPixels.png(tile)
                    return (index, PaintFiles.tileName(for: png), png)
                }
            }.value
            do {
                try await Self.write(Dictionary(files.map { ($0.1, $0.2) }) { first, _ in first }, to: folder)
            } catch {
                app.show("Couldn't save the stroke: \(error.localizedDescription)", kind: .error)
                return
            }
            let changes = files.sorted { $0.0 < $1.0 }.map { PaintTileChange(layer: painted.layer, tile: $0.0, file: $0.1) }
            guard baseScene.objects[painted.object]?.paint?.layer(painted.layer) != nil else { return }
            stage?.renderer.adoptPaint(object: painted.object, layer: painted.layer, changes: changes)
            perform(.paintTiles(painted.object, changes))
        }
    }

    /// The path the paint brush makes of samples (stage points), its size and opacity folded in.
    func paintPath(_ samples: [BrushInput<Vec2>]) -> BrushPath<Vec2> {
        BrushStroker.path(samples, brush: currentBrush(for: .paint), size: colourPaint.size, opacity: colourPaint.opacity, minimumSpacing: 1.5)
    }

    /// The colour painted (sRGB).
    var paintColor: RGBA {
        let color = currentColor.resolved(in: look.palette)
        return RGBA(color.r, color.g, color.b, 1)
    }

    // MARK: Fill, eyedropper, pictures

    /// Fills the target's layer with the current colour (the whole layer: what isn't seen on the model is never drawn).
    func fillPaint(_ id: ObjectID) {
        guard let object = baseScene.objects[id], let paint = object.paint, let layer = paintLayer(of: object) else { return }
        let fill = PaintOperations.fill(paintColor, layer: layer, surface: paint.surface, object: id, encode: PaintPixels.png)
        let folder = assetsFolder
        Task {
            do {
                try await Self.write(fill.files, to: folder)
            } catch {
                app.show("Couldn't save the fill: \(error.localizedDescription)", kind: .error)
                return
            }
            perform(fill.command)
        }
    }

    /// Takes the painted colour under a stage point (the object's own colour where nothing is painted).
    func pickPaintColour(at point: CGPoint) {
        guard let stage, let picked = stage.pickObject(at: point), let object = displayed.scene.objects[picked.0] else { return }
        let local = displayed.scene.worldTransform(of: picked.0).inverseApply(to: picked.1.point)
        var color = object.color?.resolved(in: look.palette) ?? .blockout
        if let paint = object.paint, let picked = PaintSampler.color(at: local, of: object, paint: paint, file: paintFiles) {
            color = picked
        }
        currentColor = .rgba(RGBA(color.r, color.g, color.b, 1))
        app.show("Picked a colour")
    }

    /// Projects the placed picture from the camera onto the target's layer, then commits it like a stroke.
    func projectPicture() {
        guard let picture = colourPaint.picture, let stage, let object = paintTarget, let layer = paintLayer(of: object) else { return }
        paintStrokes += 1
        let color = RGBA(1, 1, 1, colourPaint.opacity)
        stage.showLivePaint(LivePaint(object: object.id, layer: layer.id, stroke: paintStrokes, source: .picture(picture.image, rect: picture.rect),
                                      color: color, erases: false, pixelsPerPoint: Double(stage.contentScaleFactor)))
        // The frame that draws it runs before the read-back is encoded (both on the main thread, in this order).
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let stage = self.stage else { return }
                stage.draw()
                stage.showLivePaint(nil)
                if let pending = stage.finishPaintStroke() { self.commitPaintStroke(pending) }
                self.colourPaint.picture = nil
            }
        }
    }
}

extension EditorModel {
    /// A tap with Paint ▸ Colour: fill, take a colour, or choose (and ready) the object to paint.
    func paintTap(at point: CGPoint) {
        if colourPaint.mode == .pick {
            pickPaintColour(at: point)
            return
        }
        guard let stage, let hit = stage.pickObject(at: point), let object = displayed.scene.objects[hit.0] else { return }
        guard object.isPaintable else {
            app.show("This can't be painted (try a shape, a modelled part or a placed model)")
            return
        }
        colourPaint.target = object.id
        select(object.id)
        guard object.paint != nil else {
            preparePaint(object.id)
            return
        }
        if colourPaint.mode == .fill { fillPaint(object.id) }
    }

    /// Forgets what the GPU holds for painted layers, so they're drawn again from the document's tiles.
    func revertPaint() {
        stage?.renderer.forgetPaint()
        stage?.redraw()
    }
}

/// The painted colour at a point of an object (the eyedropper): the closest point of its paint surface, every
/// visible layer at that texel composited.
enum PaintSampler {
    static func color(at local: Vec3, of object: SceneObject, paint: ObjectPaint, file: (String) -> Data?) -> RGBA? {
        guard let unwrap = file(paint.surface.unwrap).flatMap({ try? PaintUnwrap(data: $0) }) else { return nil }
        var point = SIMD3<Float>(Float(local.x), Float(local.y), Float(local.z))
        if let factor = PaintSource.toObjectSpace(of: object) { point /= factor }
        guard let uv = PaintSampler.uv(of: point, on: unwrap) else { return nil }
        let size = paint.surface.size
        let x = min(max(Int(uv.x * Float(size)), 0), size - 1), y = min(max(Int(uv.y * Float(size)), 0), size - 1)
        let tile = PaintTileIndex(column: x / PaintSurface.tileSize, row: y / PaintSurface.tileSize)
        var single = paint
        single.surface = PaintSurface(size: PaintSurface.tileSize, unwrap: paint.surface.unwrap, mesh: paint.surface.mesh)
        for index in single.layers.indices {
            let name = paint.layers[index][tile]
            single.layers[index].tiles = name.map { ["0,0": $0] } ?? [:]
        }
        let pictures = Dictionary(single.layers.compactMap { layer in layer.tiles["0,0"].map { ($0, file($0)) } }) { first, _ in first }
            .compactMapValues { $0.flatMap { try? PNGCodec.decode($0) } }
        let composite = PaintComposer.composite(single) { layer in
            PaintComposer.layerImage(layer, surface: single.surface) { pictures[$0] }
        }
        let pixel = composite.pixel(x % PaintSurface.tileSize, y % PaintSurface.tileSize)
        return pixel.a > 0.01 ? pixel : nil
    }

    /// The uv of the surface point closest to `point` (the unwrap's own positions).
    static func uv(of point: SIMD3<Float>, on unwrap: PaintUnwrap) -> SIMD2<Float>? {
        var best: (distance: Float, uv: SIMD2<Float>)?
        for face in 0 ..< unwrap.triangleCount {
            let i = (Int(unwrap.indices[face * 3]), Int(unwrap.indices[face * 3 + 1]), Int(unwrap.indices[face * 3 + 2]))
            let a = unwrap.positions[i.0], b = unwrap.positions[i.1], c = unwrap.positions[i.2]
            let center = (a + b + c) / 3
            let reach = max((a - center).length, (b - center).length, (c - center).length)
            guard (point - center).length <= reach + (best?.distance ?? .greatestFiniteMagnitude) else { continue }
            let (weights, distance) = Self.closest(point, a, b, c)
            if distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (distance, unwrap.uvs[i.0] * weights.x + unwrap.uvs[i.1] * weights.y + unwrap.uvs[i.2] * weights.z)
            }
        }
        return best?.uv
    }

    /// The closest point of a triangle as barycentric weights (projected and clamped), and its distance.
    static func closest(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> (SIMD3<Float>, Float) {
        let ab = b - a, ac = c - a, ap = p - a
        let d00 = (ab * ab).sum(), d01 = (ab * ac).sum(), d11 = (ac * ac).sum()
        let d20 = (ap * ab).sum(), d21 = (ap * ac).sum()
        let denominator = d00 * d11 - d01 * d01
        guard abs(denominator) > 1e-12 else { return (SIMD3<Float>(1, 0, 0), (p - a).length) }
        var v = (d11 * d20 - d01 * d21) / denominator, w = (d00 * d21 - d01 * d20) / denominator
        v = min(max(v, 0), 1)
        w = min(max(w, 0), 1 - v)
        let weights = SIMD3<Float>(1 - v - w, v, w)
        return (weights, (a * weights.x + b * weights.y + c * weights.z - p).length)
    }
}

private extension SIMD3 where Scalar == Float {
    var length: Float { (self * self).sum().squareRoot() }
}
