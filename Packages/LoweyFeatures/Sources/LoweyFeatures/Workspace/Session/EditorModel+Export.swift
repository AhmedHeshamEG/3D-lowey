import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine
import Photos
import UIKit

/// Export: video (verified), PNG stills and sequences, GIF loops, 3D files and captions, on the stage's renderer.
/// It runs in the background (the stage stays usable), keeps going when the app leaves the screen, and reports its
/// progress to the Live Activity.
extension EditorModel {
    var isExporting: Bool { exportProgress != nil }

    /// Starts an export (one at a time).
    func startExport(_ kind: ExportKind, settings: ExportSettings, title: String) {
        guard exportTask == nil else { return }
        pause()
        exportProgress = 0
        exportResults = []
        let id = UUID().uuidString
        let reporter = app.exportReporter
        let background = BackgroundExport()
        background.onExpired = { [weak self] in self?.cancelExport() }
        background.begin(title: "Exporting \(baseScene.name)", subtitle: title)
        reporter?.exportStarted(id: id, title: title)
        ScreenAwake.hold("export", true)
        exportTask = Task { [weak self] in
            guard let self else { return }
            let urls = await runExport(kind, settings: settings, id: id, background: background)
            background.end(success: urls != nil)
            if let urls {
                exportResults = urls
                HmmHaptics.play(.commit)
                reporter?.exportFinished(id: id, title: title, files: urls)
            }
            exportProgress = nil
            exportWaiting = false
            exportTask = nil
            ScreenAwake.hold("export", false)
        }
    }

    private func runExport(_ kind: ExportKind, settings: ExportSettings, id: String, background: BackgroundExport) async -> [URL]? {
        do {
            let session = try makeExportSession()
            session.onWaiting = { [weak self] waiting in
                self?.exportWaiting = waiting
                self?.app.exportReporter?.exportProgressed(id: id, fraction: self?.exportProgress ?? 0, waiting: waiting)
            }
            let progress: (Double) -> Void = { [weak self] fraction in
                self?.exportProgress = fraction
                background.progress(fraction)
                self?.app.exportReporter?.exportProgressed(id: id, fraction: fraction, waiting: false)
            }
            return try await exportFiles(kind, settings: settings, session: session, progress: progress)
        } catch ExportError.cancelled {
            app.show("Export cancelled")
        } catch {
            app.show("Export failed: \(String(describing: error))", kind: .error)
            app.exportReporter?.exportFailed(id: id, title: baseScene.name, message: String(describing: error))
        }
        return nil
    }

    private func exportFiles(_ kind: ExportKind, settings: ExportSettings, session: ExportSession,
                             progress: @escaping (Double) -> Void) async throws -> [URL] {
        try FileManager.default.createDirectory(at: rendersFolder, withIntermediateDirectories: true)
        let base = rendersFolder.appendingPathComponent(exportBaseName(settings))
        switch kind {
        case .video:
            let url = base.appendingPathExtension(settings.transparent ? "mov" : "mp4")
            try? FileManager.default.removeItem(at: url)
            return try await [session.video(settings, audio: mixdown(settings.range), to: url, progress: progress)]
        case .gif:
            return try await [session.gif(settings, to: base.appendingPathExtension("gif"), progress: progress)]
        case .still:
            let image = try await session.image(at: time, framing: settings.framing, longSide: settings.longSide, transparent: settings.transparent)
            let url = base.appendingPathExtension("png")
            guard let png = UIImage(cgImage: image).pngData() else { throw ExportError.nothingToExport }
            try png.write(to: url, options: .atomic)
            progress(1)
            return [url]
        case .model:
            let urls = exportModel(precision.exportFormat, selectionOnly: !selection.isEmpty)
            guard !urls.isEmpty else { throw ExportError.nothingToExport }
            progress(1)
            return urls
        case .captions:
            guard let url = exportSubtitles() else { throw ExportError.nothingToExport }
            progress(1)
            return [url]
        }
    }

    /// A PNG sequence (one file per frame, with the soundtrack as WAV) for editing apps.
    func exportPNGSequence(_ settings: ExportSettings) {
        guard exportTask == nil else { return }
        exportProgress = 0
        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let exporter = try makeExportSession()
                let folder = rendersFolder.appendingPathComponent(exportBaseName(settings) + " frames")
                let url = try await exporter.pngSequence(settings, audio: mixdown(settings.range), to: folder) { [weak self] in
                    self?.exportProgress = $0
                }
                exportResults = [url]
            } catch {
                app.show("Export failed: \(String(describing: error))", kind: .error)
            }
            exportProgress = nil
            exportTask = nil
        }
    }

    private func makeExportSession() throws -> ExportSession {
        let exporter = try ExportSession(document: session.document, catalog: library.catalog, device: RenderDevice.sharedDevice(),
                                         models: library.models)
        let assets = assetsFolder
        exporter.mediaURL = { file in
            let url = assets.appendingPathComponent(file)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        exporter.stillImage = { name in UIImage(contentsOfFile: assets.appendingPathComponent(name).path)?.cgImage }
        exporter.paintFile = paintFiles
        let gpuInBackground = BackgroundExport.backgroundGPU
        exporter.canRender = { gpuInBackground || UIApplication.shared.applicationState != .background }
        return exporter
    }

    private func exportBaseName(_ settings: ExportSettings) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let shape = settings.framing.rawValue.replacingOccurrences(of: ":", with: "x")
        return "\(ProjectStore.sanitize(baseScene.name)) \(shape) \(formatter.string(from: Date()))"
    }

    /// The soundtrack mixed exactly as the preview plays it (same gains, fades and envelopes).
    private func mixdown(_ range: TimeRange) async -> [Float]? {
        let clips = timeline.audio
        guard !clips.isEmpty else { return nil }
        let folder = audioFolder
        return await Task.detached(priority: .userInitiated) {
            var sources: [String: PCMAudio] = [:]
            for file in Set(clips.map(\.file)) {
                sources[file] = try? AudioDecoder.decode(folder.appendingPathComponent(file))
            }
            return AudioMixer.mix(clips, sources: sources, range: range, sampleRate: AudioDecoder.sampleRate)
        }.value
    }

    /// A PNG of the shot at the playhead (or `time`), through the shot camera like the export (the bridge's snapshot).
    func snapshotPNG(framing: Framing, longSide: Int, at time: Double? = nil) async -> Data? {
        if let time { setTime(time) }
        guard let exporter = try? makeExportSession(),
              let image = try? await exporter.image(at: self.time, framing: framing, longSide: longSide) else { return nil }
        return UIImage(cgImage: image).pngData()
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    // MARK: Files

    /// The scene (or the selection) as a 3D file: glTF, USDZ, OBJ (with its materials), STL, 3MF or a Blender package.
    func exportModel(_ format: ModelExportFormat, selectionOnly: Bool) -> [URL] {
        let ids = selectionOnly && !selection.isEmpty ? selection : nil
        let name = ProjectStore.sanitize(ids.flatMap { $0.count == 1 ? displayed.scene.objects[$0[0]]?.name : nil } ?? baseScene.name)
        // The scene as edited for the timeline's keys (glTF, Blender); as shown for the rest.
        let edited = format == .glb || format == .blender
        let source = edited ? baseScene : displayed.scene
        let files = ModelExport.files(format, ids: ids, scene: source, look: look, preset: lookPreset, catalog: library.catalog, models: library.models,
                                      name: name, paintFile: paintFiles, poses: edited ? [:] : displayed.poses)
        guard !files.isEmpty else {
            app.show("Nothing to export")
            return []
        }
        do {
            try FileManager.default.createDirectory(at: rendersFolder, withIntermediateDirectories: true)
            return try files.map { file in
                let url = rendersFolder.appendingPathComponent(file.name)
                try file.data.write(to: url, options: .atomic)
                return url
            }
        } catch {
            app.show("3D export failed: \(error.localizedDescription)", kind: .error)
            return []
        }
    }

    func saveToPhotos(_ urls: [URL]) {
        let media = urls.filter { ["mp4", "mov", "png", "gif"].contains($0.pathExtension.lowercased()) }
        guard !media.isEmpty else { return }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                app.show("Allow \(AppIdentity.displayName) to add to Photos in Settings", kind: .error)
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for url in media {
                        let isVideo = ["mp4", "mov"].contains(url.pathExtension.lowercased())
                        PHAssetCreationRequest.forAsset().addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
                    }
                }
                app.show("Saved to Photos", kind: .success)
            } catch {
                app.show("Couldn't save to Photos: \(error.localizedDescription)", kind: .error)
            }
        }
    }
}
