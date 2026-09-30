import Foundation
import HmmCommands

/// `EditCommand` speaks hmm-kit's command protocol, so undo/redo, coalescing and grouping are `CommandStack`'s.
extension EditCommand: HmmCommands.EditCommand {
    public typealias Target = Document
    public typealias Changes = ChangeSet

    public static func group(_ label: String, _ commands: [EditCommand]) -> EditCommand {
        .batch(label, commands)
    }

    /// Merges two forward commands of one gesture. Property sets and key edits collapse to the latest values.
    public static func coalesced(_ first: EditCommand, _ second: EditCommand) -> EditCommand {
        if case let .setProperties(a) = first, case let .setProperties(b) = second {
            var order: [String] = []
            var latest: [String: PropertyChange] = [:]
            for change in a + b {
                let key = "\(change.object.raw)|\(change.key.rawValue)"
                if latest[key] == nil { order.append(key) }
                latest[key] = change
            }
            return .setProperties(order.compactMap { latest[$0] })
        }
        if case let .setTracks(a) = first, case let .setTracks(b) = second {
            var order: [TrackID] = []
            var latest: [TrackID: TrackEdit] = [:]
            for edit in a + b {
                if latest[edit.id] == nil { order.append(edit.id) }
                latest[edit.id] = edit
            }
            return .setTracks(order.compactMap { latest[$0] })
        }
        if case let .batch(label, commands) = first {
            return .batch(label, commands + [second])
        }
        return .batch(second.label, [first, second])
    }

    /// Inverse of a merged gesture. For property sets it collapses to the pre-gesture value of every touched
    /// property; for key edits the earlier inverses restore the pre-gesture tracks.
    public static func coalescedInverse(earlier: EditCommand, later: EditCommand) -> EditCommand {
        if case let .setProperties(a) = earlier, case let .setProperties(b) = later {
            var seen = Set(a.map { "\($0.object.raw)|\($0.key.rawValue)" })
            var merged = a
            for change in b where seen.insert("\(change.object.raw)|\(change.key.rawValue)").inserted {
                merged.append(change)
            }
            return .setProperties(merged)
        }
        if case let .setTracks(a) = earlier, case let .setTracks(b) = later {
            var seen = Set(a.map(\.id))
            var merged: [TrackEdit] = []
            for edit in b where seen.insert(edit.id).inserted {
                merged.append(edit)
            }
            return .setTracks(merged + a)
        }
        return .batch(earlier.label, [later, earlier])
    }
}

/// A document plus its undo history. A value type: easy to test, impossible to change without a command.
public struct EditSession: Sendable {
    public private(set) var document: Document
    public private(set) var history: CommandStack<EditCommand>

    public init(document: Document, historyLimit: Int = 500) {
        self.document = document
        history = CommandStack(limit: historyLimit)
    }

    public var undoStack: [HistoryEntry<EditCommand>] { history.undoStack }
    public var redoStack: [HistoryEntry<EditCommand>] { history.redoStack }
    /// Bumped on every change; autosave compares it with the last saved revision.
    public var revision: Int { history.revision }
    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }
    public var undoLabel: String? { history.undoLabel }
    public var redoLabel: String? { history.redoLabel }
    /// "Undo Move Camera" for the Undo menu.
    public var undoTitle: String { history.undoTitle }
    public var redoTitle: String { history.redoTitle }

    /// Applies a command and records it for undo. Commands sharing a `coalesceKey` merge into one step until
    /// `endCoalescing()` (continuous gestures).
    @discardableResult
    public mutating func perform(_ command: EditCommand, coalesceKey: String? = nil) throws -> ChangeSet {
        try history.perform(command, on: &document, coalesceKey: coalesceKey)
    }

    /// Ends the current continuous gesture: the next command starts a new undo step.
    public mutating func endCoalescing() {
        history.endCoalescing()
    }

    /// Everything performed until `endGroup()` becomes one undo step called `label`.
    public mutating func beginGroup(_ label: String) {
        history.beginGroup(label)
    }

    public mutating func endGroup() throws {
        try history.endGroup()
    }

    @discardableResult
    public mutating func undo() throws -> ChangeSet? {
        try history.undo(on: &document)
    }

    @discardableResult
    public mutating func redo() throws -> ChangeSet? {
        try history.redo(on: &document)
    }

    /// Replaces the scene camera viewpoint. Navigation is not an edit: no history entry, but the revision bumps so
    /// the viewpoint is saved.
    public mutating func setViewpoint(_ viewpoint: Viewpoint) {
        guard document.scene.viewpoint != viewpoint else { return }
        document.scene.viewpoint = viewpoint
        history.touch()
    }

    /// Updates the project record (a rename from the Theater) without history.
    public mutating func updateProjectInfo(_ update: (inout ProjectInfo) -> Void) {
        update(&document.project)
        history.touch()
    }

    public mutating func clearHistory() {
        history.clear()
    }
}
