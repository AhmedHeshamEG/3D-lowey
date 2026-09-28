import Foundation
import LoweyCore
import SwiftUI
import UIKit

/// A script waiting for Hesham's decision (from the bridge, the clipboard or a file).
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

/// AI layer inside the editor: Scene Scripts from anywhere → preview → apply as one undo step.
extension EditorModel {
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
                Haptics.success()
            }
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    /// Shows the proposal and waits for Apply / Not now (or 3 minutes).
    func propose(_ script: SceneScript, preview: ScriptPreview, source: String) async -> Bool {
        proposal?.reply?.resume(returning: false)
        return await withCheckedContinuation { continuation in
            proposal = ScriptProposal(title: script.title, source: source, lines: preview.lines, report: preview.report, script: script,
                                      reply: continuation)
            Haptics.tap()
            let id = proposal?.id
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(180))
                guard let self, let current = proposal, current.id == id else { return }
                current.reply?.resume(returning: false)
                proposal = nil
            }
        }
    }

    /// Hesham's answer to the proposal sheet.
    func answerProposal(_ apply: Bool) {
        guard let current = proposal else { return }
        proposal = nil
        if let reply = current.reply {
            reply.resume(returning: apply)
        } else if apply {
            if case let .failure(error) = applyScript(current.script) { app.show("The script failed: \(error)") }
        }
    }

    /// A Scene Script from the clipboard or a file: preview first, then apply.
    func importScript(_ data: Data, source: String) {
        guard let script = try? LoweyJSON.decode(SceneScript.self, from: data) else {
            app.show("That isn't a Scene Script (JSON with \"actions\" or \"commands\")")
            return
        }
        do {
            let preview = try ScriptCompiler.preview(script, document: session.document, context: scriptContext())
            proposal = ScriptProposal(title: script.title, source: source, lines: preview.lines, report: preview.report, script: script)
        } catch {
            app.show("The script has a problem: \(error)")
        }
    }

    func importScriptFromClipboard() {
        guard let text = UIPasteboard.general.string, let data = text.data(using: .utf8) else {
            app.show("Copy a Scene Script (JSON) first")
            return
        }
        // Allow a script pasted inside a Markdown code block.
        let cleaned = text.components(separatedBy: "\n").filter { !$0.hasPrefix("```") }.joined(separator: "\n")
        importScript(cleaned.data(using: .utf8) ?? data, source: "Clipboard")
    }
}
