import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// Where the selection sits on the stage, so the inspector can float beside it without covering it. Measured at once
/// when the selection changes, and once edits or the camera pause (not every frame of a drag or an orbit: the
/// inspector glides over when things come to rest).
extension EditorModel {
    /// With no delay given: at once for a new selection, after a short pause for the same one being edited.
    func refreshSelectionScreenRect(after delay: Double? = nil) {
        selectionRectTask?.cancel()
        guard !selection.isEmpty else {
            if selectionScreenRect != nil { selectionScreenRect = nil }
            measuredSelection = []
            return
        }
        let delay = delay ?? (selection == measuredSelection ? 0.12 : 0)
        measuredSelection = selection
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
