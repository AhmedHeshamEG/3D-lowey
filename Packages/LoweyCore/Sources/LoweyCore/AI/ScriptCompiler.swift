import Foundation

/// Scene Script v2 "actions": an AI-friendly (and hand-writable) language on top of the command system.
/// Objects are named, not id'd; times can be seconds, a spoken word or a marker; everything compiles to ordinary
/// `EditCommand`s against the current document and applies as ONE undo step. See `/schemas/scene-script.schema.json`.
///
///     {"do": "add", "shape": "cube", "name": "Paper", "at": [0, 0.8, 0], "size": [0.3, 0.01, 0.4], "color": "palette:0"}
///     {"do": "preset", "target": "Screen*", "preset": "popIn", "at": {"word": "Nobody"}, "stagger": 0.08}
///     {"do": "cameraMove", "move": "pushIn", "subject": "Paper", "at": {"word": "message"}, "duration": 2}
public struct ScriptContext: Sendable {
    public var library: LibraryManifest
    /// The playhead ("now").
    public var now: Double
    /// Where new things go when no position is given (the middle of the view).
    public var focus: Vec3
    public var ids: IDFactory

    public init(library: LibraryManifest = LibraryManifest(), now: Double = 0, focus: Vec3 = .zero, ids: IDFactory = .random) {
        self.library = library
        self.now = now
        self.focus = focus
        self.ids = ids
    }
}

public struct ScriptResult: Sendable {
    /// Everything as one command (nil when the script changes nothing).
    public var command: EditCommand?
    /// One human-readable line per action.
    public var report: [String]
    /// Names given in the script → the objects they became.
    public var created: [String: ObjectID]
    /// The document after the script (for previews).
    public var document: Document
}

public struct ScriptError: Error, Equatable, CustomStringConvertible {
    /// 0-based action index.
    public var action: Int
    public var message: String

    public var description: String { "Action \(action + 1): \(message)" }
}

public enum ScriptCompiler {
    public static func compile(_ script: SceneScript, document: Document, context: ScriptContext) throws -> ScriptResult {
        var state = ScriptState(document: document, context: context)
        for (index, command) in script.commands.enumerated() {
            do {
                try state.run(command, label: nil)
            } catch {
                throw ScriptError(action: index, message: "command failed: \(error)")
            }
        }
        for (index, action) in script.actions.enumerated() {
            do {
                try state.perform(action)
            } catch let error as ScriptError {
                throw ScriptError(action: index + script.commands.count, message: error.message)
            } catch {
                throw ScriptError(action: index + script.commands.count, message: String(describing: error))
            }
        }
        let command: EditCommand? = state.commands.isEmpty ? nil : .batch(script.title, state.commands)
        return ScriptResult(command: command, report: state.report, created: state.created, document: state.document)
    }

    /// Compiles and describes the change without applying it (the AI proposes, you decide).
    public static func preview(_ script: SceneScript, document: Document, context: ScriptContext) throws -> ScriptPreview {
        let result = try compile(script, document: document, context: context)
        return ScriptPreview(before: document, after: result.document, report: result.report)
    }
}

/// What a script would change, in plain words.
public struct ScriptPreview: Sendable {
    public var added: [String]
    public var removed: [String]
    public var changed: [String]
    public var keyedTracks: Int
    public var timelineChanges: [String]
    public var lookChanged: Bool
    public var report: [String]

    public init(before: Document, after: Document, report: [String]) {
        let old = before.scene.objects
        let new = after.scene.objects
        added = new.keys.filter { old[$0] == nil }.compactMap { new[$0]?.name }.sorted()
        removed = old.keys.filter { new[$0] == nil }.compactMap { old[$0]?.name }.sorted()
        changed = new.keys.filter { old[$0] != nil && old[$0] != new[$0] }.compactMap { new[$0]?.name }.sorted()
        let oldTracks = Dictionary(before.scene.timeline.tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        keyedTracks = after.scene.timeline.tracks.filter { oldTracks[$0.id] != $0 }.count
        var timeline: [String] = []
        let a = before.scene.timeline
        let b = after.scene.timeline
        if a.cuts != b.cuts { timeline.append("camera cuts: \(a.cuts.count) → \(b.cuts.count)") }
        if a.effects != b.effects { timeline.append("screen effects: \(a.effects.count) → \(b.effects.count)") }
        if a.markers != b.markers { timeline.append("markers: \(a.markers.count) → \(b.markers.count)") }
        if a.clipTracks != b.clipTracks { timeline.append("character clips changed") }
        if a.captions != b.captions { timeline.append("captions changed") }
        if a.duration != b.duration { timeline.append("length \(a.duration) s → \(b.duration) s") }
        timelineChanges = timeline
        lookChanged = before.effectiveLook != after.effectiveLook
        self.report = report
    }

    public var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && changed.isEmpty && keyedTracks == 0 && timelineChanges.isEmpty && !lookChanged
    }

    public var lines: [String] {
        var lines: [String] = []
        if !added.isEmpty { lines.append("Adds \(added.count): \(added.prefix(8).joined(separator: ", "))\(added.count > 8 ? "…" : "")") }
        if !removed.isEmpty { lines.append("Removes \(removed.count): \(removed.prefix(8).joined(separator: ", "))") }
        if !changed.isEmpty { lines.append("Changes \(changed.count): \(changed.prefix(8).joined(separator: ", "))\(changed.count > 8 ? "…" : "")") }
        if keyedTracks > 0 { lines.append("Animates \(keyedTracks) propert\(keyedTracks == 1 ? "y" : "ies")") }
        lines += timelineChanges.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        if lookChanged { lines.append("Changes the look") }
        return lines
    }
}

// MARK: - Scene Script v2

public extension SceneScript {
    /// Version with `actions` (v1 scripts only had raw commands; both still load).
    static let actionsVersion = 2
}

// MARK: - Compiler state

struct ScriptState {
    var document: Document
    var context: ScriptContext
    var commands: [EditCommand] = []
    var report: [String] = []
    var created: [String: ObjectID] = [:]
    var operations: Operations

    init(document: Document, context: ScriptContext) {
        self.document = document
        self.context = context
        operations = Operations(ids: context.ids, library: context.library)
    }

    var scene: Scene { document.scene }
    var timeline: Timeline { document.scene.timeline }

    mutating func run(_ command: EditCommand?, label: String?) throws {
        guard let command else { return }
        var working = document
        _ = try command.apply(to: &working)
        document = working
        commands.append(command)
        if let label { report.append(label) }
    }

    /// Operations that make objects share the script's one id source (no collisions with deterministic ids).
    mutating func withOperations<T>(_ body: (inout Operations, Scene) -> T) -> T {
        operations.ids = context.ids
        let current = scene
        let result = body(&operations, current)
        context.ids = operations.ids
        return result
    }

    func fail(_ message: String) -> ScriptError { ScriptError(action: 0, message: message) }
}
