import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI
import UIKit

/// The monitor window: the open project's shot, through its camera, as it exports. Move it next to the editor in
/// Stage Manager or onto an external display.
public struct MonitorRoot: View {
    @Environment(AppModel.self) private var app
    @AppStorage(HmmThemeMode.storageKey) private var themeMode = HmmThemeMode.dark.rawValue

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let editor = app.editor {
                MonitorHost(editor: editor)
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) { MonitorCaption(editor: editor) }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("monitor")
            } else {
                HmmEmptyState("rectangle.on.rectangle", title: "Monitor", message: "Open a project: its shot plays here, as it will export.")
            }
        }
        .hmmThemed(.lowey, mode: HmmThemeMode(rawValue: themeMode) ?? .dark)
    }
}

private struct MonitorCaption: View {
    let editor: EditorModel

    var body: some View {
        Text(verbatim: "\(editor.monitorCaption) · \(TimeFormat.clock(editor.time))")
            .font(.hmmNumbers(.caption))
            .foregroundStyle(.white.opacity(0.75))
            .padding(HmmSpacing.s)
            .accessibilityLabel(Text("Shot \(editor.monitorCaption) at \(TimeFormat.clock(editor.time))"))
    }
}

/// A second stage view that draws the shot camera's frame continuously (it never takes touches).
struct MonitorHost: UIViewRepresentable {
    let editor: EditorModel

    func makeUIView(context _: Context) -> UIView {
        guard let view = try? StageView(device: RenderDevice.sharedDevice()) else { return UIView() }
        view.isUserInteractionEnabled = false
        view.preferredFramesPerSecond = 30
        view.isContinuous = true
        view.frameSource = { [weak editor] view in editor?.monitorFrame(for: view) }
        view.isAccessibilityElement = true
        view.accessibilityLabel = String(localized: "Monitor")
        return view
    }

    func updateUIView(_: UIView, context _: Context) {}
}

/// When the editor is open in another window, a second main window offers to take it over or become a monitor
/// (one stage edits a project at a time).
struct SecondaryWindowView: View {
    @Environment(AppModel.self) private var app
    let claim: () -> Void
    @State private var showsMonitor = false

    var body: some View {
        if showsMonitor {
            MonitorRoot()
        } else {
            VStack(spacing: HmmSpacing.m) {
                HmmEmptyState("macwindow.on.rectangle", title: "Open in another window",
                              message: "3D-lowey edits in one window at a time. Use this one instead, or make it a monitor of the shot.")
                HStack {
                    HmmPillButton("Monitor", systemName: "rectangle.on.rectangle") { showsMonitor = true }
                    HmmPillButton("Edit here", systemName: "pencil", prominent: true, action: claim)
                }
            }
            .padding(HmmSpacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .accessibilityIdentifier("secondary-window")
        }
    }
}
