import Foundation
import HmmDocuments

/// The JSON files inside a `.lowey` package and the library.
public enum FileKind: String, Sendable {
    case project, scene, library
}

public extension Migration {
    init(kind: FileKind, from: Int, transform: @escaping @Sendable (JSONValue) throws -> JSONValue) {
        self.init(kind: kind.rawValue, from: from, transform: transform)
    }
}

public extension SchemaCoder {
    /// Maquette's coder: current schema, every migration since v0.
    static let shared = SchemaCoder(appName: "Maquette", currentVersion: LoweySchema.currentVersion, migrations: LoweySchema.migrations)

    func encode(_ payload: some Codable & Sendable, kind: FileKind) throws -> Data {
        try encode(payload, kind: kind.rawValue)
    }

    func decode<T: Codable & Sendable>(_ type: T.Type, kind: FileKind, from data: Data) throws -> T {
        try decode(type, kind: kind.rawValue, from: data)
    }

    func migrate(_ raw: JSONValue, kind: FileKind) throws -> JSONValue {
        try migrate(raw, kind: kind.rawValue)
    }
}

/// Schema versions of Maquette's JSON files.
///
/// - v1: objects keyed by id, transforms as properties.
/// - v2 (1.0 phase 2): timelines gain markers, loop, cuts, behaviours, clip tracks. Additive.
/// - v3 (1.0 phase 3): audio, transcripts, effects, transitions, captions; looks gain post. Additive.
/// - v4 (2.0): looks gain a render style (`presetID`); projects gain their own Looks. Files from 1.x keep their
///   appearance: they open in Clay (the v1 look on the new renderer), or Low-poly when they were faceted.
public enum LoweySchema {
    /// 5: Maquette 0.3's `mesh` and `sketch` objects (older apps refuse these files instead of misreading them).
    /// 6: Maquette 0.4's `dimension` objects and the `symmetry` property.
    public static let currentVersion = 6

    public static let migrations: [Migration] = [
        Migration(kind: .scene, from: 0, transform: liftSceneV0),
        Migration(kind: .project, from: 0) { $0 },
        Migration(kind: .library, from: 0) { $0 },
        Migration(kind: .scene, from: 1) { $0 },
        Migration(kind: .project, from: 1) { $0 },
        Migration(kind: .library, from: 1) { $0 },
        Migration(kind: .scene, from: 2) { $0 },
        Migration(kind: .project, from: 2) { $0 },
        Migration(kind: .library, from: 2) { $0 },
        Migration(kind: .scene, from: 3) { keepV1Appearance($0) },
        Migration(kind: .project, from: 3) { keepV1Appearance($0) },
        Migration(kind: .library, from: 3) { keepV1Appearance($0) },
        // 4 → 5 adds object kinds; nothing older changes shape.
        Migration(kind: .scene, from: 4) { $0 },
        Migration(kind: .project, from: 4) { $0 },
        Migration(kind: .library, from: 4) { $0 },
        // 5 → 6 adds an object kind; nothing older changes shape.
        Migration(kind: .scene, from: 5) { $0 },
        Migration(kind: .project, from: 5) { $0 },
        Migration(kind: .library, from: 5) { $0 }
    ]

    /// The render style a 1.x look maps to.
    static func v1PresetID(for look: JSONValue) -> String {
        look["shading"]?.stringValue == "flat" ? LookPreset.lowPoly.id : LookPreset.clay.id
    }

    /// Every look in the file (project look, scene look, saved library looks) gets the style that keeps its v1
    /// appearance. A look is any object with a palette, lighting and sky.
    static func keepV1Appearance(_ value: JSONValue) -> JSONValue {
        switch value {
        case var .object(dictionary):
            for (key, child) in dictionary {
                dictionary[key] = keepV1Appearance(child)
            }
            if dictionary["palette"] != nil, dictionary["lighting"] != nil, dictionary["sky"] != nil, dictionary["presetID"] == nil {
                dictionary["presetID"] = .string(v1PresetID(for: .object(dictionary)))
            }
            return .object(dictionary)
        case let .array(items):
            return .array(items.map(keepV1Appearance))
        default:
            return value
        }
    }

    /// v0 → v1: objects were an array with nested transforms; v1 keys them by id with transform properties.
    static func liftSceneV0(_ payload: JSONValue) -> JSONValue {
        var scene = payload
        if let array = payload["objects"]?.arrayValue {
            var keyed: [String: JSONValue] = [:]
            for object in array {
                guard let id = object["id"]?.stringValue else { continue }
                keyed[id] = liftTransform(object)
            }
            scene["objects"] = .object(keyed)
        } else if let dictionary = payload["objects"]?.objectValue {
            scene["objects"] = .object(dictionary.mapValues(liftTransform))
        }
        if scene["roots"] == nil, let objects = scene["objects"]?.objectValue {
            let roots = objects.values
                .filter { $0["parent"] == nil || $0["parent"] == .null }
                .compactMap { $0["id"]?.stringValue }
                .sorted()
            scene["roots"] = .array(roots.map(JSONValue.string))
        }
        return scene
    }

    private static func liftTransform(_ object: JSONValue) -> JSONValue {
        guard case var .object(dictionary) = object else { return object }
        if dictionary["children"] == nil { dictionary["children"] = .array([]) }
        var properties = dictionary["properties"]?.objectValue ?? [:]
        if let transform = dictionary["transform"]?.objectValue {
            if let position = transform["position"] { properties["position"] = .object(["vec3": position]) }
            if let rotation = transform["rotation"] { properties["rotation"] = .object(["quat": rotation]) }
            if let scale = transform["scale"] { properties["scale"] = .object(["vec3": scale]) }
            dictionary.removeValue(forKey: "transform")
        }
        dictionary["properties"] = .object(properties)
        return .object(dictionary)
    }
}
