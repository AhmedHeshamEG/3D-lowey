import Foundation
import LoweyEngine
import UIKit

/// The hovering Pencil (CONTEXT §4.4): with the hover setting on, a small point sits exactly under the tip for every
/// tool, drawn by the stage in the frame it renders; with it off there is no mark at all. The brush outline appears
/// only while the brush is being resized (under the tip, or in the middle of the stage when the Pencil is away).
extension EditorModel {
    /// The Pencil moved over the stage (nil: it left, or the setting is off).
    func setHover(_ point: CGPoint?) {
        hoverPoint = point
        updatePencilPointer()
    }

    /// A brush-size slider started or stopped moving.
    func setBrushResizing(_ resizing: Bool) {
        brushResizing = resizing
        updatePencilPointer()
    }

    func updatePencilPointer() {
        guard let stage else { return }
        let size = stage.bounds.size
        let outline = brushResizing ? brushRadiusPoints : nil
        guard let location = hoverPoint ?? (brushResizing ? CGPoint(x: size.width / 2, y: size.height / 2) : nil) else {
            stage.showPointer(nil)
            return
        }
        stage.showPointer(PencilPointer(at: location, in: size, outline: outline))
    }

    /// The current brush's radius on screen, in points.
    var brushRadiusPoints: Double {
        switch tool {
        case .draw: max(6, 40 * draw.width / 0.05) * 0.3
        case .ink: ink.mode == .erase ? ink.eraserRadius : max(ink.width * 2000, 1)
        case .flipbook: flipbook.mode == .erase ? flipbook.eraserRadius : flipbook.width
        case .shadowBrush: max(10, shadowBrush.radius * 120)
        default: 6
        }
    }
}
