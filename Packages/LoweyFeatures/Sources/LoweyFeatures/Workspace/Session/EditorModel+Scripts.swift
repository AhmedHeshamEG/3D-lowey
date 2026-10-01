import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// Programs and AI: JavaScript scripts (one undo step), and Scene Scripts that arrive from Claude, the clipboard or a
/// file — previewed, then applied as one undo step when you say so.
extension EditorModel {
    // MARK: JavaScript

    func openScript(_ script: ScriptAsset?) {
        if let script {
            scriptName = script.name
            scriptSource = script.source
        } else if scriptSource.isEmpty {
            scriptName = ScriptExamples.forest.name
            scriptSource = ScriptExamples.forest.source
        }
        scriptLog = []
        sheet = .scripts
    }

    func runScript() {
        guard !scriptRunning else { return }
        scriptRunning = true
        scriptLog = ["Running…"]
        let source = scriptSource
        let name = scriptName.isEmpty ? "Script" : scriptName
        let document = session.document
        let selection = selection
        let time = time
        Task {
            let outcome = await ScriptRunner.run(source, name: name, document: document, selection: selection, time: time)
            scriptRunning = false
            if let error = outcome.error {
                scriptLog = outcome.log + ["⚠︎ " + error]
                return
            }
            if let command = outcome.command, perform(command) {
                let created = outcome.created.filter { baseScene.objects[$0]?.parent == nil }
                if !created.isEmpty { setSelection(created) }
                scriptLog = outcome.log + ["Done: one undo step."]
                HmmHaptics.play(.commit)
            } else {
                scriptLog = outcome.log + ["The script ran but changed nothing."]
            }
        }
    }

    func saveScriptToLibrary() {
        library.saveScript(name: scriptName.isEmpty ? "My script" : scriptName, source: scriptSource)
        app.show("Saved “\(scriptName)” to your library")
    }

    // MARK: Scene Scripts (AI proposes, you decide)

    func scriptContext() -> ScriptContext {
        refreshOperationsLibrary()
        return ScriptContext(library: library.manifest, now: time, focus: dropPoint(), ids: .random)
    }

    /// Compiles against the current document and performs it (one undo step).
    func applyScript(_ script: SceneScript) -> Result<ScriptResult, Error> {
        do {
            let result = try ScriptCompiler.compile(script, document: session.document, context: scriptContext())
            if let command = result.command {
                perform(command)
                HmmHaptics.play(.commit)
            }
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    /// Shows the proposal and waits for Apply / Not now (or three minutes).
    func propose(_ script: SceneScript, preview: ScriptPreview, source: String) async -> Bool {
        proposal?.reply?.resume(returning: false)
        return await withCheckedContinuation { continuation in
            let made = ScriptProposal(title: script.title, source: source, lines: preview.lines, report: preview.report, script: script,
                                      reply: continuation)
            proposal = made
            HmmHaptics.play(.selection)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(180))
                guard let self, let current = proposal, current.id == made.id else { return }
                current.reply?.resume(returning: false)
                proposal = nil
            }
        }
    }

    /// The answer to the proposal card.
    func answerProposal(_ apply: Bool) {
        guard let current = proposal else { return }
        proposal = nil
        if let reply = current.reply {
            reply.resume(returning: apply)
        } else if apply, case let .failure(error) = applyScript(current.script) {
            app.show("The script failed: \(error)", kind: .error)
        }
    }

    /// A Scene Script from the clipboard or a file: preview first, then apply.
    func importScript(_ data: Data, source: String) {
        guard let script = try? LoweyJSON.decode(SceneScript.self, from: data) else {
            app.show("That isn't a Scene Script (JSON with \"actions\")", kind: .error)
            return
        }
        do {
            let preview = try ScriptCompiler.preview(script, document: session.document, context: scriptContext())
            proposal = ScriptProposal(title: script.title, source: source, lines: preview.lines, report: preview.report, script: script)
        } catch {
            app.show("The script has a problem: \(error)", kind: .error)
        }
    }

    func importScriptFromClipboard() {
        guard let text = UIPasteboard.general.string else {
            app.show("Copy a Scene Script (JSON) first")
            return
        }
        // A script pasted inside a Markdown code block works too.
        let cleaned = text.components(separatedBy: "\n").filter { !$0.hasPrefix("```") }.joined(separator: "\n")
        importScript(Data(cleaned.utf8), source: "Clipboard")
    }
}

/// A Scene Script waiting for a decision.
struct ScriptProposal: Identifiable {
    let id = UUID()
    var title: String
    var source: String
    var lines: [String]
    var report: [String]
    var script: SceneScript
    /// The bridge waits on this (true = apply).
    var reply: CheckedContinuation<Bool, Never>?
}
