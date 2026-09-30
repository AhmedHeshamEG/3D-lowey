/// A reversible edit of a document.
///
/// Every mutation of a document in an hmm. app is one of these, executed through a `CommandStack`: the UI, gestures,
/// scripts and AI batches all speak the same language, so undo is exact and nothing changes a document behind the
/// stack's back. `apply` must be atomic (it either changes the target completely or throws and leaves it untouched)
/// and must return the exact inverse of what it did.
public protocol EditCommand: Sendable {
    /// What the command edits (usually the app's document value).
    associatedtype Target
    /// What the command reports as changed (so renderers and views update only what moved).
    associatedtype Changes

    /// A short verb phrase for the Undo menu, e.g. "Move Camera" (shown as "Undo Move Camera").
    var label: String { get }

    /// Applies the command and returns its exact inverse plus what changed.
    func apply(to target: inout Target) throws -> (inverse: Self, changes: Changes)

    /// Several commands applied in order as one step (compound actions, AI batches, groups).
    static func group(_ label: String, _ commands: [Self]) -> Self

    /// Two forward commands of one continuous gesture merged into one (the default groups them).
    static func coalesced(_ first: Self, _ second: Self) -> Self

    /// The inverse of a merged gesture, given the inverse of its earlier part and of its later part.
    /// The default undoes the later part first, then the earlier part.
    static func coalescedInverse(earlier: Self, later: Self) -> Self
}

public extension EditCommand {
    static func coalesced(_ first: Self, _ second: Self) -> Self {
        group(second.label, [first, second])
    }

    static func coalescedInverse(earlier: Self, later: Self) -> Self {
        group(earlier.label, [later, earlier])
    }
}

/// One step of the undo history.
public struct HistoryEntry<Command: EditCommand>: Sendable {
    public var command: Command
    public var inverse: Command
    /// Continuous gestures (drags, sliders, joysticks) share a key so the whole gesture is one undo step.
    public var coalesceKey: String?
    /// Overrides the command's own label (named groups).
    public var customLabel: String?

    public init(command: Command, inverse: Command, coalesceKey: String? = nil, customLabel: String? = nil) {
        self.command = command
        self.inverse = inverse
        self.coalesceKey = coalesceKey
        self.customLabel = customLabel
    }

    public var label: String { customLabel ?? command.label }
}
