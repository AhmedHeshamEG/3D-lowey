import Foundation
import LoweyCore
import LoweyRender
import LoweyScript
import Photos
import SwiftUI

extension EditorModel {
    // MARK: Video

    var rendersFolder: URL { projectURL.appendingPathComponent(ProjectLayout.rendersFolder) }

    var isExporting: Bool { exportProgress != nil }

    /// Renders frame by frame in the background; the stage stays usable. One job at a time.
    func exportVideo(_ settings: VideoExportSettings) {
        guard exportTask == nil else { return }
        pause()
        exportProgress = 0
        exportResults = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "\(ProjectStore.sanitize(baseScene.name)) \(formatter.string(from: Date()))"
        let exporter = VideoExporter(document: session.document, library: library, rigs: rigCache)
        let folder = rendersFolder
        exportTask = Task { [weak self] in
            do {
                let urls = try await exporter.export(settings: settings, to: folder, baseName: base) { progress in
                    self?.exportProgress = progress
                }
                self?.exportResults = urls
                Haptics.success()
                self?.app.show(urls.count == 1 ? "Exported" : "Exported \(urls.count) videos")
            } catch ExportError.cancelled {
                self?.app.show("Export cancelled")
            } catch {
                self?.app.show("Export failed: \(error)")
            }
            self?.exportProgress = nil
            self?.exportTask = nil
        }
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    func saveToPhotos(_ urls: [URL]) {
        let videos = urls.filter { ["mp4", "mov"].contains($0.pathExtension.lowercased()) }
        guard !videos.isEmpty else { return }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                app.show("Allow 3D-lowey to add to Photos in Settings")
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for url in videos {
                        PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
                    }
                }
                app.show("Saved to Photos")
            } catch {
                app.show("Couldn't save to Photos: \(error.localizedDescription)")
            }
        }
    }

    // MARK: 3D

    func exportModel(_ format: ModelExportFormat, selectionOnly: Bool) -> URL? {
        let ids = selectionOnly && !selection.isEmpty ? selection : nil
        let meshes = ModelExport.meshes(ids, scene: displayed.scene, look: look, renderer: renderer)
        guard !meshes.isEmpty else {
            app.show("Nothing to export")
            return nil
        }
        let name = ProjectStore.sanitize(ids.flatMap { $0.count == 1 ? displayed.scene.objects[$0[0]]?.name : nil } ?? baseScene.name)
        let url = rendersFolder.appendingPathComponent(name).appendingPathExtension(format.rawValue)
        do {
            try FileManager.default.createDirectory(at: rendersFolder, withIntermediateDirectories: true)
            try ModelExport.data(format, meshes: meshes).write(to: url, options: .atomic)
            return url
        } catch {
            app.show("3D export failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Scripts

    func openScript(_ script: ScriptAsset?) {
        if let script {
            scriptName = script.name
            scriptSource = script.source
        } else if scriptSource.isEmpty {
            scriptName = ScriptExamples.forest.name
            scriptSource = ScriptExamples.forest.source
        }
        scriptLog = []
        showScripts = true
    }

    func runScript() {
        guard !scriptRunning else { return }
        scriptRunning = true
        scriptLog = ["Running…"]
        let source = scriptSource
        let name = scriptName.isEmpty ? "Script" : scriptName
        let document = session.document
        let selection = selection
        let time = time
        Task {
            let outcome = await ScriptRunner.run(source, name: name, document: document, selection: selection, time: time)
            scriptRunning = false
            if let error = outcome.error {
                scriptLog = outcome.log + ["⚠︎ " + error]
                return
            }
            if let command = outcome.command, perform(command) {
                let created = outcome.created.filter { baseScene.objects[$0]?.parent == nil }
                if !created.isEmpty { setSelection(created) }
                scriptLog = outcome.log + ["Done — one undo step."]
                Haptics.success()
            } else {
                scriptLog = outcome.log + ["The script ran but changed nothing."]
            }
        }
    }

    func saveScriptToLibrary() {
        library.saveScript(name: scriptName.isEmpty ? "My script" : scriptName, source: scriptSource)
        app.show("Saved “\(scriptName)” to your library")
    }

    // MARK: Characters

    var selectedCharacter: (object: SceneObject, asset: LibraryAsset)? {
        guard let object = singleSelection, let id = object.kind.assetID, let asset = library.manifest.asset(id), asset.rig.isRigged else { return nil }
        return (object, asset)
    }

    func availableClips(for asset: LibraryAsset) -> [ClipRef] {
        rigCache.availableClips(for: asset, library: library)
    }

    func clipTrack(for id: ObjectID) -> ClipTrack? {
        timeline.clipTracks.first { $0.target == id }
    }

    /// Plays a clip from the playhead to the end (looping); it crossfades from what played before.
    func addClip(_ clip: ClipRef) {
        guard let character = selectedCharacter?.object.id else { return }
        let duration = max(timeline.duration - time, 1)
        updateTimeline("Play \(clip.name)") { timeline in
            var track = timeline.clipTracks.first { $0.target == character } ?? ClipTrack(id: UUID().uuidString.lowercased(), target: character)
            // A new clip cuts the previous one short where it starts (plus the crossfade).
            track.segments = track.segments.map { segment in
                var trimmed = segment
                if segment.start < time, segment.end > time { trimmed.duration = max(time - segment.start + 0.3, 0.1) }
                return trimmed
            }.filter { $0.start < time + 1e-6 }
            track.segments.append(ClipSegment(id: UUID().uuidString.lowercased(), clip: clip, start: time, duration: duration,
                                              blend: track.segments.isEmpty ? 0 : 0.3))
            track.segments.sort { $0.start < $1.start }
            timeline.clipTracks.removeAll { $0.target == character }
            timeline.clipTracks.append(track)
        }
    }

    func updateSegment(_ id: String, _ change: @escaping (inout ClipSegment) -> Void) {
        updateTimeline("Edit clip") { timeline in
            for trackIndex in timeline.clipTracks.indices {
                if let index = timeline.clipTracks[trackIndex].segments.firstIndex(where: { $0.id == id }) {
                    change(&timeline.clipTracks[trackIndex].segments[index])
                }
            }
        }
    }

    func removeSegment(_ id: String) {
        updateTimeline("Remove clip") { timeline in
            for index in timeline.clipTracks.indices {
                timeline.clipTracks[index].segments.removeAll { $0.id == id }
            }
            timeline.clipTracks.removeAll { $0.segments.isEmpty }
        }
    }

    func setIK(_ change: @escaping (inout IKSettings) -> Void) {
        guard let character = selectedCharacter?.object.id else { return }
        updateTimeline("Character IK") { timeline in
            if let index = timeline.clipTracks.firstIndex(where: { $0.target == character }) {
                change(&timeline.clipTracks[index].ik)
            }
        }
    }

    /// Walking along a path without sliding: the walk plays at the speed the path demands.
    func matchClipSpeedToPath() {
        guard let (object, asset) = selectedCharacter, let track = clipTrack(for: object.id),
              let behavior = behaviors(of: object.id).first(where: {
                  if case .followPath = $0.kind {
                      true
                  } else {
                      false
                  }
              }),
              case let .followPath(source, duration, _, _) = behavior.kind else {
            app.show("Give the character a Follow path behaviour first")
            return
        }
        let length = BehaviorEvaluator.path(source, in: displayed.scene).length
        guard duration > 0, length > 0 else { return }
        let speed = length / duration
        let scale = displayed.scene.worldTransform(of: object.id).scale.y
        var changed = 0
        updateTimeline("Match walk to path") { timeline in
            guard let index = timeline.clipTracks.firstIndex(where: { $0.id == track.id }) else { return }
            // The path moves the character; the clip only animates the legs.
            timeline.clipTracks[index].ik.inPlace = true
            for segmentIndex in timeline.clipTracks[index].segments.indices {
                let clip = timeline.clipTracks[index].segments[segmentIndex].clip
                guard let rig = rigCache.rig(
                    for: library.manifest.asset(clip.asset) ?? asset,
                    url: library.fileURL(for: library.manifest.asset(clip.asset) ?? asset)
                ),
                    let motion = rig.clips[clip.name], let stride = rig.strideSpeed(of: motion) else { continue }
                timeline.clipTracks[index].segments[segmentIndex].speed = min(max(speed / (stride * max(scale, 0.01)), 0.1), 5)
                changed += 1
            }
        }
        app.show(changed > 0 ? "The walk now matches the path — no sliding" : "Couldn't measure the clip's stride")
    }

    /// Crowd tool: copies of the selected character in a loose grid, each with its clips offset
    /// and slightly varied so they don't move in lock-step.
    func makeCrowd(count: Int) {
        guard let (object, _) = selectedCharacter else { return }
        refreshOperationsLibrary()
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        let step = max(arrayStep, 0.6)
        guard let (arrayCommand, group) = operations.array(object.id, layout: .grid(columns: columns, rows: rows, spacingX: step, spacingZ: step),
                                                           in: scene) else { return }
        var working = session.document
        guard (try? arrayCommand.apply(to: &working)) != nil else { return }
        let members = working.scene.objects[group]?.children ?? []
        var timeline = working.scene.timeline
        var random = SeededRandom(seed: UInt64.random(in: 1 ... 1_000_000))
        if let source = timeline.clipTracks.first(where: { $0.target == object.id }) {
            for member in members where member != object.id {
                var copy = source
                copy.id = UUID().uuidString.lowercased()
                copy.target = member
                copy.segments = source.segments.map { segment in
                    var varied = segment
                    varied.id = UUID().uuidString.lowercased()
                    varied.offset += random.range(0, 1.5)
                    varied.speed *= random.range(0.9, 1.1)
                    return varied
                }
                timeline.clipTracks.append(copy)
            }
        }
        var changes: [PropertyChange] = []
        for member in members where member != object.id {
            guard let transform = working.scene.objects[member]?.transform else { continue }
            var jittered = transform
            jittered.position += Vec3(random.range(-0.2, 0.2), 0, random.range(-0.2, 0.2)) * step
            jittered.rotation = (Quat(angle: random.range(-0.3, 0.3), axis: .unitY) * transform.rotation).normalized
            changes.append(PropertyChange(object: member, key: .position, value: .vec3(jittered.position)))
            changes.append(PropertyChange(object: member, key: .rotation, value: .quat(jittered.rotation)))
        }
        // Placement, not animation: never auto-keyed.
        let keying = autoKey
        autoKey = false
        defer { autoKey = keying }
        if perform(.batch("Crowd of \(members.count)", [arrayCommand, .setProperties(changes), .setTimeline(timeline)])) {
            setSelection([group])
        }
    }
}
