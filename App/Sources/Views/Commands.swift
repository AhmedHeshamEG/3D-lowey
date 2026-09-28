import LoweyCore
import SwiftUI

/// Menu-bar commands with Magic Keyboard shortcuts. They act on the open editor.
struct LoweyCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandMenu("Scene") {
            ForEach(Array(EditorMode.allCases.enumerated()), id: \.offset) { index, mode in
                Button(mode.title) { app.editor?.mode = mode }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
            Button("Library") { app.editor?.showLibrary.toggle() }
            Button("Paste a Scene Script") { app.editor?.importScriptFromClipboard() }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Button("AI & laptop bridge…") { app.editor?.showBridge = true }
                .keyboardShortcut("b", modifiers: [.command, .shift])
        }
        CommandMenu("Timeline") {
            Button("Audio & words…") { app.editor?.showAudio = true }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Transcript") { app.editor?.showTranscript = true }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Record voiceover") { app.editor?.toggleVoiceRecording() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Select all keys") { app.editor?.selectKeys(.all) }
            Button("Keys after the playhead") { app.editor?.selectKeys(.afterPlayhead) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            Button("Keys at the playhead") { app.editor?.selectKeys(.atPlayhead) }
            Button("Add marker") { app.editor?.addMarker() }
                .keyboardShortcut("m", modifiers: .command)
            Divider()
            Button("Flash here") { app.editor?.addScreenEffect(.flash) }
            Button("Shake here") { app.editor?.addScreenEffect(.shake) }
        }
        CommandMenu("View") {
            Button("Post-processing preview on/off") { app.editor?.previewPost.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Show FPS & stats") { app.editor?.showStatistics.toggle() }
        }
    }
}
