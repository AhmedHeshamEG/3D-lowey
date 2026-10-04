import Foundation
import HmmCommands

/// The document at any moment of the undo history, for the history scrubber: position `n` is "now" (every step
/// applied), position 0 is before the oldest step kept. Moving steps through the inverses (back) or the commands
/// (forward) from wherever the cursor is, so dragging costs one step per notch, never a replay from the start.
public struct HistoryCursor: Sendable {
    public private(set) var position: Int
    public private(set) var document: Document
    /// The undo steps, oldest first.
    public let steps: [HistoryEntry<EditCommand>]

    public init(document: Document, steps: [HistoryEntry<EditCommand>]) {
        self.document = document
        self.steps = steps
        position = steps.count
    }

    public var count: Int { steps.count }
    public var isNow: Bool { position == steps.count }

    /// The step that leads to `position` ("Move Lamp"), nil at the very start.
    public func label(at position: Int) -> String? {
        position > 0 && position <= steps.count ? steps[position - 1].label : nil
    }

    /// Moves to `target` (clamped) and returns everything that changed on the way.
    @discardableResult
    public mutating func move(to target: Int) throws -> ChangeSet {
        let target = min(max(target, 0), steps.count)
        var changes = ChangeSet()
        while position > target {
            try changes.formUnion(steps[position - 1].inverse.apply(to: &document).changes)
            position -= 1
        }
        while position < target {
            try changes.formUnion(steps[position].command.apply(to: &document).changes)
            position += 1
        }
        return changes
    }
}
