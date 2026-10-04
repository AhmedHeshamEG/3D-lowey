import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// Scripts: write (or pick) a JavaScript script and run it; whatever it builds is one undo step.
struct ScriptSheet: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HmmSheet("Scripts", primary: (editor.scriptRunning ? "Running…" : "Run", { editor.runScript() })) {
            HStack(spacing: HmmSpacing.xs) {
                TextField("Script name", text: $editor.scriptName).font(.hmm(.headline, weight: .semibold))
                Menu {
                    ForEach(ScriptExamples.all, id: \.name) { example in
                        Button(LocalizedStringKey(example.name)) {
                            editor.scriptName = example.name
                            editor.scriptSource = example.source
                        }
                    }
                    let saved = editor.library.manifest.scripts
                    if !saved.isEmpty {
                        Section("Your library") {
                            ForEach(saved) { script in Button(script.name) { editor.openScript(script) } }
                        }
                    }
                } label: { Label("Examples", systemImage: "books.vertical").font(.hmm(.body, weight: .semibold)) }
                HmmPillButton("Save", systemName: "tray.and.arrow.down") { editor.saveScriptToLibrary() }
                HmmPillButton("Run", systemName: "play.fill", prominent: true) { editor.runScript() }
                    .accessibilityIdentifier("run-script")
            }
            TextEditor(text: $editor.scriptSource)
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(HmmSpacing.xs)
                .frame(minHeight: 280)
                .background(RoundedRectangle(cornerRadius: HmmRadius.control).fill(theme.surface2))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("script-editor")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(editor.scriptLog.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("⚠︎") ? theme.danger : theme.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("script-log")
            DisclosureGroup("What scripts can do") {
                Text(Self.reference).font(.system(.footnote, design: .monospaced)).foregroundStyle(theme.text2).textSelection(.enabled)
            }
            .font(.hmm(.body, weight: .semibold))
        }
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
