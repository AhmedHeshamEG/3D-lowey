import Foundation

/// Strongly typed string identifiers. They encode as plain JSON strings and can be
/// used as dictionary keys that encode as JSON objects (via `CodingKeyRepresentable`).
public protocol LoweyIdentifier: Hashable, Sendable, Codable, Comparable, CodingKeyRepresentable,
    CustomStringConvertible, ExpressibleByStringLiteral {
    var raw: String { get }
    init(raw: String)
}

public extension LoweyIdentifier {
    /// A fresh random identifier (lowercase UUID).
    static func make() -> Self { Self(raw: UUID().uuidString.lowercased()) }

    init(stringLiteral value: String) { self.init(raw: value) }

    init(from decoder: Decoder) throws {
        try self.init(raw: decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    var codingKey: CodingKey { IdentifierCodingKey(stringValue: raw) }

    init?(codingKey: some CodingKey) { self.init(raw: codingKey.stringValue) }

    var description: String { raw }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.raw < rhs.raw }
}

struct IdentifierCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue _: Int) { nil }
}

public struct ObjectID: LoweyIdentifier {
    public let raw: String
    public init(raw: String) { self.raw = raw }
}

public struct SceneID: LoweyIdentifier {
    public let raw: String
    public init(raw: String) { self.raw = raw }
}

public struct ProjectID: LoweyIdentifier {
    public let raw: String
    public init(raw: String) { self.raw = raw }
}

public struct AssetID: LoweyIdentifier {
    public let raw: String
    public init(raw: String) { self.raw = raw }
}

public struct PrefabID: LoweyIdentifier {
    public let raw: String
    public init(raw: String) { self.raw = raw }
}

public struct LookPresetID: LoweyIdentifier {
    public let raw: String
    public init(raw: String) { self.raw = raw }
}

public struct TrackID: LoweyIdentifier {
    public let raw: String
    public init(raw: String) { self.raw = raw }
}

public struct ScriptID: LoweyIdentifier {
    public let raw: String
    public init(raw: String) { self.raw = raw }
}

/// Deterministic identifier factory. The app uses random IDs; tests, samples and
/// Scene Scripts can use a counter so output is reproducible.
public struct IDFactory: Sendable {
    private var counter: Int
    private let prefix: String?

    /// Random UUIDs.
    public static var random: IDFactory { IDFactory(prefix: nil) }

    /// Sequential IDs: `"<prefix>-1"`, `"<prefix>-2"`, …
    public static func sequential(_ prefix: String) -> IDFactory { IDFactory(prefix: prefix) }

    private init(prefix: String?) {
        self.prefix = prefix
        counter = 0
    }

    /// Sequential factories make deterministic samples and tests.
    public var isSequential: Bool { prefix != nil }

    public mutating func next<ID: LoweyIdentifier>(_: ID.Type = ID.self) -> ID {
        guard let prefix else { return ID.make() }
        counter += 1
        return ID(raw: "\(prefix)-\(counter)")
    }
}
