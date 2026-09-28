import LoweyCore
import LoweyScript
import SwiftUI

/// The programmatic layer: write (or pick) a script, run it — the result is one undo step.
struct ScriptPanel: View {
    @Bindable var editor: EditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "curlybraces").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.accent)
                TextField("Script name", text: $editor.scriptName)
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Menu {
                    ForEach(ScriptExamples.all, id: \.name) { example in
                        Button(example.name) {
                            editor.scriptName = example.name
                            editor.scriptSource = example.source
                        }
                    }
                    let saved = editor.library.manifest.scripts
                    if !saved.isEmpty {
                        Section("Your library") {
                            ForEach(saved) { script in
                                Button(script.name) { editor.openScript(script) }
                            }
                        }
                    }
                } label: {
                    Label("Examples", systemImage: "books.vertical").pillLabel()
                }
                PillButton(title: "Save", systemName: "tray.and.arrow.down") { editor.saveScriptToLibrary() }
                PillButton(title: editor.scriptRunning ? "Running…" : "Run", systemName: "play.fill", prominent: true) { editor.runScript() }
                    .accessibilityIdentifier("run-script")
                IconButton(systemName: "xmark", label: "Close scripts", size: 36) { dismiss() }
            }
            TextEditor(text: $editor.scriptSource)
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("script-editor")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(editor.scriptLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(line.hasPrefix("⚠︎") ? Theme.danger : Theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 90)
            .accessibilityIdentifier("script-log")
            DisclosureGroup("What scripts can do") {
                Text(Self.reference)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .padding(20)
        .background(Theme.background)
    }

    static let reference = """
    lowey.add(shape, { name, position, rotation, scale, color, glow, parent }) → id
    lowey.group(name, { position, rotation, parent }) → id
    lowey.light("point" | "spot" | "directional", { position, color, intensity, range }) → id
    lowey.set(id, property, value)            lowey.key(id, property, time, value, easing?)
    lowey.preset(ids, "popIn", time, { duration, amplitude, delay, order: "x" | "distance", from })
    lowey.behavior(id, { type: "windSway", angle: 5 }, { start, end })
    lowey.flock(ids, { duration, center, extent, speed })    lowey.crowdWalk(ids, targets, { speed })
    lowey.physics(ids, { kind: "fall" | "explode", duration })    lowey.remove(id)    lowey.log(…)
    lowey.random(seed) → a function returning 0…1 (the same every run)
    scene.objects()  scene.find(name)  scene.get(id)  selection  time  fps  duration
    Colours: "#ff8800" or a palette slot number. Rotations in degrees. Everything is one undo step.
    """
}
