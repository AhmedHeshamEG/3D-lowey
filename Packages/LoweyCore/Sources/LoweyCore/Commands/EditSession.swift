import Foundation

/// One entry of the undo history.
public struct HistoryEntry: Hashable, Sendable {
    public var command: EditCommand
    public var inverse: EditCommand
    /// Continuous gestures (joystick, drag, slider) share a key so the whole
    /// gesture becomes one undo step.
    public var coalesceKey: String?

    public var label: String { command.label }
}

/// A document plus its undo/redo history. A pure value type: easy to test,
/// impossible to mutate without going through `perform`.
public struct EditSession: Sendable {
    public private(set) var document: Document
    public private(set) var undoStack: [HistoryEntry] = []
    public private(set) var redoStack: [HistoryEntry] = []
    /// Bumped on every change; autosave compares it with the last saved revision.
    public private(set) var revision = 0
    public var historyLimit: Int

    private var openCoalesceKey: String?

    public init(document: Document, historyLimit: Int = 500) {
        self.document = document
        self.historyLimit = historyLimit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoLabel: String? { undoStack.last?.label }
    public var redoLabel: String? { redoStack.last?.label }

    /// Applies a command and records it for undo.
    ///
    /// With a `coalesceKey`, consecutive commands with the same key merge into one
    /// history entry until `endCoalescing()` (or a command with another key) is called.
    @discardableResult
    public mutating func perform(_ command: EditCommand, coalesceKey: String? = nil) throws -> ChangeSet {
        let result = try command.apply(to: &document)
        revision += 1
        redoStack.removeAll()
        if let coalesceKey, coalesceKey == openCoalesceKey, var last = undoStack.popLast(), last.coalesceKey == coalesceKey {
            // Keep the *first* inverse (state before the gesture) and accumulate the forward commands.
            last.command = Self.merge(last.command, command)
            last.inverse = Self.mergeInverse(earlier: last.inverse, later: result.inverse)
            undoStack.append(last)
        } else {
            undoStack.append(HistoryEntry(command: command, inverse: result.inverse, coalesceKey: coalesceKey))
            if undoStack.count > historyLimit { undoStack.removeFirst(undoStack.count - historyLimit) }
        }
        openCoalesceKey = coalesceKey
        return result.changes
    }

    /// Ends the current continuous gesture: the next command starts a new undo step.
    public mutating func endCoalescing() {
        openCoalesceKey = nil
    }

    @discardableResult
    public mutating func undo() throws -> ChangeSet? {
        guard let entry = undoStack.popLast() else { return nil }
        openCoalesceKey = nil
        let result = try entry.inverse.apply(to: &document)
        revision += 1
        redoStack.append(HistoryEntry(command: entry.command, inverse: result.inverse, coalesceKey: nil))
        return result.changes
    }

    @discardableResult
    public mutating func redo() throws -> ChangeSet? {
        guard let entry = redoStack.popLast() else { return nil }
        openCoalesceKey = nil
        let result = try entry.command.apply(to: &document)
        revision += 1
        undoStack.append(HistoryEntry(command: entry.command, inverse: result.inverse, coalesceKey: nil))
        return result.changes
    }

    /// Replaces the scene camera viewpoint. Navigation is not an edit: no history entry,
    /// but the revision bumps so the viewpoint is saved.
    public mutating func setViewpoint(_ viewpoint: Viewpoint) {
        guard document.scene.viewpoint != viewpoint else { return }
        document.scene.viewpoint = viewpoint
        revision += 1
    }

    /// Updates the project-level record (e.g. after a rename from Home) without history.
    public mutating func updateProjectInfo(_ update: (inout ProjectInfo) -> Void) {
        update(&document.project)
        revision += 1
    }

    public mutating func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        openCoalesceKey = nil
    }

    /// Merges two forward commands of one gesture. Property sets collapse to the latest values.
    private static func merge(_ first: EditCommand, _ second: EditCommand) -> EditCommand {
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

    /// Inverse of a merged gesture: undo the later part, then the earlier part. For property
    /// sets this collapses to the pre-gesture values of every touched property.
    private static func mergeInverse(earlier: EditCommand, later: EditCommand) -> EditCommand {
        if case let .setProperties(a) = earlier, case let .setProperties(b) = later {
            var seen = Set(a.map { "\($0.object.raw)|\($0.key.rawValue)" })
            var merged = a
            for change in b where seen.insert("\(change.object.raw)|\(change.key.rawValue)").inserted {
                merged.append(change)
            }
            return .setProperties(merged)
        }
        if case let .setTracks(a) = earlier, case let .setTracks(b) = later {
            // Earlier inverses restore the pre-gesture tracks; later ones only matter for tracks
            // the gesture created after it started.
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
