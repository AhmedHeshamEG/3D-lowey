import Foundation
import LoweyCore
import LoweyEngine

/// The layers of an object's paint (Paint ▸ Colour ▸ Layers): each change is one undo step.
extension EditorModel {
    func addPaintLayer(to id: ObjectID) {
        guard let object = baseScene.objects[id], let paint = object.paint else { return }
        guard let (command, layer) = PaintOperations.addLayer(to: paint, above: paintLayer(of: object)?.id, object: id) else {
            app.show("An object holds up to \(ObjectPaint.maximumLayers) layers")
            return
        }
        if perform(command) { colourPaint.layers[id] = layer }
    }

    func duplicatePaintLayer(_ layer: String, of id: ObjectID) {
        guard let paint = baseScene.objects[id]?.paint else { return }
        guard let (command, copy) = PaintOperations.duplicateLayer(layer, in: paint, object: id) else {
            app.show("An object holds up to \(ObjectPaint.maximumLayers) layers")
            return
        }
        if perform(command) { colourPaint.layers[id] = copy }
    }

    func deletePaintLayer(_ layer: String, of id: ObjectID) {
        guard let paint = baseScene.objects[id]?.paint, let command = PaintOperations.deleteLayer(layer, from: paint, object: id) else { return }
        if perform(command), colourPaint.layers[id] == layer { colourPaint.layers[id] = nil }
    }

    /// Moves a layer up (+1) or down (−1) the stack.
    func movePaintLayer(_ layer: String, of id: ObjectID, by offset: Int) {
        guard let paint = baseScene.objects[id]?.paint, let index = paint.layerIndex(layer),
              let command = PaintOperations.moveLayer(layer, to: index + offset, in: paint, object: id) else { return }
        perform(command)
    }

    /// A layer's name, opacity, blend or visibility. Dragging the opacity slider is one undo step (`gesture`).
    func updatePaintLayer(_ layer: String, of id: ObjectID, gesture: String? = nil, _ change: (inout PaintLayer) -> Void) {
        guard let paint = baseScene.objects[id]?.paint, let command = PaintOperations.update(layer, in: paint, object: id, change) else { return }
        perform(command, coalesceKey: gesture)
    }

    func clearPaintLayer(_ layer: String, of id: ObjectID) {
        guard let paint = baseScene.objects[id]?.paint, let current = paint.layer(layer),
              let command = PaintOperations.clear(current, object: id) else { return }
        perform(command)
    }

    /// Merges a layer into the one under it (their pixels composited off the main thread, then one step).
    func mergePaintLayerDown(_ layer: String, of id: ObjectID) {
        guard let paint = baseScene.objects[id]?.paint, let index = paint.layerIndex(layer), index > 0 else { return }
        let file = paintFiles
        let folder = assetsFolder
        Task {
            let merged = await Task.detached(priority: .userInitiated) { () -> (command: EditCommand, files: PaintOperations.Files)? in
                var pictures: [String: RGBAImage] = [:]
                for name in Set(paint.layers[index - 1 ... index].flatMap(\.tiles.values)) {
                    pictures[name] = file(name).flatMap { try? PNGCodec.decode($0) }
                }
                return PaintOperations.mergeDown(layer, in: paint, object: id, image: { layer in
                    PaintComposer.layerImage(layer, surface: paint.surface) { pictures[$0] }
                }, encode: PaintPixels.png)
            }.value
            guard let merged else { return }
            do {
                try await Self.write(merged.files, to: folder)
            } catch {
                app.show("Couldn't save the merged layer: \(error.localizedDescription)", kind: .error)
                return
            }
            guard baseScene.objects[id]?.paint == paint else { return }
            if perform(merged.command) { colourPaint.layers[id] = paint.layers[index - 1].id }
        }
    }

    /// Takes the paint off an object entirely (one step; undo brings it back).
    func removePaint(from id: ObjectID) {
        guard baseScene.objects[id]?.paint != nil else { return }
        perform(.setPaint(id, nil))
        colourPaint.layers[id] = nil
    }
}
