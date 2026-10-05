import HmmCommands
import LoweyCore
import LoweyEngine
import SwiftUI

/// The menu bar (iPadOS 26) with every keyboard shortcut. It acts on the open project.
public struct LoweyMenuCommands: Commands {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    public init(app: AppModel) {
        self.app = app
    }

    private var editor: EditorModel? { app.editor }

    public var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(editor?.canUndo == true ? editor?.undoTitle ?? "Undo" : "Undo") { editor?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(editor?.canUndo != true)
            Button(editor?.canRedo == true ? editor?.redoTitle ?? "Redo" : "Redo") { editor?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(editor?.canRedo != true)
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Copy") { editor?.copySelection() }.keyboardShortcut("c", modifiers: .command)
            Button("Paste") { editor?.paste() }.keyboardShortcut("v", modifiers: .command)
            Button("Duplicate") { editor?.duplicateSelection() }.keyboardShortcut("d", modifiers: .command)
            Button("Delete") { editor?.deleteSelection() }.keyboardShortcut(.delete, modifiers: .command)
            Divider()
            Button("Select All") { editor?.selectAll() }.keyboardShortcut("a", modifiers: .command)
            Button("Select Similar") { editor?.selectSimilar() }.keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Group") { editor?.groupSelection() }.keyboardShortcut("g", modifiers: .command)
            Button("Ungroup") { editor?.ungroupSelection() }.keyboardShortcut("g", modifiers: [.command, .shift])
        }
        // The making tools in the order of the top-right cluster, then the document's panels.
        CommandMenu("Tools") {
            Button("Model") { panel(.model) }.keyboardShortcut("1", modifiers: .command)
            Button("Draw") { tool(.ink, panel: .draw) }.keyboardShortcut("2", modifiers: .command)
            Button("Paint") { tool(.shadowBrush, panel: .paint) }.keyboardShortcut("3", modifiers: .command)
            Button("Animate") { editor?.toggleAnimate() }.keyboardShortcut("4", modifiers: .command)
            Button("Cast") { panel(.cast) }.keyboardShortcut("5", modifiers: .command)
            Divider()
            Button("Actions") { panel(.actions) }.keyboardShortcut("6", modifiers: .command)
            Button("Look") { panel(.look) }.keyboardShortcut("7", modifiers: .command)
            Button("Select") { tool(.select, panel: .select) }.keyboardShortcut("8", modifiers: .command)
            Divider()
            Button("Library") { modelPage(.library) }.keyboardShortcut("l", modifiers: .command)
            Button("Precision") { modelPage(.precision) }
            Button("Solid Shape") { tool(.draw, panel: .draw) }
            Button("Flipbook") { tool(.flipbook, panel: .draw) }
            Button("Shadow Brush") { tool(.shadowBrush, panel: .paint) }
            Button("Scatter") { tool(.scatter, panel: .paint) }
            Button("Lasso") { tool(.lasso, panel: nil) }
            Divider()
            Button("Move") { gizmo(.move) }.keyboardShortcut("1", modifiers: [.command, .option])
            Button("Turn") { gizmo(.rotate) }.keyboardShortcut("2", modifiers: [.command, .option])
            Button("Size") { gizmo(.scale) }.keyboardShortcut("3", modifiers: [.command, .option])
        }
        CommandMenu("Scene") {
            Button("Frame Selection") { editor?.frameSelection() }.keyboardShortcut("f", modifiers: .command)
            Button("Director View") { editor.map { $0.setDirectorView(!$0.directorView) } }.keyboardShortcut("d", modifiers: [.command, .option])
            Button("Fly the Camera") { editor.map { $0.flying ? $0.stopFlying() : $0.startFlying() } }.keyboardShortcut("y", modifiers: [.command, .option])
            Button("Hide Interface") { editor?.chromeHidden.toggle() }.keyboardShortcut("f", modifiers: [.command, .control])
            Divider()
            Button("Export…") { editor?.sheet = .export }.keyboardShortcut("e", modifiers: .command)
            Button("Paste a Scene Script") { editor?.importScriptFromClipboard() }.keyboardShortcut("v", modifiers: [.command, .option])
            Button("AI & Laptop Bridge…") { editor?.sheet = .bridge }.keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Scripts…") { editor?.openScript(nil) }
            Divider()
            Button("New Monitor Window") { openWindow(id: LoweyWindow.monitor) }.keyboardShortcut("n", modifiers: [.command, .option])
        }
        CommandMenu("Timeline") {
            Button(editor?.timelinePresence == .hidden ? "Show Timeline" : "Hide Timeline") { editor?.toggleTimeline() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Play / Pause") { editor?.togglePlay() }
            Button("Key the Selection") { editor?.keySelection() }.keyboardShortcut("k", modifiers: .command)
            Button("Record a Performance") { editor?.armPerform() }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Add Marker") { editor?.addMarker() }.keyboardShortcut("m", modifiers: .command)
            Divider()
            Button("Audio & Words…") { editor?.sheet = .audio }.keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Transcript") { editor?.sheet = .transcript }.keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Record Voiceover") { editor?.toggleVoiceRecording() }.keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Select All Keys") { editor?.selectKeys(.all) }.keyboardShortcut("a", modifiers: [.command, .option])
            Button("Keys After the Playhead") { editor?.selectKeys(.afterPlayhead) }.keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            Button("Keys at the Playhead") { editor?.selectKeys(.atPlayhead) }
        }
    }

    private func panel(_ panel: ClusterPanel) {
        guard let editor else { return }
        editor.openPanel = editor.openPanel == panel ? nil : panel
    }

    private func tool(_ tool: StageTool, panel: ClusterPanel?) {
        guard let editor else { return }
        editor.tool = tool
        if let panel { editor.openPanel = panel }
    }

    private func modelPage(_ page: ModelPage) {
        guard let editor else { return }
        editor.modelPage = page
        editor.openPanel = .model
    }

    private func gizmo(_ mode: GizmoMode) {
        guard let editor else { return }
        editor.tool = .select
        editor.gizmoMode = mode
    }
}
