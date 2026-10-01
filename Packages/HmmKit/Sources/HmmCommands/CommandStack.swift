/// Errors of the command stack itself (a command's own errors pass through unchanged).
public enum CommandStackError: Error, Equatable, CustomStringConvertible {
    case groupNotOpen

    public var description: String {
        switch self {
        case .groupNotOpen: "There is no open group to end."
        }
    }
}

/// Undo and redo for one document.
///
/// - **Coalescing:** consecutive commands with the same `coalesceKey` merge into one step until `endCoalescing()`
///   (or a command with another key). The first inverse is kept, so undo returns to the state before the gesture.
/// - **Grouping:** everything performed between `beginGroup(_:)` and `endGroup()` becomes one step with the group's
///   label ("Undo Add Lamp"). Groups nest; only the outermost one produces a history entry.
/// - **Limits:** the oldest steps are dropped beyond `limit`.
/// - **Labels:** `undoTitle` / `redoTitle` are ready for the Undo menu ("Undo Move Camera").
///
/// A value type: the owner keeps it next to the document and passes the document in, so a stack can never mutate
/// a document it doesn't own.
public struct CommandStack<Command: EditCommand>: Sendable {
    public private(set) var undoStack: [HistoryEntry<Command>] = []
    public private(set) var redoStack: [HistoryEntry<Command>] = []
    /// Bumped on every change (perform, undo, redo): autosave compares it with the last saved revision.
    public private(set) var revision = 0
    /// Most steps kept.
    public var limit: Int

    private var openCoalesceKey: String?
    private var groups: [OpenGroup] = []

    private struct OpenGroup: Sendable {
        var label: String
        var commands: [Command] = []
        var inverses: [Command] = []
    }

    public init(limit: Int = 500) {
        self.limit = max(limit, 1)
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoLabel: String? { undoStack.last?.label }
    public var redoLabel: String? { redoStack.last?.label }
    /// "Undo Move Camera", or "Undo" when there is nothing to undo.
    public var undoTitle: String { undoLabel.map { "Undo \($0)" } ?? "Undo" }
    public var redoTitle: String { redoLabel.map { "Redo \($0)" } ?? "Redo" }
    /// Whether a group is open (commands are being collected into one step).
    public var isGrouping: Bool { !groups.isEmpty }

    /// Applies a command to `target` and records it for undo.
    @discardableResult
    public mutating func perform(_ command: Command, on target: inout Command.Target, coalesceKey: String? = nil) throws -> Command.Changes {
        let result = try command.apply(to: &target)
        revision += 1
        redoStack.removeAll()
        if !groups.isEmpty {
            groups[groups.count - 1].commands.append(command)
            groups[groups.count - 1].inverses.append(result.inverse)
            return result.changes
        }
        if let coalesceKey, coalesceKey == openCoalesceKey, var last = undoStack.popLast(), last.coalesceKey == coalesceKey {
            last.command = Command.coalesced(last.command, command)
            last.inverse = Command.coalescedInverse(earlier: last.inverse, later: result.inverse)
            undoStack.append(last)
        } else {
            push(HistoryEntry(command: command, inverse: result.inverse, coalesceKey: coalesceKey))
        }
        openCoalesceKey = coalesceKey
        return result.changes
    }

    /// Ends the current continuous gesture: the next command starts a new step.
    public mutating func endCoalescing() {
        openCoalesceKey = nil
    }

    /// Starts collecting commands into one step called `label`.
    public mutating func beginGroup(_ label: String) {
        openCoalesceKey = nil
        groups.append(OpenGroup(label: label))
    }

    /// Closes the innermost group. The outermost group becomes one history entry (nothing if it was empty).
    public mutating func endGroup() throws {
        guard let group = groups.popLast() else { throw CommandStackError.groupNotOpen }
        guard !group.commands.isEmpty else { return }
        let command = Command.group(group.label, group.commands)
        let inverse = Command.group(group.label, group.inverses.reversed())
        if groups.isEmpty {
            push(HistoryEntry(command: command, inverse: inverse, customLabel: group.label))
        } else {
            groups[groups.count - 1].commands.append(command)
            groups[groups.count - 1].inverses.append(inverse)
        }
    }

    /// Closes the innermost group and reverts everything it did (a compound action that failed halfway).
    public mutating func cancelGroup(on target: inout Command.Target) throws {
        guard let group = groups.popLast() else { throw CommandStackError.groupNotOpen }
        for inverse in group.inverses.reversed() {
            _ = try inverse.apply(to: &target)
            revision += 1
        }
    }

    @discardableResult
    public mutating func undo(on target: inout Command.Target) throws -> Command.Changes? {
        guard groups.isEmpty, let entry = undoStack.popLast() else { return nil }
        openCoalesceKey = nil
        do {
            let result = try entry.inverse.apply(to: &target)
            revision += 1
            redoStack.append(HistoryEntry(command: entry.command, inverse: result.inverse, customLabel: entry.customLabel))
            return result.changes
        } catch {
            undoStack.append(entry)
            throw error
        }
    }

    @discardableResult
    public mutating func redo(on target: inout Command.Target) throws -> Command.Changes? {
        guard groups.isEmpty, let entry = redoStack.popLast() else { return nil }
        openCoalesceKey = nil
        do {
            let result = try entry.command.apply(to: &target)
            revision += 1
            undoStack.append(HistoryEntry(command: entry.command, inverse: result.inverse, customLabel: entry.customLabel))
            return result.changes
        } catch {
            redoStack.append(entry)
            throw error
        }
    }

    /// Records a change that isn't an edit (navigation, metadata) so autosave notices it.
    public mutating func touch() {
        revision += 1
    }

    public mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        openCoalesceKey = nil
        groups.removeAll()
    }

    private mutating func push(_ entry: HistoryEntry<Command>) {
        undoStack.append(entry)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
    }
}
