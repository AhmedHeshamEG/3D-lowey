import HmmDesign
import LoweyCore
import SwiftUI

/// Everything floating over the stage (docs/LAYOUT.md): the two corner clusters and the panel each opens, the sidebar,
/// the inspector beside the selection, and the bottom row (joystick, tool options, the timeline control and views).
struct StageChrome: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppSettings.sidebarOnRight) private var sidebarOnRight = false
    @AppStorage(AppSettings.showsJoystick) private var showsJoystick = true
    /// The open leading panel's frame on screen (the inspector keeps clear of it).
    @State private var leadingPanelFrame: CGRect?

    var body: some View {
        ZStack {
            if editor.tool == .model || editor.precision.showsDimensions { ModelDimensions(editor: editor) }
            HStack {
                if !sidebarOnRight { EditorSidebar(editor: editor) }
                Spacer()
                if sidebarOnRight { EditorSidebar(editor: editor) }
            }
            .padding(.horizontal, HmmSpacing.xs)
            .frame(maxHeight: .infinity, alignment: .center)
            bottomRow
            // Last, so above everything: a panel opened from a cluster covers the sidebar and the bottom row, never
            // the other way round.
            VStack(spacing: HmmSpacing.s) {
                HStack(alignment: .top) {
                    leadingCluster
                    Spacer(minLength: HmmSpacing.m)
                    trailingCluster
                }
                HStack(alignment: .top, spacing: HmmSpacing.s) {
                    if let panel = editor.openPanel, panel.isLeading {
                        ClusterPanelView(editor: editor, panel: panel)
                            .hmmPanelTransition(from: .topLeading)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { leadingPanelFrame = $0 }
                            .onDisappear { leadingPanelFrame = nil }
                    }
                    Spacer(minLength: 0)
                    if let panel = editor.openPanel, !panel.isLeading {
                        ClusterPanelView(editor: editor, panel: panel).hmmPanelTransition(from: .topTrailing)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(HmmSpacing.m)
        }
        .overlay {
            if showsInspector {
                FloatingInspector(editor: editor, avoiding: leadingPanelFrame, sidebarOnRight: sidebarOnRight)
                    .transition(.opacity)
            }
        }
        .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: editor.openPanel)
        .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: showsInspector)
    }

    /// The inspector floats while something is selected and no making tool's panel is open. While sketching it steps
    /// aside: the numbers on the stage are what you're working with then (D-124).
    private var showsInspector: Bool {
        !editor.selection.isEmpty && editor.openPanel?.isLeading != false
            && !(editor.tool == .model && editor.modeling.mode.sketchKind != nil)
    }

    // MARK: Clusters

    private var leadingCluster: some View {
        HmmCornerCluster([
            HmmClusterItem(id: "home", systemName: "square.grid.2x2", label: "Home") { app.closeEditor() },
            item(.actions, "ellipsis.circle", "Actions"),
            item(.look, "paintpalette", "Look"),
            item(.select, editor.tool == .lasso ? "lasso" : "hand.point.up.left", "Select", on: editor.tool == .lasso)
        ])
        .overlay(alignment: .bottomLeading) {
            Text(editor.baseScene.name)
                .font(.hmm(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .offset(x: HmmSpacing.s, y: 18)
                .accessibilityIdentifier("scene-name")
        }
    }

    /// The making tools: Model, Draw, Paint, Animate (calls the timeline) and Cast.
    private var trailingCluster: some View {
        HmmCornerCluster([
            item(.model, "cube", "Model"),
            item(.draw, drawIcon, "Draw", on: editor.tool.draws),
            item(.paint, editor.tool == .scatter ? "circle.hexagongrid" : "paintbrush.pointed", "Paint", on: editor.tool.paintsSurfaces),
            HmmClusterItem(id: "animate", systemName: "figure.walk.motion", label: "Animate", isOn: editor.timelinePresence == .full) {
                editor.toggleAnimate()
            },
            item(.cast, "person.2", "Cast")
        ])
    }

    private var drawIcon: String {
        switch editor.tool {
        case .draw: "scribble.variable"
        case .flipbook: "book.pages"
        default: "pencil.tip"
        }
    }

    private func item(_ panel: ClusterPanel, _ systemName: String, _ label: String, on: Bool = false) -> HmmClusterItem {
        HmmClusterItem(id: panel.rawValue, systemName: systemName, label: label, isOn: editor.openPanel == panel || on) {
            editor.openPanel = editor.openPanel == panel ? nil : panel
            if panel == .model, editor.openPanel == nil { editor.libraryPurpose = .place }
        }
    }

    // MARK: Bottom of the stage

    private var bottomRow: some View {
        HStack(alignment: .bottom, spacing: HmmSpacing.s) {
            if editor.flying {
                FlyPad(editor: editor).transition(.scale.combined(with: .opacity))
            } else if showsJoystick, !editor.selection.isEmpty, editor.tool == .select, editor.performPhase == .idle, !editor.directorView {
                JoystickPad(editor: editor)
                    .overlay(alignment: .topTrailing) { JoystickHideButton { showsJoystick = false } }
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            ToolOptionsBar(editor: editor)
            Spacer()
            ViewControls(editor: editor)
        }
        .padding(HmmSpacing.m)
        .padding(.leading, sidebarOnRight ? 0 : 56)
        .padding(.trailing, sidebarOnRight ? 56 : 0)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

/// The panel a cluster button opened.
private struct ClusterPanelView: View {
    let editor: EditorModel
    let panel: ClusterPanel

    var body: some View {
        switch panel {
        case .actions: ActionsPanel(editor: editor)
        case .look: LookPanel(editor: editor)
        case .select: SelectPanel(editor: editor)
        case .model: ModelPanel(editor: editor)
        case .draw: DrawToolsPanel(editor: editor)
        case .paint: PaintPanel(editor: editor)
        case .cast: CastPanel(editor: editor)
        }
    }
}

/// The joystick's own way out (Settings ▸ Stage brings it back).
private struct JoystickHideButton: View {
    let hide: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        HmmButton("xmark", label: "Hide the joystick", size: 28) {
            hide()
            app.show("The joystick is in Settings ▸ Stage when you want it back")
        }
        .offset(x: HmmSpacing.xs, y: -HmmSpacing.xs)
        .accessibilityIdentifier("hide-joystick")
    }
}

/// Bottom-right of the stage: the timeline on call, the views, framing the selection, the Director view.
private struct ViewControls: View {
    let editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xxs) {
            HmmButton("timeline.selection", label: "Timeline", isOn: editor.timelinePresence != .hidden) { editor.toggleTimeline() }
                .accessibilityIdentifier("timeline-toggle")
            Menu {
                ForEach(ViewAxis.allCases, id: \.self) { axis in
                    Button(LocalizedStringKey(axis.displayName)) { editor.stage?.quickView(axis) }
                }
                Divider()
                Button(editor.projection == .orthographic ? "Perspective" : "Orthographic") { editor.toggleProjection() }
            } label: {
                Image(systemName: "cube.transparent").font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Views")
            .accessibilityIdentifier("views-menu")
            HmmButton("viewfinder", label: "Frame the selection") { editor.frameSelection() }
            HmmButton("video", label: "Director view", isOn: editor.directorView) { editor.setDirectorView(!editor.directorView) }
                .accessibilityIdentifier("director-view")
        }
        .padding(HmmSpacing.xxs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("view-controls")
    }
}
