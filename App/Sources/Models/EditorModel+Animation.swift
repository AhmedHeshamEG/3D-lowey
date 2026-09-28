import Foundation
import LoweyCore
import LoweyRender
import QuartzCore
import SwiftUI

/// Timeline drawer modes (Procreate Dreams-style).
enum TimelineMode: String, CaseIterable, Identifiable {
    case compose, perform, keyframe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compose: "Compose"
        case .perform: "Perform"
        case .keyframe: "Keyframe"
        }
    }
}

/// Ways to pick many keys at once (the timeline's Select menu).
enum KeyQuery: String, CaseIterable, Identifiable {
    case all, afterPlayhead, beforePlayhead, atPlayhead, loop, invert, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All keys"
        case .afterPlayhead: "Everything after the playhead"
        case .beforePlayhead: "Everything before the playhead"
        case .atPlayhead: "Keys at the playhead"
        case .loop: "Keys in the loop"
        case .invert: "Invert selection"
        case .none: "Select none"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "checkmark.circle"
        case .afterPlayhead: "arrow.right.to.line"
        case .beforePlayhead: "arrow.left.to.line"
        case .atPlayhead: "line.3.horizontal"
        case .loop: "repeat"
        case .invert: "circle.lefthalf.filled"
        case .none: "xmark.circle"
        }
    }
}

enum PerformPhase: Equatable {
    case idle
    case countdown(Int)
    case recording
}

struct PerformSettings: Equatable {
    /// 0…1 motion filtering; 0 captures everything.
    var smoothing = 0.3
    /// Apple Pencil Pro barrel roll turns the object while you move it.
    var barrelRoll = true
}

/// One performed property of one object.
struct PerformChannel: Hashable {
    var object: ObjectID
    var property: PropertyKey
}

enum StaggerChoice: String, CaseIterable, Identifiable {
    case selection, leftToRight, rightToLeft, frontToBack, wave

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection: "Selection order"
        case .leftToRight: "Left → right"
        case .rightToLeft: "Right → left"
        case .frontToBack: "Front → back"
        case .wave: "Wave from centre"
        }
    }
}

struct StaggerPanelSettings: Equatable {
    var delay = 0.08
    var order: StaggerChoice = .leftToRight
    var randomTiming = 0.0
    var randomStrength = 0.0
}

/// Display-link clock for playback (real time; export never uses it).
@MainActor
final class PlaybackClock: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    var onTick: ((Double) -> Void)?

    func start() {
        stop()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        last = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let delta = last.map { now - $0 } ?? 0
        last = now
        onTick?(min(delta, 0.1))
    }
}

extension EditorModel {
    var timeline: Timeline { session.document.scene.timeline }
    var isAnimating: Bool { mode == .animate || mode == .camera }

    /// The range playback loops over (the loop region, else the whole timeline).
    var playRange: TimeRange { timeline.loop ?? TimeRange(start: 0, end: timeline.duration) }

    // MARK: Display

    /// Re-evaluates the timeline at the playhead and updates the stage.
    func refreshDisplay(_ changes: ChangeSet? = nil) {
        rigs = rigCache.rigs(for: session.document, library: library)
        var animated = Animator.evaluate(session.document, at: time, rigs: rigs)
        applyPerformOverrides(&animated)
        var set = changes ?? ChangeSet()
        set.objects.formUnion(animated.animated)
        set.objects.formUnion(previousAnimated)
        displayed = animated
        previousAnimated = animated.animated
        renderer.sync(displayDocument, changes: set)
        renderer.applyPoses(animated.poses, rigs: rigs)
        renderer.applyClipFallback(timeline, at: time, skipping: Set(animated.poses.keys))
        renderer.applyParticles(animated.scene, timeline: timeline, time: time)
        updateLookThrough()
        updateStagePost()
        // During playback SwiftUI panels refresh a few times a second, not every frame.
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
        for (id, values) in propertyOverride {
            guard var object = animated.scene.objects[id] else { continue }
            for (key, value) in values {
                object[key] = value
            }
            animated.scene.objects[id] = object
            animated.animated.insert(id)
        }
    }

    /// Property edits of animated properties become keys at the playhead (and every edit does,
    /// in Animate / Camera mode with auto-key on). Structural edits pass through untouched.
    func keyed(_ command: EditCommand) -> EditCommand {
        switch command {
        case let .setProperties(changes):
            var plain: [PropertyChange] = []
            var keyedChanges: [PropertyChange] = []
            for change in changes {
                let animatable = change.key.spec?.animatable == true && change.value != nil
                let hasTrack = timeline.track(for: change.object, change.key) != nil
                if animatable, hasTrack || (autoKey && isAnimating) {
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

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        play(withAudio: true)
    }

    /// Starts playback. With audio, the picture follows the sound's clock so they never drift apart.
    func play(withAudio: Bool) {
        guard !isPlaying else { return }
        let range = playRange
        if time >= range.end - 1e-3 || time < range.start - 1e-3 { time = range.start }
        isPlaying = true
        if withAudio, !timeline.audio.isEmpty {
            audioPlayback.play(timeline.audio, from: time, until: range.end)
        }
        clock.onTick = { [weak self] delta in self?.tick(delta) }
        clock.start()
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
            if audioPlayback.isPlaying {
                audioPlayback.play(timeline.audio, from: next, until: range.end)
            }
        }
        time = next
        if audioPlayback.isPlaying { audioPlayback.updateGains(timeline.audio, at: next) }
        if performPhase == .recording { recordPerformSample() }
        refreshDisplay()
        refreshSelectionOverlay()
    }

    // MARK: Timeline settings

    func updateTimeline(_ label: String = "Edit timeline", _ change: (inout Timeline) -> Void) {
        var copy = timeline
        change(&copy)
        guard copy != timeline else { return }
        perform(.batch(label, [.setTimeline(copy)]))
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

    /// `nil` = follow the project.
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

    // MARK: Keys

    /// "Key" button: position, rotation and scale of the selection, as they are now.
    func keySelection() {
        var keys = KeyOperations()
        guard let command = keys.keyTransforms(selection, at: time, current: displayed.scene, timeline: timeline) else { return }
        perform(command)
        Haptics.success()
    }

    func deleteSelectedKeys() {
        let keys = KeyOperations()
        perform(keys.delete(Array(selectedKeys), in: timeline))
        selectedKeys = []
    }

    func moveSelectedKeys(by delta: Double, snapToWords wordSnap: Bool = true) {
        let keys = KeyOperations()
        let earliest = selectedKeys.map(\.time).min() ?? 0
        var snapped = max(timeline.snapped(delta), -earliest)
        // The selection's first key lands on a spoken word when it's dropped close to one.
        if wordSnap, snapToWords, let word = WordSnap.snap(earliest + snapped, to: words, tolerance: 8 / max(timelineZoom, 1)) {
            snapped = max(word - earliest, -earliest)
        }
        guard abs(snapped) > 1e-9, perform(keys.moveClamped(Array(selectedKeys), by: snapped, in: timeline)) else { return }
        selectedKeys = Set(selectedKeys.map { KeyRef(track: $0.track, time: max(0, $0.time + snapped)) })
    }

    /// Nudges the selected keys by whole frames (keyboard [ and ], the key menu).
    func nudgeSelectedKeys(frames: Int) {
        moveSelectedKeys(by: Double(frames) / Double(max(timeline.fps, 1)), snapToWords: false)
    }

    /// Stretches the selected keys so they span `range` (drag an end of the selection band).
    func stretchSelectedKeys(to range: TimeRange) {
        guard let from = KeySelection.span(of: selectedKeys) else { return }
        let target = TimeRange(start: timeline.snapped(max(range.start, 0)), end: timeline.snapped(max(range.end, 0)))
        guard perform(KeyOperations().stretch(Array(selectedKeys), to: target, in: timeline)) else { return }
        selectedKeys = KeySelection.normalized(Set(selectedKeys.map {
            KeyRef(track: $0.track, time: max(0, KeySelection.stretchedTime($0.time, from: from, to: target)))
        }), in: timeline)
        Haptics.tap()
    }

    /// Replaces (or adds to) the key selection.
    func selectKeys(_ keys: Set<KeyRef>, additive: Bool = false) {
        selectedKeys = additive ? selectedKeys.union(keys) : keys
        if !keys.isEmpty { Haptics.select() }
    }

    /// Tracks the key-selection commands act on: the selected objects' tracks, or every track.
    var keyScope: Set<TrackID>? {
        selection.isEmpty ? nil : KeySelection.tracks(of: Set(selection.flatMap { baseScene.subtree(of: $0) }), in: timeline)
    }

    func selectKeys(_ query: KeyQuery) {
        let scope = keyScope
        switch query {
        case .all: selectKeys(KeySelection.all(in: timeline, tracks: scope))
        case .afterPlayhead: selectKeys(KeySelection.after(time, in: timeline, tracks: scope))
        case .beforePlayhead: selectKeys(KeySelection.before(time, in: timeline, tracks: scope))
        case .atPlayhead: selectKeys(KeySelection.column(at: time, in: timeline, tracks: scope))
        case .loop:
            guard let loop = timeline.loop else { return }
            selectKeys(KeySelection.keys(in: loop, tracks: scope ?? Set(timeline.tracks.map(\.id)), timeline: timeline))
        case .invert: selectKeys(KeySelection.inverted(selectedKeys, in: timeline, tracks: scope))
        case .none: selectedKeys = []
        }
    }

    func setEasing(_ easing: Easing) {
        let keys = KeyOperations()
        perform(keys.setEasing(easing, for: Array(selectedKeys), in: timeline))
    }

    func copyKeys() {
        let keys = KeyOperations()
        keyClipboard = keys.copy(Array(selectedKeys), in: timeline)
        app.show("Copied \(selectedKeys.count) key\(selectedKeys.count == 1 ? "" : "s")")
    }

    func pasteKeys() {
        guard let clipboard = keyClipboard else { return }
        var keys = KeyOperations()
        let onto = selection.count == 1 && clipboard.entries.count == 1 ? selection.first : nil
        perform(keys.paste(clipboard, at: time, onto: onto, in: timeline))
    }

    func mirrorKeys() {
        perform(KeyOperations().mirror(Array(selectedKeys), in: timeline))
    }

    func reverseKeys() {
        perform(KeyOperations().reverse(Array(selectedKeys), in: timeline))
    }

    func retimeKeys(_ factor: Double) {
        let keys = KeyOperations()
        guard perform(keys.retime(Array(selectedKeys), factor: factor, in: timeline)) else { return }
        let pivot = selectedKeys.map(\.time).min() ?? 0
        selectedKeys = Set(selectedKeys.map { KeyRef(track: $0.track, time: pivot + ($0.time - pivot) * factor) })
    }

    func shiftAnimation(of objects: Set<ObjectID>, by delta: Double) {
        perform(KeyOperations().shift(objects, by: timeline.snapped(delta), in: timeline))
    }

    func clearAnimation() {
        let ids = Set(selection.flatMap { baseScene.subtree(of: $0) })
        var cleaned = TimelineTools.removingReferences(to: ids, from: timeline)
        cleaned.cuts = timeline.cuts
        guard cleaned != timeline else { return }
        perform(.batch("Clear animation", [.setTimeline(cleaned)]))
    }

    var selectionHasAnimation: Bool {
        let ids = Set(selection)
        return !timeline.animatedObjects.isDisjoint(with: ids)
    }

    // MARK: Presets

    func presetOptions(_ preset: AnimationPreset) -> PresetOptions {
        var options = PresetOptions(preset)
        if let presetDuration { options.duration = presetDuration }
        options.amplitude = PresetBuilder.scaledAmplitudeForStrength(preset, options.amplitude, strength: presetStrength)
        if preset == .slideIn, let stage {
            // From the left of the screen.
            let right = stage.viewpoint.rotation.act(.unitX)
            options.direction = -Vec3(right.x, 0, right.z).normalized
        }
        return options
    }

    func applyPreset(_ preset: AnimationPreset) {
        let targets = operations.topLevel(selection, in: baseScene)
        guard !targets.isEmpty else {
            app.show("Select what to animate first")
            return
        }
        let current = Animator.keyedScene(session.document, at: time)
        var settings = StaggerSettings(delay: stagger.delay, randomTiming: stagger.randomTiming, randomAmplitude: stagger.randomStrength,
                                       seed: UInt64.random(in: 1 ... 1_000_000))
        switch stagger.order {
        case .selection: settings.order = .selection
        case .leftToRight: settings.order = .axis(.x, reversed: false)
        case .rightToLeft: settings.order = .axis(.x, reversed: true)
        case .frontToBack: settings.order = .axis(.z, reversed: true)
        case .wave:
            let bounds = selectionBounds
            settings.order = .distance(from: bounds?.center ?? .zero)
        }
        var builder = PresetBuilder()
        guard perform(builder.apply(preset, to: targets, at: time, options: presetOptions(preset), stagger: settings,
                                    current: current, timeline: timeline)) else { return }
        Haptics.success()
    }

    func growGenerator() {
        guard let group = singleSelection, group.kind == .group else { return }
        var builder = PresetBuilder()
        let current = Animator.keyedScene(session.document, at: time)
        perform(builder.animateGenerator(group.id, at: time, current: current, timeline: timeline))
    }

    /// Arrays and scatters (groups made by the generators) can grow in.
    var selectionIsGenerator: Bool {
        guard let object = singleSelection, object.kind == .group else { return false }
        return object.name.contains("array") || object.name.contains("scatter")
    }

    // MARK: Behaviours

    func behaviors(of id: ObjectID) -> [Behavior] {
        timeline.behaviors.filter { $0.target == id }
    }

    func addBehavior(_ kind: BehaviorKind) {
        let targets = operations.topLevel(selection, in: baseScene)
        guard !targets.isEmpty else { return }
        updateTimeline("Add \(kind.title)") { timeline in
            for target in targets {
                timeline.behaviors.append(Behavior(id: UUID().uuidString.lowercased(), target: target, kind: kind, start: 0))
            }
        }
    }

    func removeBehavior(_ id: String) {
        updateTimeline("Remove behaviour") { $0.behaviors.removeAll { $0.id == id } }
    }

    func toggleBehavior(_ id: String) {
        updateTimeline("Toggle behaviour") { timeline in
            if let index = timeline.behaviors.firstIndex(where: { $0.id == id }) { timeline.behaviors[index].enabled.toggle() }
        }
    }

    func setBehaviorStart(_ id: String, toPlayhead: Bool) {
        updateTimeline("Behaviour timing") { timeline in
            guard let index = timeline.behaviors.firstIndex(where: { $0.id == id }) else { return }
            if toPlayhead { timeline.behaviors[index].start = time } else { timeline.behaviors[index].end = time }
        }
    }

    func bakeBehavior(_ id: String) {
        var ids = IDFactory.random
        perform(Simulation.bake(id, in: session.document, rigs: rigs, ids: &ids))
    }

    // MARK: Simulations

    func simulatePhysics(_ kind: PhysicsKind) {
        let targets = operations.topLevel(selection, in: baseScene)
        guard !targets.isEmpty else { return }
        var ids = IDFactory.random
        refreshOperationsLibrary()
        let settings = PhysicsSettings(kind: kind, duration: min(4, max(timeline.duration - time, 1)), center: selectionBounds?.center)
        perform(Simulation.physics(targets, settings: settings, at: time, fps: timeline.fps, bounds: operations.bounds,
                                   current: Animator.keyedScene(session.document, at: time), timeline: timeline, ids: &ids))
    }

    func simulateFlock() {
        let targets = operations.topLevel(selection, in: baseScene)
        guard targets.count > 1 else {
            app.show("Select several birds (or anything) to flock")
            return
        }
        var ids = IDFactory.random
        let center = selectionBounds?.center ?? Vec3(0, 6, 0)
        let settings = Simulation.FlockSettings(duration: max(timeline.duration - time, 2), center: center, extent: Vec3(10, 2.5, 10))
        perform(Simulation.flock(targets, settings: settings, at: time, fps: timeline.fps,
                                 current: Animator.keyedScene(session.document, at: time), timeline: timeline, ids: &ids))
    }

    // MARK: Puppets

    enum PivotPlace: String, CaseIterable {
        case top, center, bottom

        var title: String {
            switch self {
            case .top: "Joint at the top (arm, leg)"
            case .center: "Joint in the middle"
            case .bottom: "Joint at the bottom"
            }
        }
    }

    /// Puppet rigging: wraps the selection in a joint that turns around a pivot (shoulder, hip, hinge).
    func makeJoint(_ place: PivotPlace) {
        refreshOperationsLibrary()
        guard let bounds = selectionBounds else { return }
        let pivot: Vec3 = switch place {
        case .top: Vec3(bounds.center.x, bounds.max.y, bounds.center.z)
        case .center: bounds.center
        case .bottom: Vec3(bounds.center.x, bounds.min.y, bounds.center.z)
        }
        let name = (singleSelection?.name).map { "\($0) joint" } ?? "Joint"
        guard let (command, group) = operations.group(selection, in: scene, name: name, pivot: pivot) else { return }
        if perform(command) {
            setSelection([group])
            app.show("Rotate “\(name)” to bend around its joint")
        }
    }

    // MARK: Perform (motion capture by touch)

    /// Objects that performing moves: the selection (top level).
    var performTargets: [ObjectID] {
        operations.topLevel(selection, in: baseScene).filter { !baseScene.isEffectivelyLocked($0) }
    }

    func armPerform() {
        guard performPhase == .idle else {
            cancelPerform()
            return
        }
        guard !performTargets.isEmpty || virtualCameraActive else {
            app.show("Select what to perform first, or use the iPad as camera")
            return
        }
        pause()
        takes = [:]
        performChannels = []
        performOverride = [:]
        propertyOverride = [:]
        Task { @MainActor in
            for count in [3, 2, 1] {
                performPhase = .countdown(count)
                Haptics.tap()
                try? await Task.sleep(for: .milliseconds(650))
                guard performPhase != .idle else { return }
            }
            performPhase = .recording
            Haptics.success()
            play()
        }
    }

    func cancelPerform() {
        performPhase = .idle
        takes = [:]
        performOverride = [:]
        propertyOverride = [:]
        performTouching = false
        if isPlaying {
            isPlaying = false
            clock.stop()
        }
        refreshDisplay()
    }

    func finishPerform() {
        guard performPhase == .recording else { return }
        performPhase = .idle
        let recorded = Array(takes.values)
        takes = [:]
        performOverride = [:]
        propertyOverride = [:]
        performTouching = false
        var ids = IDFactory.random
        if let command = PerformBaker.command(for: recorded, fps: timeline.fps, smoothing: performSettings.smoothing, timeline: timeline, ids: &ids) {
            perform(command)
            app.show("Performance recorded")
        } else {
            refreshDisplay()
            app.show("Nothing was performed — touch and move while it plays")
        }
    }

    /// Start of a touch while recording: the performed values start from what's shown now.
    func performTouchBegan(_ channels: Set<PropertyKey>) {
        guard performPhase == .recording else { return }
        performTouching = true
        for id in performTargets {
            if performOverride[id] == nil { performOverride[id] = displayed.scene.worldTransform(of: id) }
            for property in channels {
                let channel = PerformChannel(object: id, property: property)
                performChannels.insert(channel)
                var take = takes[channel] ?? PerformTake(object: id, property: property)
                take.begin()
                takes[channel] = take
            }
        }
        recordPerformSample()
    }

    /// Lifting the finger pauses recording (the playhead keeps going).
    func performTouchEnded() {
        performTouching = false
    }

    func performMove(by delta: Vec3) {
        for id in performTargets {
            performOverride[id]?.position += delta
        }
        refreshDisplay()
    }

    func performScale(by factor: Double) {
        for id in performTargets {
            if var transform = performOverride[id] {
                transform.scale = (transform.scale * factor).map { max($0, 0.01) }
                performOverride[id] = transform
            }
        }
        refreshDisplay()
    }

    func performRotate(by radians: Double) {
        let turn = Quat(angle: radians, axis: .unitY)
        for id in performTargets {
            if var transform = performOverride[id] {
                transform.rotation = (turn * transform.rotation).normalized
                performOverride[id] = transform
            }
        }
        refreshDisplay()
    }

    /// Slider performing (any animatable number: glow, light strength, focal length, opacity…).
    func performValue(_ key: PropertyKey, _ value: Double, touching: Bool) {
        for id in performTargets {
            propertyOverride[id, default: [:]][key] = .float(value)
            if touching, performPhase == .recording {
                let channel = PerformChannel(object: id, property: key)
                if !performTouching { takes[channel, default: PerformTake(object: id, property: key)].begin() }
                performChannels.insert(channel)
            }
        }
        performTouching = touching
        refreshDisplay()
    }

    func recordPerformSample() {
        guard performPhase == .recording, performTouching else { return }
        for channel in performChannels {
            guard takes[channel] != nil else { continue }
            let value: PropertyValue?
            if let world = performOverride[channel.object], [.position, .rotation, .scale].contains(channel.property) {
                let parentWorld = displayed.scene.objects[channel.object]?.parent.map { displayed.scene.worldTransform(of: $0) } ?? .identity
                let local = CoreTransform.relative(world: world, toParent: parentWorld)
                value = switch channel.property {
                case .position: .vec3(local.position)
                case .rotation: .quat(local.rotation)
                default: .vec3(local.scale)
                }
            } else {
                value = propertyOverride[channel.object]?[channel.property]
            }
            if let value { takes[channel]?.add(.init(time: time, value: value)) }
        }
    }
}

extension PresetBuilder {
    /// The strength slider scales how far a preset goes (multiplicative presets scale around 1).
    static func scaledAmplitudeForStrength(_ preset: AnimationPreset, _ amplitude: Double, strength: Double) -> Double {
        scaledAmplitude(preset, amplitude, by: strength)
    }
}
