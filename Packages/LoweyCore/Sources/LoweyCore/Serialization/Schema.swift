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

public enum FileKind: String, Sendable {
    case project, scene, library
}

public enum SchemaError: Error, Equatable, CustomStringConvertible {
    case newerThanApp(found: Int, supported: Int)
    case missingMigration(from: Int)
    case malformed(String)

    public var description: String {
        switch self {
        case let .newerThanApp(found, supported):
            "This file was saved by a newer 3D-lowey (schema \(found), this app reads up to \(supported)). Update the app."
        case let .missingMigration(from): "No migration from schema \(from)"
        case let .malformed(reason): "The file is damaged: \(reason)"
        }
    }
}

/// One migration step: transforms the raw JSON *payload* of `kind` from `from` to `from + 1`.
public struct Migration: Sendable {
    public let kind: FileKind
    public let from: Int
    public let transform: @Sendable (JSONValue) throws -> JSONValue

    public init(kind: FileKind, from: Int, transform: @escaping @Sendable (JSONValue) throws -> JSONValue) {
        self.kind = kind
        self.from = from
        self.transform = transform
    }
}

/// Reads and writes versioned files, migrating old ones on load. Migrations exist from day one.
public struct SchemaCoder: Sendable {
    /// Current schema version of every file kind.
    /// v2 (Phase 2): timelines gain markers, loop, cuts, behaviours and clip tracks; the library
    /// gains scripts. The shape is backward compatible, but older apps must refuse v2 files rather
    /// than silently drop animation when they re-save them.
    /// v3 (Phase 3): timelines gain audio clips, transcripts, screen effects, transitions and captions;
    /// looks gain post-processing; new object kinds (text, overlays, particles, characters).
    public static let currentVersion = 3

    public var migrations: [Migration]
    public var currentVersion: Int

    public init(migrations: [Migration] = SchemaCoder.builtInMigrations, currentVersion: Int = SchemaCoder.currentVersion) {
        self.migrations = migrations
        self.currentVersion = currentVersion
    }

    public static let shared = SchemaCoder()

    public func encode<T: Codable & Sendable>(_ payload: T, kind: FileKind) throws -> Data {
        try LoweyJSON.encode(VersionedFile(schemaVersion: currentVersion, kind: kind.rawValue, payload: payload))
    }

    public func decode<T: Codable & Sendable>(_: T.Type, kind: FileKind, from data: Data) throws -> T {
        let raw: JSONValue
        do {
            raw = try LoweyJSON.decode(JSONValue.self, from: data)
        } catch {
            throw SchemaError.malformed("not valid JSON")
        }
        let migrated = try migrate(raw, kind: kind)
        let payload = migrated["payload"] ?? .null
        let payloadData = try LoweyJSON.encode(payload)
        do {
            return try LoweyJSON.decode(T.self, from: payloadData)
        } catch {
            throw SchemaError.malformed(String(describing: error))
        }
    }

    /// Brings a raw file up to `currentVersion`.
    ///
    /// Version 0 files are the pre-envelope format (the bare payload, no `schemaVersion`);
    /// they're wrapped first and then migrated like any other version.
    public func migrate(_ raw: JSONValue, kind: FileKind) throws -> JSONValue {
        var file = raw
        var version: Int
        if let number = raw["schemaVersion"]?.numberValue {
            version = Int(number)
        } else {
            version = 0
            file = .object(["schemaVersion": .number(0), "kind": .string(kind.rawValue), "payload": raw])
        }
        if version > currentVersion { throw SchemaError.newerThanApp(found: version, supported: currentVersion) }
        while version < currentVersion {
            guard let step = migrations.first(where: { $0.kind == kind && $0.from == version }) else {
                throw SchemaError.missingMigration(from: version)
            }
            file["payload"] = try step.transform(file["payload"] ?? .null)
            version += 1
            file["schemaVersion"] = .number(Double(version))
        }
        return file
    }

    /// v0 → v1.
    /// - scene: objects were an array (`"objects": [...]`) and transforms a nested
    ///   `"transform": {"position","rotation","scale"}` object; v1 keys objects by id
    ///   and stores the transform as three animatable properties.
    /// - project / library: unchanged shape, just wrapped.
    public static let builtInMigrations: [Migration] = [
        Migration(kind: .scene, from: 0) { payload in
            var scene = payload
            if let array = payload["objects"]?.arrayValue {
                var keyed: [String: JSONValue] = [:]
                for object in array {
                    guard let id = object["id"]?.stringValue else { continue }
                    keyed[id] = Self.liftTransform(object)
                }
                scene["objects"] = .object(keyed)
            } else if let dictionary = payload["objects"]?.objectValue {
                scene["objects"] = .object(dictionary.mapValues(Self.liftTransform))
            }
            if scene["roots"] == nil, let objects = scene["objects"]?.objectValue {
                let roots = objects.values
                    .filter { $0["parent"] == nil || $0["parent"] == .null }
                    .compactMap { $0["id"]?.stringValue }
                    .sorted()
                scene["roots"] = .array(roots.map(JSONValue.string))
            }
            return scene
        },
        Migration(kind: .project, from: 0) { $0 },
        Migration(kind: .library, from: 0) { $0 },
        // v1 → v2: new fields are optional with defaults; nothing to rewrite.
        Migration(kind: .scene, from: 1) { $0 },
        Migration(kind: .project, from: 1) { $0 },
        Migration(kind: .library, from: 1) { $0 },
        // v2 → v3: additive again (optional fields with defaults).
        Migration(kind: .scene, from: 2) { $0 },
        Migration(kind: .project, from: 2) { $0 },
        Migration(kind: .library, from: 2) { $0 }
    ]

    private static func liftTransform(_ object: JSONValue) -> JSONValue {
        var object = object
        if object["children"] == nil { object["children"] = .array([]) }
        var properties = object["properties"]?.objectValue ?? [:]
        if let transform = object["transform"]?.objectValue {
            if let position = transform["position"] { properties["position"] = .object(["vec3": position]) }
            if let rotation = transform["rotation"] { properties["rotation"] = .object(["quat": rotation]) }
            if let scale = transform["scale"] { properties["scale"] = .object(["vec3": scale]) }
            object["transform"] = nil
            if case var .object(dictionary) = object {
                dictionary.removeValue(forKey: "transform")
                object = .object(dictionary)
            }
        }
        object["properties"] = .object(properties)
        return object
    }
}
