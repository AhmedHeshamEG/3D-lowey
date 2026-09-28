import AVFoundation
import Foundation
import LoweyCore
import LoweyRender
import SwiftUI
import UniformTypeIdentifiers

/// Pictures and videos in the shot (screenshots, clips, Manim renders): copied into the project, shown as overlays.
extension EditorModel {
    var assetsFolder: URL { projectURL.appendingPathComponent(ProjectLayout.assetsFolder) }

    /// A media file of the project (nil if it isn't there).
    func mediaURL(_ file: String) -> URL? {
        let url = assetsFolder.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Copies a picture or video into the project and puts it in the frame at `at` (default: the playhead).
    @discardableResult
    func importMedia(_ source: URL, at start: Double? = nil) async -> ObjectID? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
            let file = uniqueMediaName(source.lastPathComponent)
            let destination = assetsFolder.appendingPathComponent(file)
            try FileManager.default.copyItem(at: source, to: destination)
            let isVideo = UTType(filenameExtension: destination.pathExtension)?.conforms(to: .movie) ?? false
            if isVideo {
                let asset = AVURLAsset(url: destination)
                let duration = try await asset.load(.duration).seconds
                var aspect = 16.0 / 9
                if let track = try await asset.loadTracks(withMediaType: .video).first {
                    let natural = try await track.load(.naturalSize)
                    let size = try await natural.applying(track.load(.preferredTransform))
                    aspect = abs(size.width) / max(abs(size.height), 1)
                }
                return addMediaOverlay(OverlayRecipe(shape: .image, video: file, videoStart: start ?? time, videoDuration: duration), aspect: aspect)
            }
            let aspect = UIImage(contentsOfFile: destination.path).map { $0.size.width / max($0.size.height, 1) } ?? 1
            return addMediaOverlay(OverlayRecipe(shape: .image, image: file), aspect: aspect)
        } catch {
            app.show("Couldn't add \(source.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// A media overlay filling most of the frame's height, centred, on top.
    private func addMediaOverlay(_ recipe: OverlayRecipe, aspect _: Double) -> ObjectID? {
        let layer = Double(baseScene.objects.values.filter(\.kind.isOverlay).count)
        let name = recipe.video ?? recipe.image ?? "Media"
        let object = SceneObject(id: .make(), name: ObjectFactory.uniqueName((name as NSString).deletingPathExtension, in: scene), kind: .overlay(recipe),
                                 transform: CoreTransform(position: Vec3(0, 0, layer), scale: Vec3(2.6, 2.6, 1)))
        guard perform(operations.add(object)) else { return nil }
        select(object.id)
        app.show(recipe.video != nil ? "Plays from \(TimelineDrawer.format(recipe.videoStart ?? 0)). Drag it in the frame; pinch to size it"
            : "Drag it in the frame; pinch to size it")
        return object.id
    }

    private func uniqueMediaName(_ original: String) -> String {
        let base = (original as NSString).deletingPathExtension
        let ext = (original as NSString).pathExtension
        var candidate = original
        var index = 2
        while FileManager.default.fileExists(atPath: assetsFolder.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(index).\(ext)"
            index += 1
        }
        return candidate
    }
}
