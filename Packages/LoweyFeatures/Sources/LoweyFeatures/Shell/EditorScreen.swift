import HmmDesign
import LoweyCore
import SwiftUI

/// The open project, Procreate Dreams grammar: the Stage on top, the Timeline below (resizable, collapsible to a
/// transport bar); document and app things in the top-left cluster, the making tools in the top-right one, two
/// context sliders and undo / redo in the sidebar, the inspector sliding in from the right while something is
/// selected. Four fingers hide everything but the stage; playback fades the chrome after two seconds.
struct EditorScreen: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.preferredPencilSqueezeAction) private var squeezeAction
    @AppStorage("timeline.height") private var timelineHeight = 260.0
    @AppStorage(AppSettings.showsPerformanceHUD) private var showsHUD = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                stageArea
                if !editor.chromeHidden {
                    TimelineDivider(height: $timelineHeight, collapsed: $editor.timelineCollapsed, maximum: geometry.size.height * 0.6)
                    if editor.timelineCollapsed {
                        TransportBar(editor: editor)
                    } else {
                        // Time runs left to right in every language (as on a ruler); the panels around it mirror.
                        TimelinePane(editor: editor)
                            .environment(\.layoutDirection, .leftToRight)
                            .frame(height: min(max(timelineHeight, 150), geometry.size.height * 0.6))
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
        .modifier(EditorSheets(editor: editor))
        .background(EditorKeyboardShortcuts(editor: editor))
        .onPencilSqueeze { phase in
            guard case .ended = phase, squeezeAction != .ignore else { return }
            editor.togglePlay()
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await app.library.importFiles(urls) }
            return true
        }
        .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: editor.chromeHidden)
        .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: editor.timelineCollapsed)
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
            if editor.chromeHidden {
                ChromeRestoreButton(editor: editor)
            } else {
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

/// The handle between stage and timeline: drag to resize, tap to collapse the timeline into a transport bar.
private struct TimelineDivider: View {
    @Binding var height: Double
    @Binding var collapsed: Bool
    let maximum: CGFloat
    @State private var start: Double?
    @Environment(\.hmmTheme) private var theme

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
                    if start == nil { start = collapsed ? 150 : height }
                    let proposed = (start ?? height) - Double(value.translation.height)
                    collapsed = proposed < 110
                    height = min(max(proposed, 150), Double(maximum))
                }
                .onEnded { _ in start = nil }
        )
        .onTapGesture {
            HmmHaptics.play(.selection)
            collapsed.toggle()
        }
        .accessibilityElement()
        .accessibilityLabel(collapsed ? "Show the timeline" : "Collapse the timeline")
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
