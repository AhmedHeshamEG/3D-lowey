import Foundation
import LoweyCore
import LoweyRender
import Observation
import os
import RealityKit
import SwiftUI

/// Everything about one open project: the edit session (document + undo), selection,
/// tools, panels, autosave. Every change to the scene goes through `perform`.
@Observable
@MainActor
final class EditorModel {
    // MARK: State

    @ObservationIgnored unowned let app: AppModel
    private(set) var projectURL: URL
    private(set) var session: EditSession
    var document: Document { session.document }
    /// The scene as edited (what's saved).
    var baseScene: CoreScene { session.document.scene }
    /// The scene as shown: animation evaluated at the playhead. Tools read this, so moving an
    /// animated object moves what you see, and the change becomes a key at the playhead.
    var scene: CoreScene {
        _ = displayRevision
        return displayed.scene
    }

    /// The document with the scene as shown (for the renderer and snapshots).
    var displayDocument: Document { Document(project: session.document.project, scene: displayed.scene) }

    private(set) var selection: [ObjectID] = [] {
        didSet {
            if AppModel.isUITesting, selection != oldValue {
                let names = selection.compactMap { scene.objects[$0]?.name }.joined(separator: ",")
                debugTrail = Array((debugTrail + ["sel=[\(names)]"]).suffix(12))
            }
        }
    }

    /// UI-test only: recent selection/command history, exposed as an accessibility value.
    private(set) var debugTrail: [String] = []
    var mode: EditorMode = .build {
        didSet { if mode != oldValue { modeChanged() } }
    }

    var tool: Tool = .select {
        didSet { if tool != oldValue { toolChanged() } }
    }

    var gizmoMode: GizmoMode = .move {
        didSet { stage?.gizmo.mode = gizmoMode }
    }

    var snap = SnapSettings()
    var draw = DrawSettings() {
        didSet { if draw != oldValue { refreshGuide() } }
    }

    var scatter = ScatterPanelSettings()
    /// The rail colour: new blockout, strokes and "paint" use it.
    var currentColor: ColorValue = .palette(0)
    var showLibrary = false
    /// Slide-out panel next to the tool rail.
    var railPanel: RailPanel?
    var showOutliner = false
    var libraryPurpose: LibraryPurpose = .place
    /// The stats pill (frame rate, slowest frame, heat) in the stage's corner.
    var showStatistics = false {
        didSet { statsMonitor.setRunning(showStatistics) }
    }

    let statsMonitor = StatsMonitor()
    /// Video overlay frames for the live stage (nearest frame, never waits).
    @ObservationIgnored lazy var videoPreview: VideoFrames = {
        let frames = VideoFrames(exact: false)
        frames.onFrame = { [weak self] in self?.updateStagePost() }
        return frames
    }()

    /// The picture / video picker (Add → Photo or video).
    var showMediaImporter = false
    /// Focus mode: every panel hidden, only the stage (and one button to bring the interface back).
    var focusMode = false

    var showGrid = true {
        didSet { stage?.showsGrid = showGrid && mode == .build }
    }

    /// Mirrors the stage camera's projection (for the ortho toggle).
    private(set) var projection: Viewpoint.Projection = .perspective
    var eyedropperActive = false
    var eyedropperSlot = 0
    var snapshotFraming: Framing = .landscape
    var isSaving = false
    private(set) var lastSaved: Date?
    /// Screen-space overlay shapes (lasso polygon, scatter circle).
    var lassoPoints: [CGPoint] = []
    /// Where the Apple Pencil hovers (brush preview), and how high (0…1).
    var hoverPoint: CGPoint?
    var hoverHeight: Double = 0
    var scatterPreview: (center: CGPoint, radius: CGFloat)?

    // MARK: Animation state (see EditorModel+Animation.swift)

    /// Playhead (seconds). Change it with `setTime` so the stage follows.
    var time: Double = 0
    var isPlaying = false
    var timelineMode: TimelineMode = .keyframe
    /// In Animate / Camera mode, edits become keys at the playhead.
    var autoKey = true
    /// Timeline zoom: points per second.
    var timelineZoom: Double = 90
    var selectedKeys: Set<KeyRef> = []
    /// Timeline "Select" mode: dragging on empty lanes draws a selection box and taps add to the selection.
    var keyBoxSelect = false
    var expandedObjects: Set<ObjectID> = []
    /// Timeline group rows whose children are folded away.
    var collapsedGroups: Set<ObjectID> = []
    /// First second shown in the timeline (scrolled by drags, flicks and zoom).
    var timelineStart: Double = 0
    var presetDuration: Double?
    var presetStrength: Double = 1
    var stagger = StaggerPanelSettings()
    var performSettings = PerformSettings()
    var performPhase: PerformPhase = .idle
    /// A property being performed with a slider (glow, light, focal length…).
    var performSliderKey: PropertyKey?
    var graphKey: KeyRef?
    var showScripts = false
    var scriptSource = ""
    var scriptName = "My script"
    var scriptLog: [String] = []
    var scriptRunning = false
    /// Camera mode: see through the shot camera.
    var lookThrough = true
    var cameraFraming: Framing = .landscape
    var showSafeZones = true
    var virtualCameraActive = false
    var virtualCameraScale: Double = 1
    var exportProgress: Double?
    /// The export is holding until the app is back in front (it resumes by itself).
    var exportWaiting = false
    var exportResults: [URL] = []

    // MARK: Audio & narration state (see EditorModel+Audio.swift)

    var selectedAudio: String?
    var showAudio = false
    var showTranscript = false
    /// Keys, cuts and the playhead snap to spoken words.
    var snapToWords = true
    var isRecordingVoice = false
    var transcribing: String?
    var transcriptLanguage = "en-US"
    /// Selected words in the transcript panel (indices into `timeline.words`).
    var wordSelection: ClosedRange<Int>?
    @ObservationIgnored lazy var audioPlayback = AudioPlayback(folder: audioFolder)
    @ObservationIgnored let voiceRecorder = VoiceRecorder()
    @ObservationIgnored var recordingStart: Double = 0
    /// Waveform peaks per audio file (100 per second), decoded once.
    var waveforms: [String: [Float]] = [:]
    @ObservationIgnored var decodedAudio: [String: PCMAudio] = [:]

    // MARK: Story, VFX & post state (see EditorModel+Story.swift)

    /// Post-processing in the live view (off = the plain render, for speed while blocking out).
    var previewPost = true {
        didSet { updateStagePost() }
    }

    /// Screen effects (shake, flash…) in the live view.
    var previewEffects = true
    @ObservationIgnored var overlayImages: [String: CGImage] = [:]

    // MARK: Character & face state (see EditorModel+Character.swift)

    var showCharacterBuilder = false
    /// The blob character sheet (the house style).
    var showBlobBuilder = false
    /// A Scene Script waiting for your decision (AI proposes, you decide).
    var proposal: ScriptProposal?
    var showBridge = false
    /// The character the builder edits (nil = a new one).
    var characterBuilderTarget: ObjectID?
    var faceActive = false
    var faceStatus: String?
    @ObservationIgnored var faceCapture: FaceCapture?
    @ObservationIgnored var faceLink: FaceLinkReceiver?
    @ObservationIgnored let facePerformer = FacePerformer()
    @ObservationIgnored var thermalObserver: NSObjectProtocol?
    @ObservationIgnored var captionCache: (factor: Double, revision: Int, pages: [CaptionPage])?
    private(set) var displayRevision = 0

    @ObservationIgnored var displayed: AnimatedScene
    @ObservationIgnored var previousAnimated = Set<ObjectID>()
    @ObservationIgnored let rigCache = RigCache()
    @ObservationIgnored var rigs: [AssetID: RigAsset] = [:]
    @ObservationIgnored let clock = PlaybackClock()
    @ObservationIgnored var keyClipboard: KeyClipboard?
    @ObservationIgnored var takes: [PerformChannel: PerformTake] = [:]
    @ObservationIgnored var performOverride: [ObjectID: CoreTransform] = [:]
    @ObservationIgnored var propertyOverride: [ObjectID: [PropertyKey: PropertyValue]] = [:]
    @ObservationIgnored var performChannels = Set<PerformChannel>()
    @ObservationIgnored var performTouching = false
    @ObservationIgnored var exportTask: Task<Void, Never>?
    @ObservationIgnored var virtualCamera: VirtualCameraController?
    @ObservationIgnored var lastRevisionBump: CFTimeInterval = 0

    func bumpDisplayRevision() {
        displayRevision &+= 1
    }

    enum RailPanel: Equatable {
        case add, color
    }

    enum LibraryPurpose: Equatable {
        case place
        case swap(ObjectID)
    }

    // MARK: Rendering

    @ObservationIgnored let renderer = SceneRenderer()
    @ObservationIgnored weak var stage: StageView?
    @ObservationIgnored let offscreen = OffscreenRenderer()
    @ObservationIgnored var operations = Operations()
    @ObservationIgnored private var factory = ObjectFactory()
    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private let saver: DocumentSaver
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var viewpointSaveTask: Task<Void, Never>?
    @ObservationIgnored private var clipboard: SceneFragment?
    @ObservationIgnored private let logger = Logger(subsystem: "com.hesham.lowey", category: "editor")

    var library: LibraryModel { app.library }

    init(app: AppModel, projectURL: URL, document: Document) {
        self.app = app
        self.projectURL = projectURL
        session = EditSession(document: document)
        displayed = Animator.evaluate(document, at: 0)
        store = app.projectStore
        saver = DocumentSaver(store: app.projectStore)
        renderer.library = app.library
        renderer.load(document)
        refreshDisplay()
        app.library.onPrefabChanged = { [weak self] id in self?.renderer.prefabChanged(id) }
        let url = projectURL
        let saver = saver
        Task { await saver.markSaved(0, for: url) }
    }

    /// Called by the stage container once the RealityKit view exists.
    func attach(_ stage: StageView) {
        self.stage = stage
        stage.setViewpoint(scene.viewpoint, notify: false)
        projection = scene.viewpoint.projection
        stage.showsGrid = showGrid && mode == .build
        stage.gizmo.mode = gizmoMode
        stage.onCameraChanged = { [weak self] viewpoint in self?.cameraMoved(viewpoint) }
        renderer.onContentChanged = { [weak self] in self?.refreshSelectionOverlay() }
        refreshGuide()
        refreshSelectionOverlay()
        applyThermalQuality()
        thermalObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil,
                                                                 queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyThermalQuality() }
        }
    }

    /// Thermal-aware preview: when the iPad gets hot, the stage renders fewer pixels and skips depth effects
    /// (exports are unaffected — they render offscreen at full quality).
    func applyThermalQuality() {
        guard let stage else { return }
        let state = ProcessInfo.processInfo.thermalState
        let full = stage.window?.screen.scale ?? 2
        let scale: CGFloat = switch state {
        case .critical: 1
        case .serious: max(full * 0.66, 1)
        default: full
        }
        if stage.contentScaleFactor != scale {
            stage.contentScaleFactor = scale
            Diagnostics.shared.log("Thermal \(state.rawValue): preview scale \(scale)")
        }
        updateStagePost()
    }

    // MARK: Perform / undo / redo

    /// Applies a command (the only way the scene changes).
    @discardableResult
    func perform(_ command: EditCommand?, coalesceKey: String? = nil) -> Bool {
        guard let command else { return false }
        do {
            let changes = try session.perform(keyed(command), coalesceKey: coalesceKey)
            if AppModel.isUITesting { debugTrail = Array((debugTrail + ["cmd=\(command.label)"]).suffix(12)) }
            refreshDisplay(changes)
            afterChange()
            return true
        } catch {
            logger.error("Command failed: \(String(describing: error))")
            app.show("That didn't work: \(error)")
            return false
        }
    }

    func endGesture() {
        session.endCoalescing()
        // Fingers up while recording a flown camera: that take pauses until the next touch.
        if performPhase == .recording, performedCamera != nil { performTouching = false }
    }

    var canUndo: Bool { session.canUndo }
    var canRedo: Bool { session.canRedo }

    func undo() {
        do {
            guard let changes = try session.undo() else { return }
            refreshDisplay(changes)
            Haptics.tap()
            afterChange()
        } catch {
            app.show("Undo failed: \(error)")
        }
    }

    func redo() {
        do {
            guard let changes = try session.redo() else { return }
            refreshDisplay(changes)
            Haptics.tap()
            afterChange()
        } catch {
            app.show("Redo failed: \(error)")
        }
    }

    private func afterChange() {
        selection = selection.filter { scene.objects[$0] != nil }
        selectedKeys = selectedKeys.filter { key in timeline.track(key.track)?.key(at: key.time) != nil }
        refreshSelectionOverlay()
        scheduleAutosave()
        if app.bridge.isOn { app.bridge.notify("scene", ["revision": String(session.revision)]) }
    }

    // MARK: Autosave (debounced, off the main thread, atomic)

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await self?.saveNow(thumbnail: false)
        }
    }

    func saveNow(thumbnail: Bool) async {
        let document = session.document
        let revision = session.revision
        let url = projectURL
        isSaving = true
        do {
            try await saver.save(document, revision: revision, to: url)
            lastSaved = Date()
        } catch {
            app.show("Autosave failed: \(error.localizedDescription)")
        }
        isSaving = false
        if thumbnail { await writeProjectThumbnail() }
    }

    private func writeProjectThumbnail() async {
        guard let image = try? await offscreen.snapshot(of: renderer, viewpoint: scene.viewpoint, framing: .landscape, longSide: 640),
              let png = OffscreenRenderer.pngData(image) else { return }
        try? store.writeThumbnail(png, for: projectURL)
        app.setThumbnail(UIImage(cgImage: image), for: document.project.id)
    }

    private func cameraMoved(_ viewpoint: Viewpoint) {
        if projection != viewpoint.projection { projection = viewpoint.projection }
        updateStagePost()
        refreshGuide()
        refreshSelectionOverlay(moveOnly: true)
        viewpointSaveTask?.cancel()
        viewpointSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard let self, !Task.isCancelled else { return }
            session.setViewpoint(viewpoint)
            scheduleAutosave()
        }
    }

    // MARK: Scenes

    var sceneList: [(id: SceneID, name: String)] {
        document.project.sceneOrder.map { ($0, document.project.sceneNames[$0] ?? "Scene") }
    }

    func switchScene(_ id: SceneID) {
        guard id != scene.id else { return }
        Task {
            await saveNow(thumbnail: false)
            do {
                let (loaded, _) = try store.loadScene(id, in: projectURL)
                var doc = session.document
                doc.scene = loaded
                doc.project = (try? store.loadProjectInfo(at: projectURL).info) ?? doc.project
                session = EditSession(document: doc)
                selection = []
                selectedKeys = []
                pause()
                time = 0
                displayed = Animator.evaluate(doc, at: 0)
                previousAnimated = []
                renderer.load(doc)
                refreshDisplay()
                stage?.setViewpoint(loaded.viewpoint, notify: false)
                await saver.markSaved(0, for: projectURL)
                refreshSelectionOverlay()
                refreshGuide()
            } catch {
                app.show("Couldn't open that scene: \(error.localizedDescription)")
            }
        }
    }

    func addScene() {
        Task {
            await saveNow(thumbnail: false)
            do {
                let new = try store.addScene(named: "Scene \(document.project.sceneOrder.count + 1)", to: projectURL)
                session.updateProjectInfo { info in
                    info.sceneOrder.append(new.id)
                    info.sceneNames[new.id] = new.name
                }
                switchScene(new.id)
            } catch {
                app.show("Couldn't add a scene: \(error.localizedDescription)")
            }
        }
    }

    func duplicateScene() {
        Task {
            await saveNow(thumbnail: false)
            do {
                let copy = try store.duplicateScene(scene.id, in: projectURL)
                let info = try store.loadProjectInfo(at: projectURL).info
                session.updateProjectInfo { $0 = info }
                switchScene(copy.id)
            } catch {
                app.show("Couldn't duplicate the scene: \(error.localizedDescription)")
            }
        }
    }

    func renameScene(_ name: String) {
        guard !name.isEmpty else { return }
        perform(.renameScene(name))
    }

    // MARK: Selection

    func select(_ id: ObjectID?, additive: Bool = false) {
        guard let id else {
            if !additive { selection = [] }
            refreshSelectionOverlay()
            return
        }
        // Tapping part of a group selects the top-most group (Lego-style), unless it's already selected.
        let target = topSelectable(for: id)
        if additive {
            if let index = selection.firstIndex(of: target) { selection.remove(at: index) } else { selection.append(target) }
        } else {
            selection = [target]
        }
        Haptics.select()
        refreshSelectionOverlay()
    }

    func setSelection(_ ids: [ObjectID]) {
        selection = ids.filter { scene.objects[$0] != nil }
        refreshSelectionOverlay()
    }

    func selectAll() {
        setSelection(scene.roots.filter { scene.objects[$0]?.isVisible ?? false })
    }

    /// The highest ancestor that isn't already selected (click again to dig into a group).
    private func topSelectable(for id: ObjectID) -> ObjectID {
        let chain = [id] + scene.ancestors(of: id)
        if let selectedIndex = chain.firstIndex(where: { selection.contains($0) }), selectedIndex > 0 {
            return chain[selectedIndex - 1]
        }
        return chain.last ?? id
    }

    var selectedObjects: [SceneObject] { selection.compactMap { scene.objects[$0] } }
    var singleSelection: SceneObject? { selection.count == 1 ? scene.objects[selection[0]] : nil }

    /// Visual bounds of the selection (includes loaded models).
    var selectionBounds: Bounds? {
        renderer.visualBounds(of: selection) ?? operations.bounds.worldBounds(of: selection, in: scene)
    }

    var selectionPivot: Vec3? {
        guard let bounds = selectionBounds else { return nil }
        return Vec3(bounds.center.x, bounds.min.y, bounds.center.z)
    }

    func refreshSelectionOverlay(moveOnly: Bool = false) {
        guard let stage else { return }
        let showGizmo = (mode == .build || mode == .animate) && tool == .select && !selection.isEmpty && performPhase == .idle
            && !selection.contains(where: { scene.isEffectivelyLocked($0) })
        if moveOnly, selection.isEmpty { return }
        // Looking through a camera: no selection box around the lens you're looking through.
        if stage.lookThrough != nil {
            stage.showSelection(nil, pivot: nil, gizmoVisible: false)
            return
        }
        stage.showSelection(selection.isEmpty ? nil : selectionBounds, pivot: selectionPivot, gizmoVisible: showGizmo)
    }

    // MARK: Mode & tool

    private func modeChanged() {
        stage?.showsGrid = showGrid && mode == .build
        if mode != .animate, performPhase != .idle { cancelPerform() }
        if mode != .camera, virtualCameraActive { stopVirtualCamera() }
        updateLookThrough()
        updateStagePost()
        if mode != .build { tool = .select }
        eyedropperActive = false
        refreshSelectionOverlay()
        refreshGuide()
    }

    private func toolChanged() {
        lassoPoints = []
        scatterPreview = nil
        if tool == .scatter, selection.isEmpty {
            app.show("Select what to scatter first (a tree, a rock…), then drag an area")
        }
        refreshSelectionOverlay()
        refreshGuide()
    }

    // MARK: Library integration

    /// Operations need current asset/prefab bounds (placement, swap-to-fit, snapping).
    func refreshOperationsLibrary() {
        operations.bounds = SceneBounds(library: library.manifest)
    }

    // MARK: Building actions

    /// Where new things appear: the ground point in the middle of the view (or on top of what's there).
    func dropPoint(at screenPoint: CGPoint? = nil) -> Vec3 {
        guard let stage else { return .zero }
        let point = screenPoint ?? CGPoint(x: stage.bounds.midX, y: stage.bounds.midY)
        if let (_, hit) = stage.pickObject(at: point), hit.normal.y > 0.6 {
            return snap.grid ? Snapping.snapToGrid(hit.point, size: snap.gridSize) : hit.point
        }
        let ground = stage.groundPoint(at: point) ?? scene.viewpoint.target
        let clamped = ground.distance(to: stage.viewpoint.target) > 60 ? Vec3(stage.viewpoint.target.x, 0, stage.viewpoint.target.z) : ground
        return snap.grid ? Snapping.snapToGrid(clamped, size: snap.gridSize) : clamped
    }

    func addPrimitive(_ shape: PrimitiveShape, at screenPoint: CGPoint? = nil) {
        refreshOperationsLibrary()
        var object = factory.primitive(shape, color: currentColor)
        object.name = ObjectFactory.uniqueName(shape.displayName, in: scene)
        object = operations.placeOnGround(object, at: dropPoint(at: screenPoint))
        if screenPoint == nil { object = operations.nudgedToFreeSpot(object, in: scene) }
        if perform(operations.add(object)) { select(object.id) }
    }

    func addLight(_ type: LightType) {
        var object = factory.light(type, at: dropPoint() + Vec3(0, type == .directional ? 4 : 1.5, 0))
        object.name = ObjectFactory.uniqueName(object.name, in: scene)
        if perform(operations.add(object)) { select(object.id) }
    }

    func addCamera() {
        guard let stage else { return }
        var object = factory.camera(at: stage.viewpoint)
        object.name = ObjectFactory.uniqueName("Camera", in: scene)
        if perform(.batch("Add camera", [operations.add(object), .setActiveCamera(object.id)])) {
            select(object.id)
            app.show("Camera saved from this view")
        }
    }

    func place(_ item: LibraryItem, at screenPoint: CGPoint? = nil) {
        refreshOperationsLibrary()
        switch item {
        case let .asset(asset):
            if case let .swap(target) = libraryPurpose {
                perform(operations.swap(target, with: asset, in: scene))
                libraryPurpose = .place
                showLibrary = false
                app.show("Swapped for \(asset.name)")
            } else {
                var object = factory.asset(asset)
                object.name = ObjectFactory.uniqueName(asset.name, in: scene)
                object = operations.placeOnGround(object, at: dropPoint(at: screenPoint))
                if screenPoint == nil { object = operations.nudgedToFreeSpot(object, in: scene) }
                if perform(operations.add(object)) { select(object.id) }
            }
        case let .prefab(prefab):
            var object = factory.prefabInstance(prefab)
            object.name = ObjectFactory.uniqueName(prefab.name, in: scene)
            object = operations.placeOnGround(object, at: dropPoint(at: screenPoint))
            if screenPoint == nil { object = operations.nudgedToFreeSpot(object, in: scene) }
            if perform(operations.add(object)) { select(object.id) }
        case let .look(preset):
            applyLook(preset.look, sceneOnly: document.scene.look != nil)
            app.show("Look “\(preset.name)” applied")
        case let .script(script):
            showLibrary = false
            openScript(script)
        }
        library.markUsed(item)
    }

    func placeLibraryItem(id: String, at point: CGPoint) {
        guard let item = LibrarySearch.items(in: library.manifest, filter: .all).first(where: { $0.id == id }) else { return }
        let purpose = libraryPurpose
        libraryPurpose = .place
        place(item, at: point)
        libraryPurpose = purpose
    }

    func duplicateSelection() {
        refreshOperationsLibrary()
        guard let (command, roots) = operations.duplicate(selection, in: scene, offset: duplicateOffset()) else { return }
        if perform(command) { setSelection(roots) }
    }

    private func duplicateOffset() -> Vec3 {
        // Right next to the original, so duplicating repeatedly builds a row.
        guard let bounds = selectionBounds else { return Vec3(0.5, 0, 0.5) }
        return Vec3(max(bounds.size.x, 0.2) + 0.1, 0, 0)
    }

    func deleteSelection() {
        guard perform(operations.delete(selection, in: scene)) else {
            if !selection.isEmpty { app.show("Locked objects can't be deleted") }
            return
        }
        selection = []
        refreshSelectionOverlay()
    }

    func copySelection() {
        clipboard = FragmentTools.extract(selection, from: scene)
        app.show("Copied")
    }

    func paste() {
        guard let clipboard else { return }
        var ids = IDFactory.random
        var (copy, _) = FragmentTools.reidentified(clipboard, ids: &ids)
        copy = FragmentTools.transformRoots(copy) { t in
            var moved = t
            moved.position += Vec3(0.5, 0, 0.5)
            return moved
        }
        if perform(.insert(copy, parent: nil, index: nil)) { setSelection(copy.roots) }
    }

    func groupSelection() {
        refreshOperationsLibrary()
        guard let (command, groupID) = operations.group(selection, in: scene) else { return }
        if perform(command) { setSelection([groupID]) }
    }

    func ungroupSelection() {
        guard let object = singleSelection, object.kind == .group else { return }
        let children = object.children
        if perform(operations.ungroup(object.id, in: scene)) { setSelection(children) }
    }

    func dropSelectionToGround() {
        refreshOperationsLibrary()
        perform(operations.dropToGround(selection, in: scene))
    }

    func array(_ layout: ArrayLayout) {
        refreshOperationsLibrary()
        guard let source = selection.first, let (command, group) = operations.array(source, layout: layout, in: scene) else { return }
        if perform(command) { setSelection([group]) }
    }

    /// Smart array step: the object's own width plus a small gap.
    var arrayStep: Double {
        guard let bounds = selectionBounds else { return 1 }
        return (max(bounds.size.x, bounds.size.z) * 1.15 * 100).rounded() / 100
    }

    func scatterSelection(center: Vec3, radius: Double) {
        refreshOperationsLibrary()
        guard let source = selection.first else { return }
        var settings = ScatterSettings(
            count: scatter.count, radius: max(radius, 0.3),
            scaleMin: 1 - scatter.scaleVariation, scaleMax: 1 + scatter.scaleVariation,
            spacing: scatter.spacing, seed: UInt64.random(in: 1 ... UInt64.max)
        )
        settings.rotationJitter = 360
        guard let (command, group) = operations.scatter(source, center: center, settings: settings, in: scene) else { return }
        if perform(command) {
            setSelection([group])
            let placed = scene.objects[group]?.children.count ?? 0
            app.show(placed < scatter.count ? "Placed \(placed) (area too small for \(scatter.count))" : "Scattered \(placed)")
        }
    }

    func align(_ axis: CoreAxis, _ mode: AlignMode) {
        refreshOperationsLibrary()
        perform(operations.align(selection, axis: axis, mode: mode, in: scene))
    }

    func distribute(_ axis: CoreAxis) {
        refreshOperationsLibrary()
        perform(operations.distribute(selection, axis: axis, in: scene))
    }

    func setColor(_ color: ColorValue?) {
        currentColor = color ?? currentColor
        guard !selection.isEmpty else { return }
        perform(operations.setColor(selection, color, in: scene))
    }

    func setProperty(_ key: PropertyKey, _ value: PropertyValue?, coalesce: String? = nil) {
        let changes = selection.map { PropertyChange(object: $0, key: key, value: value) }
        perform(.setProperties(changes), coalesceKey: coalesce)
    }

    func toggleLock(_ id: ObjectID) {
        guard let object = scene.objects[id] else { return }
        perform(operations.setFlag([id], key: .locked, !object.isLocked))
    }

    func toggleVisible(_ id: ObjectID) {
        guard let object = scene.objects[id] else { return }
        perform(operations.setFlag([id], key: .visible, !object.isVisible))
    }

    func rename(_ id: ObjectID, to name: String) {
        guard !name.isEmpty, scene.objects[id]?.name != name else { return }
        perform(.rename(id, name))
    }

    func moveToTopLevel(_ id: ObjectID) {
        perform(operations.reparent([id], to: nil, in: scene))
    }

    func reparent(_ ids: [ObjectID], to parent: ObjectID?) {
        perform(operations.reparent(ids, to: parent, in: scene))
    }

    func beginSwap() {
        guard let target = selection.first else { return }
        libraryPurpose = .swap(target)
        showLibrary = true
    }

    func frameSelection() {
        stage?.frame(selection.isEmpty ? allBounds : selectionBounds)
    }

    var allBounds: Bounds? { renderer.visualBounds(of: scene.roots) }

    // MARK: Transform (gizmo, joystick, drag, inspector)

    func translateSelection(by delta: Vec3, gesture: String) {
        perform(operations.translate(selection, by: delta, in: scene), coalesceKey: gesture)
    }

    func rotateSelection(by angle: Double, axis: CoreAxis, gesture: String) {
        guard let pivot = selectionBounds?.center else { return }
        perform(operations.rotate(selection, by: Quat(angle: angle, axis: axis.unit), around: pivot, in: scene), coalesceKey: gesture)
    }

    func scaleSelection(by factor: Vec3, gesture: String) {
        guard let pivot = selectionPivot else { return }
        perform(operations.scale(selection, by: factor, around: pivot, in: scene), coalesceKey: gesture)
    }

    /// Snaps the selection at the end of a move: grid, flush against neighbours, rotation steps.
    func finishTransform(gesture: String) {
        refreshOperationsLibrary()
        var commands: [EditCommand] = []
        if let bounds = selectionBounds {
            var correction = Vec3.zero
            if snap.grid {
                let pivot = Vec3(bounds.center.x, bounds.min.y, bounds.center.z)
                let snapped = Snapping.snapToGrid(pivot, size: snap.gridSize)
                correction = snapped - pivot
                correction.y = 0
            }
            if snap.objects {
                let moved = Bounds(min: bounds.min + correction, max: bounds.max + correction)
                let others = scene.roots.filter { !selection.contains($0) }.compactMap { renderer.visualBounds(of: [$0]) }
                let offset = Snapping.objectSnapOffset(moving: moved, others: others, threshold: snap.objectThreshold)
                correction += offset
            }
            if snap.ground, abs(bounds.min.y + correction.y) < snap.objectThreshold {
                correction.y = -bounds.min.y
            }
            if correction.lengthSquared > 1e-10 {
                commands.append(operations.translate(selection, by: correction, in: scene))
            }
        }
        for command in commands {
            perform(command, coalesceKey: gesture)
        }
        endGesture()
    }

    func snapRotation(gesture: String) {
        guard snap.rotation else {
            endGesture()
            return
        }
        var changes: [PropertyChange] = []
        for object in selectedObjects {
            let euler = object.transform.rotation.eulerDegrees
            let snapped = Vec3(Snapping.snapAngle(euler.x, step: snap.rotationStep),
                               Snapping.snapAngle(euler.y, step: snap.rotationStep),
                               Snapping.snapAngle(euler.z, step: snap.rotationStep))
            changes.append(PropertyChange(object: object.id, key: .rotation, value: .quat(Quat(eulerDegrees: snapped))))
        }
        perform(.setProperties(changes), coalesceKey: gesture)
        endGesture()
    }

    func setTransform(_ id: ObjectID, _ transform: CoreTransform) {
        perform(operations.setTransform(id, transform))
    }

    // MARK: Prefabs

    func saveSelectionAsPrefab(name: String, replaceSelection: Bool) {
        refreshOperationsLibrary()
        guard let fragment = operations.prefabFragment(selection, in: scene) else { return }
        let thumbEntity = selectionEntityForThumbnail()
        let finalName = name.isEmpty ? (singleSelection?.name ?? "My build") : name
        Task {
            let prefab = await library.savePrefab(name: finalName, fragment: fragment, thumbnailFrom: thumbEntity)
            refreshOperationsLibrary()
            if replaceSelection, let (command, instance) = operations.replaceWithPrefab(selection, prefab: prefab, in: scene) {
                if perform(command) { setSelection([instance]) }
            }
            Haptics.success()
            app.show("Saved “\(prefab.name)” to your library")
        }
    }

    /// Pushes edits of an unpacked group back into its prefab (all instances update).
    func updatePrefab(_ prefabID: PrefabID) {
        refreshOperationsLibrary()
        guard let fragment = operations.prefabFragment(selection, in: scene),
              let existing = library.manifest.prefab(prefabID) else { return }
        let thumbEntity = selectionEntityForThumbnail()
        Task {
            _ = await library.savePrefab(name: existing.name, fragment: fragment, replacing: prefabID, thumbnailFrom: thumbEntity)
            app.show("Updated “\(existing.name)” everywhere")
        }
    }

    func unpackSelection() {
        refreshOperationsLibrary()
        guard let object = singleSelection, let prefabID = object.kind.prefabID,
              let prefab = library.manifest.prefab(prefabID),
              let command = operations.unpack(object.id, prefab: prefab, in: scene) else { return }
        if perform(command) { setSelection(scene.roots.suffix(prefab.fragment.roots.count).map { $0 }) }
    }

    private func selectionEntityForThumbnail() -> Entity? {
        let holder = Entity()
        for id in selection {
            guard let node = renderer.node(for: id) else { continue }
            let clone = node.clone(recursive: true)
            clone.transform = RealityKit.Transform(matrix: node.transformMatrix(relativeTo: nil))
            holder.addChild(clone)
        }
        return holder.children.isEmpty ? nil : holder
    }

    // MARK: Look

    var look: Look { document.effectiveLook }
    var lookIsSceneOnly: Bool { document.scene.look != nil }

    /// Edits the look (scene override if this scene has its own look, else the project's).
    func applyLook(_ look: Look, sceneOnly: Bool? = nil, coalesce: String? = nil) {
        let scoped = sceneOnly ?? lookIsSceneOnly
        perform(.setLook(look, scope: scoped ? .scene : .project), coalesceKey: coalesce)
    }

    func updateLook(coalesce: String? = nil, _ change: (inout Look) -> Void) {
        var copy = look
        change(&copy)
        applyLook(copy, coalesce: coalesce)
    }

    func setLookSceneOnly(_ sceneOnly: Bool) {
        if sceneOnly {
            perform(.setLook(document.project.look, scope: .scene))
        } else {
            perform(.setLook(nil, scope: .scene))
        }
    }

    /// Takes a colour out of the palette. Objects painted with it keep their colour (the slot is kept, hidden).
    func removePaletteSwatch(_ slot: Int) {
        guard look.palette.swatches.indices.contains(slot) else { return }
        if currentColor == .palette(slot) { currentColor = .rgba(look.palette.color(at: slot)) }
        updateLook { $0.palette.remove(slot: slot) }
        Haptics.tap()
    }

    /// Eyedropper: take an object's colour into a palette slot and bind the object to it.
    func eyedrop(object id: ObjectID) {
        guard let object = scene.objects[id], let color = object.color?.resolved(in: look.palette) else {
            app.show("That object has no colour of its own")
            return
        }
        let slot = eyedropperSlot
        var newLook = look
        while newLook.palette.swatches.count <= slot {
            newLook.palette.swatches.append(.init(name: "Colour \(newLook.palette.swatches.count + 1)", color: .blockout))
        }
        newLook.palette.swatches[slot].color = color
        let scope: LookScope = lookIsSceneOnly ? .scene : .project
        perform(.batch("Eyedropper", [
            .setLook(newLook, scope: scope),
            .setProperties([PropertyChange(object: id, key: .color, value: .color(.palette(slot)))])
        ]))
        eyedropperActive = false
        Haptics.success()
    }

    // MARK: Drawing

    @ObservationIgnored var drawingObjectTarget: ObjectID?

    /// The guide surface for the current settings.
    var currentGuide: GuideSurface? {
        guard tool == .draw, mode == .build, let stage else { return nil }
        let center = selectionBounds.map { Vec3($0.center.x, $0.min.y, $0.center.z) } ?? Vec3(stage.viewpoint.target.x, 0, stage.viewpoint.target.z)
        let size = draw.guideSize
        switch draw.guide {
        case .plane:
            let normal: Vec3
            switch draw.planeLock {
            case .ground: normal = .unitY
            case .front: normal = .unitZ
            case .side: normal = .unitX
            case .view:
                // Snap to the principal axis closest to the view direction (Feather-style lock).
                let forward = (stage.viewpoint.eye - stage.viewpoint.target).normalized
                let axes: [Vec3] = [.unitX, .unitY, .unitZ]
                let best = axes.max { abs($0.dot(forward)) < abs($1.dot(forward)) } ?? .unitY
                normal = best
            }
            let origin = normal == .unitY ? Vec3(center.x, center.y, center.z) : Vec3(center.x, center.y + size / 2, center.z)
            return .plane(origin: origin + normal * draw.planeOffset, normal: normal)
        case .box:
            return .box(center: center + Vec3(0, size / 2, 0), size: Vec3(size, size, size))
        case .cylinder:
            return .cylinder(base: center, radius: size / 2, height: size)
        case .sphere:
            return .sphere(center: center + Vec3(0, size / 2, 0), radius: size / 2)
        case .object:
            return nil
        }
    }

    func refreshGuide() {
        stage?.guide.show(currentGuide)
    }

    /// Commits a finished stroke as a drawn object (one undo step).
    func commitStroke(points rawPoints: [Vec3], pressures: [Double], normals: [Vec3], guide: GuideSurface?) {
        guard rawPoints.count >= 2 || draw.style == .tube else { return }
        let widths = pressures.map { draw.width * (0.35 + 0.65 * min(max($0, 0), 1)) }
        let filtered = StrokeFilter.process(points: rawPoints, widths: widths, smoothing: draw.smoothing)
        var points = filtered.points
        let strokeWidths = filtered.widths
        guard !points.isEmpty else { return }

        // Plane normal for ribbons/extrusions.
        var planeNormal = Vec3.unitY
        if case let .plane(_, normal)? = guide { planeNormal = normal }
        if let averaged = normals.reduce(nil as Vec3?, { ($0 ?? .zero) + $1 })?.normalized, averaged.length > 0.5,
           !(guide.map {
               if case .plane = $0 {
                   true
               } else {
                   false
               }
           } ?? false) {
            planeNormal = averaged
        }

        // Object origin: the lathe axis base, or the first point.
        let origin: Vec3
        switch draw.style {
        case .lathe:
            let center = selectionBounds.map { Vec3($0.center.x, $0.min.y, $0.center.z) } ?? Vec3(
                stage?.viewpoint.target.x ?? 0,
                0,
                stage?.viewpoint.target.z ?? 0
            )
            origin = Vec3(center.x, points.map(\.y).min() ?? center.y, center.z)
        default:
            origin = points[0]
        }
        points = points.map { $0 - origin }
        var strokes = [DrawingRecipe.Stroke(points: points, widths: strokeWidths)]
        if draw.mirror, draw.style != .lathe {
            let mirrorX = (currentGuideCenterX ?? origin.x) - origin.x
            let mirrored = points.map { Vec3(2 * mirrorX - $0.x, $0.y, $0.z) }
            strokes.append(DrawingRecipe.Stroke(points: mirrored, widths: strokeWidths))
        }
        let recipe = DrawingRecipe(style: draw.style, strokes: strokes, normal: planeNormal,
                                   depth: draw.extrudeDepth, segments: draw.style == .lathe ? max(draw.segments, 6) : draw.segments)
        guard !DrawingMesher.mesh(for: recipe).isEmpty else {
            app.show(draw.style == .extrude ? "Draw a closed outline to extrude" : "That stroke was too small")
            return
        }
        var object = factory.drawing(recipe, transform: CoreTransform(position: origin), color: currentColor)
        object.name = ObjectFactory.uniqueName(object.name, in: scene)
        perform(operations.add(object))
    }

    private var currentGuideCenterX: Double? {
        switch currentGuide {
        case let .plane(origin, _): origin.x
        case let .box(center, _): center.x
        case let .cylinder(base, _, _): base.x
        case let .sphere(center, _): center.x
        case nil: selectionBounds?.center.x
        }
    }

    // MARK: Snapshot

    func exportSnapshot(framing: Framing, longSide: Int, throughCamera: Bool = false) async -> URL? {
        do {
            let image: CGImage
            if throughCamera, displayed.camera != nil {
                let exporter = VideoExporter(document: session.document, library: library, rigs: rigCache)
                guard let frame = try await exporter.images(at: time, framings: [framing], longSide: longSide).first else { return nil }
                image = frame
            } else {
                image = try await offscreen.snapshot(of: renderer, viewpoint: stage?.viewpoint ?? scene.viewpoint,
                                                     framing: framing, longSide: longSide, viewportSize: stage?.bounds.size)
            }
            guard let png = OffscreenRenderer.pngData(image) else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let name = "\(ProjectStore.sanitize(scene.name)) \(framing.rawValue.replacingOccurrences(of: ":", with: "x")) \(formatter.string(from: Date())).png"
            let url = projectURL.appendingPathComponent(ProjectLayout.rendersFolder).appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            Haptics.success()
            return url
        } catch {
            app.show("Snapshot failed: \(error)")
            return nil
        }
    }
}
