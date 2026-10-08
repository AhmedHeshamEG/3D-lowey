import Foundation
import HmmBoardUI
import HmmDesign
import HmmDocuments
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
    var displayDocument: Document { Document(project: (historyPreview ?? session.document).project, scene: displayed.scene) }

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
        didSet { if tool != oldValue { toolChanged(from: oldValue) } }
    }

    var gizmoMode: GizmoMode = .move {
        didSet {
            stage?.gizmoMode = gizmoMode
            refreshSelectionOverlay()
        }
    }

    var snap = SnapSettings() {
        didSet { if snap != oldValue { workspaceChanged() } }
    }

    var draw = DrawSettings() {
        didSet { if draw != oldValue { refreshGuide() } }
    }

    var shadowBrush = ShadowBrushSettings()
    var ink = InkSettings()
    var flipbook = FlipbookSettings()
    var colourPaint = ColourPaintSettings()
    /// Cast ▸ Rig: drawing bones, painting weights, the person rig's dots.
    var rigging = RigSettings() {
        didSet {
            guard rigging.joint != oldValue.joint || rigging.mode != oldValue.mode || rigging.target != oldValue.target
                || rigging.preview != oldValue.preview || (rigging.person == nil) != (oldValue.person == nil) else { return }
            refreshModelOverlay()
            stage?.redraw()
        }
    }

    /// The drawing tool the brush library chooses a brush for.
    var brushTool: BrushTool = .ink
    /// The drawing guide over the frame (flipbooks) and on the guide plane (ink); kept in `workspace.json`.
    var frameGuide: DrawingGuide?
    var planeGuide: DrawingGuide?
    @ObservationIgnored var strokesDrawn = 0
    var animationView = AnimationViewSettings()
    /// Strokes picked in the selected ink drawing (Ink ▸ Select strokes).
    var inkStrokes: Set<Int> = []
    var scatter = ScatterPanelSettings()
    /// The Model tool on the stage (`EditorModel+Modeling`).
    var modeling = ModelingState() {
        didSet { if modeling.overlayKey != oldValue.overlayKey { refreshModelOverlay() } }
    }

    /// Precision, printing and building settings (`EditorModel+Precision`).
    var precision = PrecisionState() {
        didSet { if precision != oldValue { precisionChanged(from: oldValue) } }
    }

    /// The unit lengths are shown and typed in (`workspace.json`).
    var units: LengthUnit = .centimetre {
        didSet { if units != oldValue { workspaceChanged() } }
    }

    /// Bumped as the camera moves while numbers float on the stage, so they follow what they measure.
    var viewRevision = 0
    /// The current colour: new blockout, strokes and "paint" use it.
    var currentColor: ColorValue = .palette(0)
    var openPanel: ClusterPanel?
    var modelPage: ModelPage = .add
    var sheet: EditorSheet?
    var libraryPurpose: LibraryPurpose = .place
    /// Four-finger tap: everything but the stage hides.
    var chromeHidden = false
    /// Playback fades the chrome after two seconds (a touch brings it back).
    var chromeFaded = false
    var showsGrid = true {
        didSet {
            stage?.showsGrid = showsGrid
            if showsGrid != oldValue { workspaceChanged() }
        }
    }

    /// Mirrors the stage camera's projection (for the orthographic toggle).
    var projection: Viewpoint.Projection = .perspective
    /// Pick (eyedropper): the next tap takes an object's colour into a palette slot.
    var pickActive = false
    var pickSlot = 0
    /// Lasso polygon, scatter circle and Pencil hover (screen space).
    var lassoPoints: [CGPoint] = []
    /// Where the Pencil hovers (the stage draws the point itself: `EditorModel+Pointer`).
    @ObservationIgnored var hoverPoint: CGPoint?
    @ObservationIgnored var brushResizing = false
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
    /// The timeline is on call: hidden until asked for (`EditorModel+Workspace`).
    var timelinePresence: TimelinePresence = .hidden {
        didSet { if timelinePresence != oldValue { workspaceChanged() } }
    }

    var timelineHeight = ProjectWorkspace.defaultTimelineHeight
    var selectedKeys: Set<KeyRef> = []
    /// Picked clip segments (ids), moved and changed together.
    var selectedClips: Set<String> = []
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
    /// Flying the shot camera (sticks or a game controller).
    var flying = false
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
    /// The voice, triggers, the chosen joint and the picked take (`EditorModel+Live`).
    let live = LiveState()
    let performance = PerformanceMonitor()
    private(set) var displayRevision = 0
    /// The Motion row's speed for the next motion tapped (`EditorModel+LoopMotion`).
    var motionSpeed = 1.0
    /// The object a hold menu's Rename is about (`ObjectRenameAlert`).
    var renamingObject: ObjectID?
    /// The project's Schizzo board, once it has been asked for, and whether it covers the stage.
    var board: BoardModel?
    var boardShown = false
    /// Pictures pinned from the board, floating over the stage (`workspace.json`).
    var references: [ReferenceCard] = []
    /// The history scrubber, while it's open (`EditorModel+HistoryScrubber`).
    var historyScrub: HistoryScrubState?
    var lastSaved: Date?
    var isSaving = false
    /// Where the selection sits on the stage (view points), for the floating inspector; settles after the camera does.
    var selectionScreenRect: CGRect?

    // MARK: Not observed

    @ObservationIgnored weak var stage: StageView?
    /// The surface a bone is being drawn through, kept for the length of the stroke (`EditorModel+RigSteps`).
    @ObservationIgnored var boneSurface: BoneSurface?
    /// What the silent load meter has done to the preview (`EditorModel+Load`).
    @ObservationIgnored var adaptivePreview = AdaptivePreview(home: PreviewQuality.current.tier)
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
    /// Shapes shown instead of the document's while a push/pull is dragged (committed as one command on release).
    @ObservationIgnored var kindOverride: [ObjectID: ObjectKind] = [:]
    @ObservationIgnored var performChannels = Set<PerformChannel>()
    /// Painted strokes commit one after another (`EditorModel+Paint`); each stroke gets a number.
    @ObservationIgnored var paintCommits: Task<Void, Never>?
    @ObservationIgnored var paintStrokes = 0
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
    @ObservationIgnored let flyer = FlyPerformer()
    @ObservationIgnored let store: ProjectStore
    /// The open scene's history journal (`EditorModel+History`).
    @ObservationIgnored var journal: HistoryJournal<EditCommand>
    @ObservationIgnored var checkpointPolicy = CheckpointPolicy()
    @ObservationIgnored var checkpointedRevision = 0
    @ObservationIgnored var idleCheckpointTask: Task<Void, Never>?
    /// When the current stretch of work began (an automatic version every hour of it).
    @ObservationIgnored var workStarted = Date()
    @ObservationIgnored var historyCursor: HistoryCursor?
    /// The earlier moment the stage shows while the scrubber is dragged back (nil = now).
    @ObservationIgnored var historyPreview: Document?
    @ObservationIgnored var viewpointSaveTask: Task<Void, Never>?
    @ObservationIgnored var workspaceSaveTask: Task<Void, Never>?
    @ObservationIgnored var selectionRectTask: Task<Void, Never>?
    @ObservationIgnored var measuredSelection: [ObjectID] = []
    /// The template the project began from and how it shows (`workspace.json`).
    @ObservationIgnored var workspace = ProjectWorkspace()
    @ObservationIgnored let logger = Logger(subsystem: AppIdentity.subsystem, category: "editor")

    var library: LibraryModel { app.library }

    init(app: AppModel, projectURL: URL, opened: ProjectHistory.Opened) {
        self.app = app
        self.projectURL = projectURL
        session = opened.session
        journal = opened.journal
        displayed = Animator.evaluate(opened.session.document, at: 0)
        store = app.projectStore
        operations = Operations(library: app.library.manifest)
        checkpointedRevision = session.revision
        refreshDisplay()
        loadWorkspace()
        saveAutomaticVersion(named: String(localized: "Opened \(Date().formatted(date: .abbreviated, time: .shortened))"))
    }

    /// The project closes: stop everything that runs on its own.
    func tearDown() {
        pause()
        board?.close()
        stopFaceCapture()
        stopVoice()
        stopVirtualCamera()
        clock.stop()
        chromeFadeTask?.cancel()
        idleCheckpointTask?.cancel()
        selectionRectTask?.cancel()
        saveWorkspace()
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
        settleHistoryBeforeEditing()
        do {
            let changes = try session.perform(keyed(command), coalesceKey: coalesceKey)
            if AppIdentity.isUITesting { trail("cmd=\(command.label)") }
            refreshDisplay(changes)
            afterChange()
            return true
        } catch {
            logger.error("Command failed: \(String(describing: error))")
            app.show("That didn't work: \(String(describing: error))", kind: .error)
            HmmHaptics.play(.error)
            return false
        }
    }

    func endGesture() {
        session.endCoalescing()
        journalChanged()
        if performPhase == .recording, performedCamera != nil { performTouching = false }
    }

    var canUndo: Bool { session.canUndo }
    var canRedo: Bool { session.canRedo }
    var undoTitle: String { session.undoTitle }
    var redoTitle: String { session.redoTitle }

    func undo() {
        if historyScrub != nil { closeHistory() }
        do {
            guard let changes = try session.undo() else { return }
            loadOlderUndoIfNeeded()
            refreshDisplay(changes)
            afterChange()
        } catch {
            app.show("Undo failed: \(String(describing: error))", kind: .error)
        }
    }

    func redo() {
        if historyScrub != nil { closeHistory() }
        do {
            guard let changes = try session.redo() else { return }
            refreshDisplay(changes)
            afterChange()
        } catch {
            app.show("Redo failed: \(String(describing: error))", kind: .error)
        }
    }

    private func afterChange() {
        let kept = selection.filter { scene.objects[$0] != nil }
        if kept != selection { selection = kept }
        selectedKeys = selectedKeys.filter { key in timeline.track(key.track)?.key(at: key.time) != nil }
        operations.bounds = SceneBounds(library: library.manifest)
        refreshSelectionOverlay()
        if tool == .model {
            validateModelPick()
            refreshModelOverlay()
        }
        if tool == .rig { refreshModelOverlay() }
        refreshPrecisionOverlay()
        journalChanged()
        app.bridge.notify("scene", ["revision": String(session.revision)])
    }

    /// Back from the background: the video frames and stage pick up where they were.
    func resumeFromBackground() {
        stage?.redraw()
    }
}
