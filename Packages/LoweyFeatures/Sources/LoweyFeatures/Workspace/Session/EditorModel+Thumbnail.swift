import CoreGraphics
import Foundation
import LoweyCore
import UIKit

/// The Home card: a still of the work view, and the model slowly turning in its Look.
extension EditorModel {
    /// What the card is drawn from, taken while the project is still open (the drawing happens after it closes).
    struct CardJob {
        var document: Document
        var viewpoint: Viewpoint
        var projectURL: URL
    }

    var cardJob: CardJob {
        CardJob(document: document, viewpoint: stage?.viewpoint ?? baseScene.viewpoint, projectURL: projectURL)
    }

    func writeProjectThumbnail() async {
        await app.drawCard(cardJob)
    }
}

extension AppModel {
    /// Draws a project's card once: the still first (so the card is never blank), then the turntable, cached in the
    /// package as a GIF. Cards only play it while they're on screen.
    func drawCard(_ job: EditorModel.CardJob) async {
        let catalog = library.catalog
        guard let still = try? await thumbnailer.still(job.document, viewpoint: job.viewpoint, width: 640, height: 360, catalog: catalog,
                                                       models: library.models) else { return }
        let image = UIImage(cgImage: still)
        if let png = image.pngData() { try? projectStore.writeThumbnail(png, for: job.projectURL) }
        setThumbnail(image, for: job.document.project.id)
        let turntable = await (try? thumbnailer.turntable(job.document, pitch: job.viewpoint.pitch, catalog: catalog, models: library.models)) ?? []
        let loopURL = job.projectURL.appendingPathComponent(Thumbnailer.loopFile)
        if turntable.count > 1 {
            try? Thumbnailer.writeLoop(turntable, to: loopURL)
        } else {
            try? FileManager.default.removeItem(at: loopURL)
        }
        cardRevisions[job.document.project.id, default: 0] += 1
    }
}
