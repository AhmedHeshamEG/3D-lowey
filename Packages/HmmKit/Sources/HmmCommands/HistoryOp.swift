/// One change to a `CommandStack`, as a history journal records it. Replaying the ops in order on the document they
/// started from rebuilds the same document and the same undo history.
public enum HistoryOp<Command: EditCommand>: Sendable {
    case perform(Command, coalesceKey: String?)
    case endCoalescing
    case beginGroup(String)
    case endGroup
    case cancelGroup
    case undo
    case redo
}

extension HistoryOp: Codable where Command: Codable {
    private enum Key: String, CodingKey { case op, command, key, label }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .op) {
        case "perform": self = try .perform(c.decode(Command.self, forKey: .command), coalesceKey: c.decodeIfPresent(String.self, forKey: .key))
        case "endCoalescing": self = .endCoalescing
        case "beginGroup": self = try .beginGroup(c.decode(String.self, forKey: .label))
        case "endGroup": self = .endGroup
        case "cancelGroup": self = .cancelGroup
        case "undo": self = .undo
        case "redo": self = .redo
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .op, in: c, debugDescription: "Unknown history op \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .perform(command, key):
            try c.encode("perform", forKey: .op)
            try c.encode(command, forKey: .command)
            try c.encodeIfPresent(key, forKey: .key)
        case let .beginGroup(label):
            try c.encode("beginGroup", forKey: .op)
            try c.encode(label, forKey: .label)
        case .endCoalescing: try c.encode("endCoalescing", forKey: .op)
        case .endGroup: try c.encode("endGroup", forKey: .op)
        case .cancelGroup: try c.encode("cancelGroup", forKey: .op)
        case .undo: try c.encode("undo", forKey: .op)
        case .redo: try c.encode("redo", forKey: .op)
        }
    }
}
