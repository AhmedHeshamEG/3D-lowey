import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// Where the selection sits on the stage, so the inspector can float beside it without covering it. Measured when the
/// selection or the scene changes, and once the camera settles (not every frame of an orbit: the inspector glides
/// over when the view comes to rest).
extension EditorModel {
    func refreshSelectionScreenRect(after delay: Double = 0) {
        selectionRectTask?.cancel()
        guard !selection.isEmpty else {
            if selectionScreenRect != nil { selectionScreenRect = nil }
            return
        }
        selectionRectTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            let rect = projectedSelectionRect()
            if rect != selectionScreenRect { selectionScreenRect = rect }
        }
    }

    /// The selection's box projected onto the stage (view points), clipped to the stage; nil when it's off screen.
    func projectedSelectionRect() -> CGRect? {
        guard let stage, let bounds = selectionBounds else { return nil }
        let corners = [bounds.min.x, bounds.max.x].flatMap { x in
            [bounds.min.y, bounds.max.y].flatMap { y in [bounds.min.z, bounds.max.z].map { z in Vec3(x, y, z) } }
        }
        guard let box = HmmFloatingPlacement.bounds(of: corners.compactMap { stage.screenPoint(of: $0) }) else { return nil }
        let visible = box.intersection(stage.bounds)
        return visible.isNull || visible.isEmpty ? nil : visible
    }
}

/// The open project is presented over Home by identity (one editor per opened project).
extension EditorModel: Identifiable {}
