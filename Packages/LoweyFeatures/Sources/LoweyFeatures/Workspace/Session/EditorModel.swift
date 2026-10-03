import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine
import Observation
import os
import UIKit

/// One open project: the edit session (document + undo), selection, tools, the stage, playback, and the state every
/// panel shares. Every change to the document goes through `perform` (one `EditCommand`, one undo step).
@Observable
@MainActor
final class EditorModel {
    @ObservationIgnored unowned let app: AppModel
    private(set) var projectURL: URL
    var session: EditSession
    var document: Document { session.document }
    /// The scene as edited (what's saved).
    var baseScene: CoreScene { session.document.scene }
    /// The scene as shown: animation evaluated at the playhead. Tools read this, so moving an animated object moves
    /// what you see and the change becomes a key at the playhead.
    var scene: CoreScene {
        _ = displayRevision
        return displayed.scene
    }

    /// The document with the scene as shown.
    var displayDocument: Document { Document(project: session.document.project, scene: displayed.scene) }

    var selection: [ObjectID] = [] {
        didSet {
            guard selection != oldValue else { return }
            if !inkStrokes.isEmpty { inkStrokes = [] }
            if AppIdentity.isUITesting { trail("sel=[\(selection.compactMap { scene.objects[$0]?.name }.joined(separator: ","))]") }
            refreshSelectionOverlay()
        }
    }

    /// UI tests only: the recent selection and command history (an accessibility value).
    private(set) var debugTrail: [String] = []

    // MARK: Tools & chrome

    var tool: StageTool = .select {
        didSet { if tool != oldValue { toolChanged() } }
    }

    var gizmoMode: GizmoMode = .move {
        didSet {
            stage?.gizmoMode = gizmoMode
            refreshSelectionOverlay()
        }
    }

    var snap = SnapSettings()
    var draw = DrawSettings() {
        didSet { if draw != oldValue { refreshGuide() } }
    }

    var shadowBrush = ShadowBrushSettings()
    var ink = InkSettings()
    var flipbook = FlipbookSettings()
    var animationView = AnimationViewSettings()
    /// Strokes picked in the selected ink drawing (Ink ▸ Select strokes).
    var inkStrokes: Set<Int> = []
    var scatter = ScatterPanelSettings()
    /// The current colour: new blockout, strokes and "paint" use it.
    var currentColor: ColorValue = .palette(0)
    var openPanel: ClusterPanel?
    var sheet: EditorSheet?
    var libraryPurpose: LibraryPurpose = .place
    /// Four-finger tap: everything but the stage hides.
    var chromeHidden = false
    /// Playback fades the chrome after two seconds (a touch brings it back).
    var chromeFaded = false
    var showsGrid = true {
        didSet { stage?.showsGrid = showsGrid }
    }

    /// Mirrors the stage camera's projection (for the orthographic toggle).
    var projection: Viewpoint.Projection = .perspective
    /// Pick (eyedropper): the next tap takes an object's colour into a palette slot.
    var pickActive = false
    var pickSlot = 0
    /// Lasso polygon, scatter circle and Pencil hover (screen space).
    var lassoPoints: [CGPoint] = []
    var hoverPoint: CGPoint?
    var hoverHeight: Double = 0
    var scatterPreview: (center: CGPoint, radius: CGFloat)?
    /// The Director view: the stage shows the shot camera with the delivery frame (else the free Work view).
    var directorView = false {
        didSet { if directorView != oldValue { refreshSelectionOverlay() } }
    }

    var deliveryFraming: Framing = .landscape
    var showsThirds = true
    var showsSafeAreas = false
    /// The heading of the work view in degrees (the joystick's compass).
    var viewYaw: Double = 0

    // MARK: Time & animation

    var time: Double = 0
    var isPlaying = false
    var timelineMode: TimelineMode = .compose
    /// In Keyframe mode, edits become keys at the playhead.
    var autoKey = true
    /// Points per second.
    var timelineZoom: Double = 90
    var timelineStart: Double = 0
    var timelineCollapsed = false
    var selectedKeys: Set<KeyRef> = []
    var keyBoxSelect = false
    var expandedObjects: Set<ObjectID> = []
    var collapsedGroups: Set<ObjectID> = []
    var presetDuration: Double?
    var presetStrength: Double = 1
    var stagger = StaggerPanelSettings()
    var performSettings = PerformSettings()
    var performPhase: PerformPhase = .idle
    /// A number performed with a slider (glow, light, focal length…).
    var performSliderKey: PropertyKey?
    var graphKey: KeyRef?
    var virtualCameraActive = false
    var virtualCameraScale: Double = 1

    // MARK: Words, sound, scripts, export

    var selectedAudio: String?
    var snapToWords = true
    var isRecordingVoice = false
    var transcribing: String?
    var transcriptLanguage = "en-US"
    /// Selected words in the transcript (indices into `timeline.words`).
    var wordSelection: ClosedRange<Int>?
    var waveforms: [String: [Float]] = [:]
    var scriptSource = ""
    var scriptName = "My script"
    var scriptLog: [String] = []
    var scriptRunning = false
    var exportProgress: Double?
    var exportWaiting = false
    var exportResults: [URL] = []
    /// A Scene Script waiting for a decision (AI proposes, you decide).
    var proposal: ScriptProposal?
    var characterBuilderTarget: ObjectID?
    var faceActive = false
    var faceStatus: String?
    let faceMonitor = FaceMonitor()
    let performance = PerformanceMonitor()
    private(set) var displayRevision = 0
    private(set) var lastSaved: Date?
    private(set) var isSaving = false

    // MARK: Not observed

    @ObservationIgnored weak var stage: StageView?
    @ObservationIgnored var displayed: AnimatedScene
    @ObservationIgnored var previousAnimated = Set<ObjectID>()
    @ObservationIgnored var operations = Operations()
    @ObservationIgnored var factory = ObjectFactory()
    @ObservationIgnored let clock = PlaybackClock()
    @ObservationIgnored var keyClipboard: KeyClipboard?
    @ObservationIgnored var clipboard: SceneFragment?
    @ObservationIgnored var takes: [PerformChannel: PerformTake] = [:]
    @ObservationIgnored var performOverride: [ObjectID: CoreTransform] = [:]
    @ObservationIgnored var propertyOverride: [ObjectID: [PropertyKey: PropertyValue]] = [:]
    @ObservationIgnored var performChannels = Set<PerformChannel>()
    @ObservationIgnored var performTouching = false
    @ObservationIgnored var virtualCamera: VirtualCameraController?
    @ObservationIgnored var exportTask: Task<Void, Never>?
    @ObservationIgnored var eulerMemory: [ObjectID: Vec3] = [:]
    @ObservationIgnored var lastRevisionBump: CFTimeInterval = 0
    @ObservationIgnored var chromeFadeTask: Task<Void, Never>?
    @ObservationIgnored lazy var audioPlayback = AudioPlayback(folder: audioFolder)
    @ObservationIgnored let voiceRecorder = VoiceRecorder()
    @ObservationIgnored var recordingStart: Double = 0
    @ObservationIgnored var decodedAudio: [String: PCMAudio] = [:]
    @ObservationIgnored var faceCapture: FaceCapture?
    @ObservationIgnored var faceLink: FaceLinkReceiver?
    @ObservationIgnored let facePerformer = FacePerformer()
    @ObservationIgnored let faceClock = PlaybackClock()
    @ObservationIgnored var faceDirty = false
    @ObservationIgnored var mediaImages: [String: CGImage] = [:]
    @ObservationIgnored lazy var videoPreview: VideoFrames = {
        let frames = VideoFrames(exact: false)
        frames.onFrame = { [weak self] in self?.stage?.redraw() }
        return frames
    }()

    @ObservationIgnored var overlayCache = StageOverlayCache()
    @ObservationIgnored var motionCache = MotionViewCache()
    @ObservationIgnored let store: ProjectStore
    @ObservationIgnored private let saver: DocumentSaver
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored var viewpointSaveTask: Task<Void, Never>?
    @ObservationIgnored let logger = Logger(subsystem: AppIdentity.subsystem, category: "editor")

    var library: LibraryModel { app.library }

    init(app: AppModel, projectURL: URL, document: Document) {
        self.app = app
        self.projectURL = projectURL
        session = EditSession(document: document)
        displayed = Animator.evaluate(document, at: 0)
        store = app.projectStore
        saver = DocumentSaver(store: app.projectStore)
        operations = Operations(library: app.library.manifest)
        refreshDisplay()
        let url = projectURL
        let saver = saver
        Task { await saver.markSaved(0, for: url) }
    }

    /// The project closes: stop everything that runs on its own.
    func tearDown() {
        pause()
        stopFaceCapture()
        stopVirtualCamera()
        clock.stop()
        chromeFadeTask?.cancel()
        stage?.frameSource = nil
    }

    func bumpDisplayRevision() {
        displayRevision &+= 1
    }

    func trail(_ entry: String) {
        debugTrail = Array((debugTrail + [entry]).suffix(12))
    }

    // MARK: Perform / undo / redo

    /// Applies a command (the only way the document changes).
    @discardableResult
    func perform(_ command: EditCommand?, coalesceKey: String? = nil) -> Bool {
        guard let command else { return false }
        do {
            let changes = try session.perform(keyed(command), coalesceKey: coalesceKey)
            if AppIdentity.isUITesting { trail("cmd=\(command.label)") }
            refreshDisplay(changes)
            afterChange()
            return true
        } catch {
            logger.error("Command failed: \(String(describing: error))")
            app.show("That didn't work: \(error)", kind: .error)
            HmmHaptics.play(.error)
            return false
        }
    }

    func endGesture() {
        session.endCoalescing()
        if performPhase == .recording, performedCamera != nil { performTouching = false }
    }

    var canUndo: Bool { session.canUndo }
    var canRedo: Bool { session.canRedo }
    var undoTitle: String { session.undoTitle }
    var redoTitle: String { session.redoTitle }

    func undo() {
        do {
            guard let changes = try session.undo() else { return }
            refreshDisplay(changes)
            afterChange()
        } catch {
            app.show("Undo failed: \(error)", kind: .error)
        }
    }

    func redo() {
        do {
            guard let changes = try session.redo() else { return }
            refreshDisplay(changes)
            afterChange()
        } catch {
            app.show("Redo failed: \(error)", kind: .error)
        }
    }

    private func afterChange() {
        let kept = selection.filter { scene.objects[$0] != nil }
        if kept != selection { selection = kept }
        selectedKeys = selectedKeys.filter { key in timeline.track(key.track)?.key(at: key.time) != nil }
        operations.bounds = SceneBounds(library: library.manifest)
        refreshSelectionOverlay()
        scheduleAutosave()
        app.bridge.notify("scene", ["revision": String(session.revision)])
    }

    // MARK: Autosave (debounced, off the main thread, atomic)

    func scheduleAutosave() {
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
        isSaving = true
        do {
            _ = try await saver.save(document, revision: revision, to: projectURL)
            lastSaved = Date()
        } catch {
            app.show("Autosave failed: \(error.localizedDescription)", kind: .error)
        }
        isSaving = false
        if thumbnail { await writeProjectThumbnail() }
    }

    /// The Theater card: a still of the work view and a short loop through the shot camera.
    private func writeProjectThumbnail() async {
        let thumbnailer = app.thumbnailer
        let viewpoint = stage?.viewpoint ?? baseScene.viewpoint
        guard let still = try? await thumbnailer.still(document, viewpoint: viewpoint, width: 640, height: 360, catalog: library.catalog,
                                                       models: library.models) else { return }
        if let png = UIImage(cgImage: still).pngData() { try? store.writeThumbnail(png, for: projectURL) }
        let loop = await (try? thumbnailer.loop(document, catalog: library.catalog, models: library.models)) ?? []
        if loop.count > 1 { try? Thumbnailer.writeLoop(loop, to: projectURL.appendingPathComponent(Thumbnailer.loopFile)) }
        app.setThumbnail(UIImage(cgImage: still), loop: loop, for: document.project.id)
    }

    /// Back from the background: the video frames and stage pick up where they were.
    func resumeFromBackground() {
        stage?.redraw()
    }
}
