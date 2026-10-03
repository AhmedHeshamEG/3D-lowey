import CoreGraphics
import Foundation
import HmmPerception
import LoweyCore
import LoweyEngine
import UIKit

/// Perception for the AI: `observe` and `contact_sheet` on the open scene (or on a proposed change before it's
/// applied), rendered exactly like the export.
extension EditorModel {
    /// An export session over `document` (the open one by default) with the project's media.
    func makeObserveSession(_ document: Document? = nil) throws -> ExportSession {
        let exporter = try ExportSession(document: document ?? session.document, catalog: library.catalog, device: RenderDevice.sharedDevice(),
                                         models: library.models)
        let assets = assetsFolder
        exporter.mediaURL = { file in
            let url = assets.appendingPathComponent(file)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        exporter.stillImage = { name in UIImage(contentsOfFile: assets.appendingPathComponent(name).path)?.cgImage }
        return exporter
    }

    /// Looks at the shot at `time` (the playhead by default) of `document` (the open scene by default).
    func observe(_ document: Document? = nil, at time: Double? = nil, views: Set<ObserveView> = [.camera], framing: Framing? = nil,
                 subject: String? = nil, longSide: Int = 1280) async throws -> ShotObservation {
        refreshOperationsLibrary()
        let session = try makeObserveSession(document)
        return try await session.observe(at: time ?? self.time, framing: framing ?? deliveryFraming, longSide: min(max(longSide, 320), 2048),
                                         views: views, subject: subject, library: library.manifest)
    }

    func contactSheet(from start: Double?, to end: Double?, frames: Int, subject: String?) async throws -> ContactSheetObservation {
        refreshOperationsLibrary()
        let session = try makeObserveSession()
        let from = max(start ?? 0, 0)
        let to = min(end ?? timeline.duration, timeline.duration)
        return try await session.contactSheet(from: from, to: max(to, from), frames: min(max(frames, 2), 12), framing: deliveryFraming,
                                              subject: subject, library: library.manifest)
    }

    /// A small picture of what a script would make (the proposal card's thumbnail), before anything is applied.
    func previewThumbnail(of document: Document) async -> UIImage? {
        guard let session = try? makeObserveSession(document),
              let image = try? await session.image(at: time, framing: deliveryFraming, longSide: 480) else { return nil }
        return UIImage(cgImage: image)
    }
}

extension CGImage {
    /// PNG bytes (for the bridge).
    var pngData: Data? { UIImage(cgImage: self).pngData() }
}
