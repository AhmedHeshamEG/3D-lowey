import HmmDesign
import LoweyCore
import SwiftUI

/// The open project (docs/LAYOUT.md): the stage owns the screen. Document and app things in the top-left cluster,
/// the making tools in the top-right one, two context sliders and undo / redo in the sidebar, the inspector floating
/// beside the selection, and time on call: the timeline is hidden until the corner control or Animate calls it, as a
/// slim transport or the whole timeline at the height this project remembers. Four fingers hide everything but the
/// stage; playback fades the chrome after two seconds.
struct EditorScreen: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.preferredPencilSqueezeAction) private var squeezeAction
    @AppStorage(AppSettings.showsPerformanceHUD) private var showsHUD = false
    @AppStorage(AppSettings.boardEnabled) private var boardEnabled = true

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                stageArea
                if !editor.chromeHidden, editor.timelinePresence != .hidden {
                    TimelineDivider(editor: editor, maximum: geometry.size.height * 0.6)
                    if editor.timelinePresence == .transport {
                        TransportBar(editor: editor)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        // Time runs left to right in every language (as on a ruler); the panels around it mirror.
                        TimelinePane(editor: editor)
                            .environment(\.layoutDirection, .leftToRight)
                            .frame(height: min(editor.timelineHeight, geometry.size.height * 0.6))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .overlay { PerformCountdown(editor: editor) }
        .overlay {
            if app.showTour { TourOverlay(editor: editor) }
        }
        .overlay(alignment: .bottom) {
            if let proposal = editor.proposal { ProposalBanner(editor: editor, proposal: proposal) }
        }
        .overlay(alignment: .bottom) {
            if let state = editor.historyScrub { HistoryScrubberBar(editor: editor, state: state) }
        }
        // What the board covers isn't there for VoiceOver either.
        .accessibilityHidden(editor.boardShown)
        .overlay {
            // The Schizzo board covers the stage (and its chrome) while it's open; sheets still come over it.
            if editor.boardShown, let board = editor.board {
                BoardCover(editor: editor, board: board)
                    .transition(.opacity)
            }
        }
        .modifier(EditorSheets(editor: editor))
        .modifier(ObjectRenameAlert(editor: editor))
        .background {
            // The stage's keys (space, delete, arrows) rest while the board has the screen.
            if !editor.boardShown { EditorKeyboardShortcuts(editor: editor) }
        }
        .onPencilSqueeze { phase in
            guard case .ended = phase, squeezeAction != .ignore else { return }
            editor.togglePlay()
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await app.library.importFiles(urls) }
            return true
        }
        .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: editor.chromeHidden)
        .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: editor.timelinePresence)
        .animation(HmmMotion.gentle.animation(reduceMotion: reduceMotion), value: editor.boardShown)
        .onAppear { editor.loadWaveforms() }
    }

    private var stageArea: some View {
        ZStack {
            StageHost(editor: editor)
                .ignoresSafeArea(edges: [.top, .horizontal])
                .dropDestination(for: String.self) { items, location in
                    for id in items {
                        editor.placeLibraryItem(id: id, at: location)
                    }
                    return !items.isEmpty
                }
            // Overlays sit on 3D positions and frame coordinates: they never mirror.
            StageOverlayView(editor: editor)
                .environment(\.layoutDirection, .leftToRight)
            // A picture being placed to project: in the stage's own points, like the stage.
            if editor.tool == .paint, editor.colourPaint.picture != nil {
                PaintPictureOverlay(editor: editor)
                    .ignoresSafeArea(edges: [.top, .horizontal])
                    .environment(\.layoutDirection, .leftToRight)
            }
            // The person rig's dots: dragged in the stage's own points.
            if editor.tool == .rig, editor.rigging.person != nil {
                PersonDotMarks(editor: editor)
                    .ignoresSafeArea(edges: [.top, .horizontal])
                    .environment(\.layoutDirection, .leftToRight)
            }
            if editor.chromeHidden {
                ChromeRestoreButton(editor: editor)
            } else {
                // Pictures pinned from the board float under the chrome: a panel always opens over them.
                if boardEnabled, !editor.references.isEmpty {
                    ReferenceCards(editor: editor)
                        .opacity(editor.chromeFaded ? 0 : 1)
                }
                StageChrome(editor: editor)
                    .opacity(editor.chromeFaded ? 0 : 1)
                    .animation(HmmMotion.gentle.animation(reduceMotion: reduceMotion), value: editor.chromeFaded)
            }
            if editor.faceActive { FacePreviewPanel(editor: editor, monitor: editor.faceMonitor) }
            if showsHUD { PerformanceHUDOverlay(monitor: editor.performance) }
            if AppIdentity.isUITesting, !AppIdentity.isTakingScreenshots { DebugTrail(editor: editor) }
        }
        .clipped()
    }
}

/// The one control left while the chrome is hidden.
private struct ChromeRestoreButton: View {
    let editor: EditorModel

    var body: some View {
        HmmButton("arrow.down.right.and.arrow.up.left", label: "Show interface", size: 40) { editor.chromeHidden = false }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(HmmSpacing.m)
            .accessibilityIdentifier("show-interface")
    }
}

/// The handle between stage and timeline: drag to resize (down past the transport sends the timeline away), tap to
/// switch between the whole timeline and the slim transport. The project remembers the height.
private struct TimelineDivider: View {
    let editor: EditorModel
    let maximum: CGFloat
    @State private var start: Double?
    @Environment(\.hmmTheme) private var theme

    static let transportHeight = 56.0

    var body: some View {
        ZStack {
            theme.background
            Capsule().fill(theme.text3).frame(width: 44, height: 5)
        }
        .frame(height: 16)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if start == nil { start = editor.timelinePresence == .full ? editor.timelineHeight : Self.transportHeight }
                    let proposed = (start ?? editor.timelineHeight) - Double(value.translation.height)
                    switch proposed {
                    case ..<24: editor.timelinePresence = .hidden
                    case ..<110: editor.timelinePresence = .transport
                    default:
                        editor.timelinePresence = .full
                        editor.setTimelineHeight(min(proposed, Double(maximum)))
                    }
                }
                .onEnded { _ in start = nil }
        )
        .onTapGesture {
            HmmHaptics.play(.selection)
            editor.timelinePresence = editor.timelinePresence == .full ? .transport : .full
        }
        .accessibilityElement()
        .accessibilityLabel(editor.timelinePresence == .full ? "Collapse the timeline" : "Show the timeline")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("timeline-divider")
    }
}

/// UI tests only: the recent selection and commands as an accessibility value.
private struct DebugTrail: View {
    let editor: EditorModel

    var body: some View {
        Text(editor.debugTrail.joined(separator: " | "))
            .font(.system(size: 8))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .accessibilityIdentifier("debug-trail")
            .allowsHitTesting(false)
    }
}
