import HmmDesign
import LoweyCore
import SwiftUI

/// Everything floating over the stage: the two corner clusters and the panel each opens, the sidebar, the inspector,
/// the Director view toggle and the view controls.
struct StageChrome: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppSettings.sidebarOnRight) private var sidebarOnRight = false
    @AppStorage(AppSettings.showsJoystick) private var showsJoystick = false

    var body: some View {
        ZStack {
            VStack(spacing: HmmSpacing.s) {
                HStack(alignment: .top) {
                    leadingCluster
                    Spacer(minLength: HmmSpacing.m)
                    trailingCluster
                }
                HStack(alignment: .top, spacing: HmmSpacing.s) {
                    if let panel = editor.openPanel, panel.isLeading {
                        ClusterPanelView(editor: editor, panel: panel).hmmPanelTransition(from: .topLeading)
                    }
                    Spacer(minLength: 0)
                    if let panel = editor.openPanel, !panel.isLeading {
                        ClusterPanelView(editor: editor, panel: panel).hmmPanelTransition(from: .topTrailing)
                    } else if !editor.selection.isEmpty {
                        InspectorPanel(editor: editor).hmmPanelTransition(from: .trailing)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(HmmSpacing.m)
            HStack {
                if !sidebarOnRight { EditorSidebar(editor: editor) }
                Spacer()
                if sidebarOnRight { EditorSidebar(editor: editor) }
            }
            .padding(.horizontal, HmmSpacing.xs)
            .frame(maxHeight: .infinity, alignment: .center)
            bottomRow
        }
        .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: editor.openPanel)
        .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: editor.selection.isEmpty)
    }

    // MARK: Clusters

    private var leadingCluster: some View {
        HmmCornerCluster([
            HmmClusterItem(id: "theater", systemName: "square.grid.2x2", label: "Theater") { app.closeEditor() },
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

    private var trailingCluster: some View {
        HmmCornerCluster([
            item(.build, "plus", "Build"),
            item(.draw, editor.tool == .shadowBrush ? "circle.lefthalf.striped.horizontal" : "pencil.tip", "Draw", on: editor.tool.paints),
            item(.transform, gizmoIcon, "Transform"),
            item(.cast, "person.2", "Cast"),
            item(.library, "books.vertical", "Library")
        ])
    }

    private func item(_ panel: ClusterPanel, _ systemName: String, _ label: String, on: Bool = false) -> HmmClusterItem {
        HmmClusterItem(id: panel.rawValue, systemName: systemName, label: label, isOn: editor.openPanel == panel || on) {
            editor.openPanel = editor.openPanel == panel ? nil : panel
            if panel == .library, editor.openPanel == nil { editor.libraryPurpose = .place }
        }
    }

    private var gizmoIcon: String {
        switch editor.gizmoMode {
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .rotate: "arrow.triangle.2.circlepath"
        case .scale: "arrow.up.left.and.arrow.down.right"
        }
    }

    // MARK: Bottom of the stage

    private var bottomRow: some View {
        HStack(alignment: .bottom, spacing: HmmSpacing.s) {
            if showsJoystick, !editor.selection.isEmpty, editor.tool == .select, editor.performPhase == .idle, !editor.directorView {
                JoystickPad(editor: editor).transition(.scale.combined(with: .opacity))
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
        case .build: BuildPanel(editor: editor)
        case .draw: DrawToolsPanel(editor: editor)
        case .transform: TransformPanel(editor: editor)
        case .cast: CastPanel(editor: editor)
        case .library: LibraryPanel(editor: editor)
        }
    }
}

/// Bottom-right of the stage: the Director view toggle, frame, quick views.
private struct ViewControls: View {
    let editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xxs) {
            Menu {
                ForEach(ViewAxis.allCases, id: \.self) { axis in
                    Button(axis.displayName) { editor.stage?.quickView(axis) }
                }
                Divider()
                Button(editor.projection == .orthographic ? "Perspective" : "Orthographic") { editor.toggleProjection() }
            } label: {
                Image(systemName: "cube.transparent").font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Views")
            HmmButton("viewfinder", label: "Frame the selection") { editor.frameSelection() }
            HmmButton("video", label: "Director view", isOn: editor.directorView) { editor.setDirectorView(!editor.directorView) }
                .accessibilityIdentifier("director-view")
        }
        .padding(HmmSpacing.xxs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
    }
}
