import Foundation

/// Versioned envelope written to disk: `{"schemaVersion": N, "kind": "...", "payload": {...}}`.
public struct VersionedFile<Payload: Codable & Sendable>: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var payload: Payload

    public init(schemaVersion: Int, kind: String, payload: Payload) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.payload = payload
    }
}

public enum SchemaError: Error, Equatable, CustomStringConvertible {
    case newerThanApp(app: String, found: Int, supported: Int)
    case missingMigration(kind: String, from: Int)
    case malformed(String)

    public var description: String {
        switch self {
        case let .newerThanApp(app, found, supported):
            "This file was saved by a newer \(app) (schema \(found); this app reads up to \(supported)). Update the app."
        case let .missingMigration(kind, from): "No migration for \(kind) files from schema \(from)"
        case let .malformed(reason): "The file is damaged: \(reason)"
        }
    }
}

/// One step of a migration chain: rewrites the raw JSON payload of one file kind from `from` to `from + 1`.
public struct Migration: Sendable {
    public let kind: String
    public let from: Int
    public let transform: @Sendable (JSONValue) throws -> JSONValue

    public init(kind: String, from: Int, transform: @escaping @Sendable (JSONValue) throws -> JSONValue) {
        self.kind = kind
        self.from = from
        self.transform = transform
    }
}

/// Reads and writes versioned JSON files, migrating old ones on load.
///
/// Files without a `schemaVersion` are version 0 (the bare payload): they're wrapped, then migrated like any other
/// version. Files from a newer app are refused with a sentence the user understands.
public struct SchemaCoder: Sendable {
    public var appName: String
    public var currentVersion: Int
    public var migrations: [Migration]

    public init(appName: String, currentVersion: Int, migrations: [Migration]) {
        self.appName = appName
        self.currentVersion = currentVersion
        self.migrations = migrations
    }

    public func encode(_ payload: some Codable & Sendable, kind: String) throws -> Data {
        try HmmJSON.encode(VersionedFile(schemaVersion: currentVersion, kind: kind, payload: payload))
    }

    public func decode<T: Codable & Sendable>(_: T.Type, kind: String, from data: Data) throws -> T {
        let raw: JSONValue
        do {
            raw = try HmmJSON.decode(JSONValue.self, from: data)
        } catch {
            throw SchemaError.malformed("not valid JSON")
        }
        let migrated = try migrate(raw, kind: kind)
        let payloadData = try HmmJSON.encode(migrated["payload"] ?? .null)
        do {
            return try HmmJSON.decode(T.self, from: payloadData)
        } catch {
            throw SchemaError.malformed(String(describing: error))
        }
    }

    /// The schema version stored in a file (0 when it has none).
    public static func version(of raw: JSONValue) -> Int {
        raw["schemaVersion"]?.numberValue.map { Int($0) } ?? 0
    }

    /// Brings a raw file up to `currentVersion`.
    public func migrate(_ raw: JSONValue, kind: String) throws -> JSONValue {
        var file = raw
        var version: Int
        if let number = raw["schemaVersion"]?.numberValue {
            version = Int(number)
        } else {
            version = 0
            file = .object(["schemaVersion": .number(0), "kind": .string(kind), "payload": raw])
        }
        if version > currentVersion {
            throw SchemaError.newerThanApp(app: appName, found: version, supported: currentVersion)
        }
        while version < currentVersion {
            guard let step = migrations.first(where: { $0.kind == kind && $0.from == version }) else {
                throw SchemaError.missingMigration(kind: kind, from: version)
            }
            file["payload"] = try step.transform(file["payload"] ?? .null)
            version += 1
            file["schemaVersion"] = .number(Double(version))
        }
        return file
    }
}
