import Foundation
import LoweyCore
import LoweyEngine
import QuartzCore

/// The playhead, playback (audio is the clock when there is sound), evaluating the timeline for the stage, and edits
/// that become keys at the playhead.
extension EditorModel {
    var timeline: Timeline { session.document.scene.timeline }

    /// The range playback loops over (the loop region, else the whole timeline).
    var playRange: TimeRange { timeline.loop ?? TimeRange(start: 0, end: timeline.duration) }

    // MARK: Display

    /// Rigs the animator needs: every clip's source model (loaded through the shared model library).
    func rigs() -> [AssetID: RigAsset] {
        guard !timeline.clipTracks.isEmpty else { return [:] }
        var needed = Set<AssetID>()
        for track in timeline.clipTracks {
            if let asset = baseScene.objects[track.target]?.kind.assetID { needed.insert(asset) }
            for segment in track.segments {
                needed.insert(segment.clip.asset)
            }
        }
        var result: [AssetID: RigAsset] = [:]
        let catalog = library.catalog
        for id in needed {
            guard let asset = catalog.manifest.asset(id) else { continue }
            _ = library.models.model(asset, catalog: catalog)
            if let rig = library.models.rig(id) { result[id] = rig }
        }
        return result
    }

    /// While the Rig tool is on, the object being rigged stands as it was made: no turned joints, no clips (bones and
    /// weights are drawn on the rest pose). So does a rigged object being painted (paint lands on the surface as made).
    func restingRigTarget(_ document: Document) -> Document {
        let target = tool == .rig ? rigging.target : (tool == .paint ? colourPaint.target ?? singleSelection?.id : nil)
        guard let id = target, let object = document.scene.objects[id], object.rig != nil else { return document }
        var resting = document
        resting.scene.objects[id]?.properties = object.properties.filter { $0.key.boneJoint == nil }
        resting.scene.timeline.tracks.removeAll { $0.target == id && $0.property.boneJoint != nil }
        resting.scene.timeline.clipTracks.removeAll { $0.target == id }
        return resting
    }

    /// Evaluates the timeline at the playhead and redraws the stage.
    func refreshDisplay(_ changes: ChangeSet? = nil) {
        var animated = Animator.evaluate(restingRigTarget(historyPreview ?? session.document), at: time, rigs: libraryRigs(),
                                         overrides: propertyOverride)
        applyPerformOverrides(&animated)
        for (id, kind) in kindOverride where animated.scene.objects[id] != nil {
            animated.scene.objects[id]?.kind = kind
        }
        displayed = animated
        previousAnimated = animated.animated
        if changes != nil { overlayCache = StageOverlayCache() }
        stage?.redraw()
        // While playing, panels refresh a few times a second, not every frame.
        let now = CACurrentMediaTime()
        if !isPlaying || now - lastRevisionBump > 0.15 {
            lastRevisionBump = now
            bumpDisplayRevision()
        }
    }

    private func applyPerformOverrides(_ animated: inout AnimatedScene) {
        for (id, transform) in performOverride {
            guard var object = animated.scene.objects[id] else { continue }
            let parentWorld = object.parent.map { animated.scene.worldTransform(of: $0) } ?? .identity
            object.transform = CoreTransform.relative(world: transform, toParent: parentWorld)
            animated.scene.objects[id] = object
            animated.animated.insert(id)
        }
    }

    /// Changes of animated properties become keys at the playhead; in Keyframe mode with auto-key on, every animatable
    /// change does (Compose never creates keys, so building a set never sprinkles them). Structural edits pass through.
    func keyed(_ command: EditCommand) -> EditCommand {
        switch command {
        case let .setProperties(changes):
            var plain: [PropertyChange] = []
            var keyedChanges: [PropertyChange] = []
            for change in changes {
                let animatable = change.key.spec?.animatable == true && change.value != nil
                let hasTrack = timeline.track(for: change.object, change.key) != nil
                if animatable, hasTrack || (autoKey && timelineMode == .keyframe) {
                    keyedChanges.append(change)
                } else {
                    plain.append(change)
                }
            }
            guard !keyedChanges.isEmpty else { return command }
            var keys = KeyOperations()
            let edits = keys.keying(keyedChanges, at: time, current: displayed.scene, timeline: timeline)
            if plain.isEmpty { return .setTracks(edits) }
            return .batch(command.label, [.setProperties(plain), .setTracks(edits)])
        case let .batch(label, commands):
            return .batch(label, commands.map(keyed))
        default:
            return command
        }
    }

    // MARK: Time & playback

    func setTime(_ newTime: Double, snap: Bool = true) {
        let clamped = min(max(snap ? timeline.snapped(newTime) : newTime, 0), timeline.duration)
        guard clamped != time || !isPlaying else { return }
        time = clamped
        refreshDisplay()
        refreshSelectionOverlay()
    }

    func step(frames: Int) {
        pause()
        setTime(time + Double(frames) / Double(timeline.fps))
    }

    /// ⌥← / ⌥→ and the on-screen buttons: ten seconds back or forward.
    func jump(seconds: Double) {
        pause()
        setTime(time + seconds, snap: false)
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    /// Starts playback. With sound, the picture follows the sound's clock so they never drift apart.
    func play(withAudio: Bool = true) {
        guard !isPlaying else { return }
        let range = playRange
        if time >= range.end - 1e-3 || time < range.start - 1e-3 { time = range.start }
        isPlaying = true
        if withAudio, !timeline.audio.isEmpty {
            _ = audioPlayback.play(timeline.audio, from: time, until: range.end)
        }
        clock.onTick = { [weak self] delta in self?.tick(delta) }
        clock.start()
        updateStageClock()
        scheduleChromeFade()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        clock.stop()
        audioPlayback.stop()
        if isRecordingVoice { stopVoiceRecording() }
        if performPhase == .recording { finishPerform() }
        time = timeline.snapped(time)
        refreshDisplay()
        refreshSelectionOverlay()
        updateStageClock()
        showChrome()
    }

    private func tick(_ delta: Double) {
        let range = playRange
        var next = audioPlayback.currentTime ?? time + delta
        if next > range.end {
            if isRecordingVoice {
                stopVoiceRecording()
                return
            }
            if performPhase == .recording {
                time = range.end
                recordPerformSample()
                pause()
                return
            }
            next = range.duration > 0 ? range.start + (next - range.end).truncatingRemainder(dividingBy: range.duration) : range.start
            if audioPlayback.isPlaying { _ = audioPlayback.play(timeline.audio, from: next, until: range.end) }
        }
        time = next
        if audioPlayback.isPlaying { audioPlayback.updateGains(timeline.audio, at: next) }
        if performPhase == .recording { recordPerformSample() }
        let before = previousAnimated
        refreshDisplay()
        if selectionMoves(before.union(previousAnimated)) { refreshSelectionOverlay() }
    }

    // MARK: Chrome during playback

    /// Playback fades the chrome after two seconds; any touch or pause brings it back.
    func scheduleChromeFade() {
        chromeFadeTask?.cancel()
        chromeFadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, isPlaying, performPhase == .idle else { return }
            chromeFaded = true
        }
    }

    func showChrome() {
        chromeFadeTask?.cancel()
        if chromeFaded { chromeFaded = false }
        if isPlaying { scheduleChromeFade() }
    }

    // MARK: Timeline settings

    func updateTimeline(_ label: String = "Edit timeline", coalesce: String? = nil, _ change: (inout Timeline) -> Void) {
        var copy = timeline
        change(&copy)
        guard copy != timeline else { return }
        perform(.batch(label, [.setTimeline(copy)]), coalesceKey: coalesce)
    }

    func setFrameRate(_ fps: Int) {
        updateTimeline("Frame rate") { $0.fps = fps }
    }

    func setDuration(_ seconds: Double) {
        updateTimeline("Length") { $0.duration = max(seconds, 1) }
        if time > timeline.duration { setTime(timeline.duration) }
    }

    func fitDurationToContent() {
        setDuration(max(timeline.contentEnd + 0.5, 1))
    }

    func setProjectStepping(_ stepping: Stepping) {
        updateTimeline("Stepping") { $0.stepping = stepping }
    }

    /// nil = follow the project.
    func setObjectStepping(_ stepping: Stepping?) {
        perform(.setProperties(selection.map { PropertyChange(object: $0, key: .stepping, value: stepping.map { .enumeration($0.name) }) }))
    }

    func addMarker(named name: String? = nil) {
        let marker = Marker(id: UUID().uuidString.lowercased(), time: time, name: name ?? "Marker \(timeline.markers.count + 1)")
        updateTimeline("Add marker") { $0.markers.append(marker) }
    }

    func removeMarker(_ id: String) {
        updateTimeline("Remove marker") { $0.markers.removeAll { $0.id == id } }
    }

    func renameMarker(_ id: String, to name: String) {
        updateTimeline("Rename marker") { timeline in
            if let index = timeline.markers.firstIndex(where: { $0.id == id }) { timeline.markers[index].name = name }
        }
    }

    func jumpToMarker(forward: Bool) {
        let times = (timeline.markers.map(\.time) + [0, timeline.duration]).sorted()
        let target = forward ? times.first(where: { $0 > time + 1e-3 }) : times.last(where: { $0 < time - 1e-3 })
        if let target { setTime(target) }
    }

    func setLoopStart() {
        let end = timeline.loop?.end ?? min(time + 2, timeline.duration)
        updateTimeline("Loop") { $0.loop = TimeRange(start: time, end: max(end, time + 0.1)) }
    }

    func setLoopEnd() {
        let start = timeline.loop?.start ?? 0
        updateTimeline("Loop") { $0.loop = TimeRange(start: min(start, time - 0.1), end: time) }
    }

    func clearLoop() {
        updateTimeline("Loop") { $0.loop = nil }
    }
}
