import Foundation

/// A self-contained piece of a scene: objects plus which of them are the top-level ones.
/// Used for inserting, duplicating, copy/paste, prefabs and delete/restore.
public struct SceneFragment: Codable, Hashable, Sendable {
    /// All objects, parents before children. Root objects' `parent` is ignored on insert.
    public var objects: [SceneObject]
    public var roots: [ObjectID]

    public init(objects: [SceneObject], roots: [ObjectID]) {
        self.objects = objects
        self.roots = roots
    }

    /// A fragment with a single parentless object.
    public init(object: SceneObject) {
        var object = object
        object.parent = nil
        self.init(objects: [object], roots: [object.id])
    }

    public var isEmpty: Bool { objects.isEmpty }
}

/// One property change. `value == nil` removes the property (back to its default).
public struct PropertyChange: Codable, Hashable, Sendable {
    public var object: ObjectID
    public var key: PropertyKey
    public var value: PropertyValue?

    public init(object: ObjectID, key: PropertyKey, value: PropertyValue?) {
        self.object = object
        self.key = key
        self.value = value
    }
}

/// Moves an object in the hierarchy (and optionally sets its local transform in the same step).
public struct ReparentEntry: Codable, Hashable, Sendable {
    public var object: ObjectID
    public var parent: ObjectID?
    /// Position among the new siblings; `nil` appends.
    public var index: Int?
    public var transform: Transform?

    public init(object: ObjectID, parent: ObjectID?, index: Int? = nil, transform: Transform? = nil) {
        self.object = object
        self.parent = parent
        self.index = index
        self.transform = transform
    }
}

/// Where a restored subtree goes back.
public struct RestoreEntry: Codable, Hashable, Sendable {
    public var fragment: SceneFragment
    public var parent: ObjectID?
    public var index: Int

    public init(fragment: SceneFragment, parent: ObjectID?, index: Int) {
        self.fragment = fragment
        self.parent = parent
        self.index = index
    }
}

/// Inserts, replaces or removes one timeline track (`track == nil` removes).
public struct TrackEdit: Codable, Hashable, Sendable {
    public var id: TrackID
    public var track: Track?
    /// Position in the track list for inserts (append when `nil`); inverses use it to restore order.
    public var index: Int?

    public init(id: TrackID, track: Track?, index: Int? = nil) {
        self.id = id
        self.track = track
        self.index = index
    }

    public init(_ track: Track) {
        self.init(id: track.id, track: track)
    }
}

public enum LookScope: String, Codable, Sendable {
    /// The project look (shared by every scene without its own look).
    case project
    /// This scene's own look (`nil` look = inherit the project's).
    case scene
}

/// Every mutation of a document. The UI, gestures, drawing, the library, scripts
/// and (later) the AI all speak this one language. Commands are values: they encode
/// to JSON (Scene Scripts) and applying one returns its exact inverse.
public indirect enum EditCommand: Hashable, Sendable {
    /// Insert a fragment under `parent` (roots when `nil`) at `index` (append when `nil`).
    case insert(SceneFragment, parent: ObjectID?, index: Int?)
    /// Delete objects and their descendants.
    case delete([ObjectID])
    /// Put deleted subtrees back exactly where they were (inverse of delete).
    case restore([RestoreEntry])
    /// Set or remove typed properties.
    case setProperties([PropertyChange])
    case rename(ObjectID, String)
    /// Change what an object is (e.g. swap a blockout cube for a library asset).
    case setKind(ObjectID, ObjectKind)
    case reparent([ReparentEntry])
    case setLook(Look?, scope: LookScope)
    case renameScene(String)
    case setActiveCamera(ObjectID?)
    case setTimeline(Timeline)
    /// Fine-grained key editing (the common case: keying, Perform takes, presets).
    case setTracks([TrackEdit])
    /// Replace an object's Shadow Brush painting (empty removes it).
    case setShadowPaint(ObjectID, [ShadowDab])
    /// Replace the project's own Looks ("My Look").
    case setCustomLooks([LookPreset])
    /// Insert, replace or remove flipbook tracks.
    case setFlipbooks([FlipbookEdit])
    /// Replace the whole scene with another state of it (restoring a version; the scene keeps its id).
    case replaceScene(Scene)
    /// Several commands as one undo step.
    case batch(String, [EditCommand])

    /// Human-readable name for the undo/redo menu.
    public var label: String {
        switch self {
        case let .insert(fragment, _, _):
            if fragment.roots.count == 1, let name = fragment.objects.first(where: { $0.id == fragment.roots[0] })?.name {
                return "Add \(name)"
            }
            return "Add \(fragment.roots.count) objects"
        case let .delete(ids): return ids.count == 1 ? "Delete" : "Delete \(ids.count) objects"
        case .restore: return "Restore"
        case let .setProperties(changes):
            let keys = Set(changes.map(\.key))
            if keys.isSubset(of: [.position, .rotation, .scale]) { return "Transform" }
            if keys.count == 1, let key = keys.first { return "Change \(key.spec?.label ?? key.rawValue)" }
            return "Change properties"
        case .rename: return "Rename"
        case .setKind: return "Swap"
        case .reparent: return "Move in hierarchy"
        case .setLook: return "Change look"
        case .renameScene: return "Rename scene"
        case .setActiveCamera: return "Set camera"
        case .setTimeline: return "Edit timeline"
        case let .setTracks(edits):
            if edits.allSatisfy({ $0.track == nil }) { return "Delete keys" }
            return "Animate"
        case .setShadowPaint: return "Paint shadows"
        case .setCustomLooks: return "Edit looks"
        case let .setFlipbooks(edits): return edits.allSatisfy { $0.track == nil } ? "Delete flipbook" : "Draw"
        case .replaceScene: return "Restore version"
        case let .batch(label, _): return label
        }
    }
}

/// What changed, so the renderer can update only those entities (diff-based sync).
public struct ChangeSet: Hashable, Sendable {
    /// Objects added, removed or modified.
    public var objects: Set<ObjectID>
    /// Parent/child relationships or root order changed.
    public var hierarchy: Bool
    /// Look (lighting, palette, sky, fog, ground, shading) changed.
    public var look: Bool
    /// Scene-level metadata (name, camera, timeline).
    public var scene: Bool

    public init(objects: Set<ObjectID> = [], hierarchy: Bool = false, look: Bool = false, scene: Bool = false) {
        self.objects = objects
        self.hierarchy = hierarchy
        self.look = look
        self.scene = scene
    }

    public static let none = ChangeSet()

    /// Everything (after load, undo across many objects, etc.).
    public static func everything(in document: Document) -> ChangeSet {
        ChangeSet(objects: Set(document.scene.objects.keys), hierarchy: true, look: true, scene: true)
    }

    public var isEmpty: Bool { objects.isEmpty && !hierarchy && !look && !scene }

    public mutating func formUnion(_ other: ChangeSet) {
        objects.formUnion(other.objects)
        hierarchy = hierarchy || other.hierarchy
        look = look || other.look
        scene = scene || other.scene
    }
}

public enum CommandError: Error, Equatable, CustomStringConvertible {
    case objectNotFound(ObjectID)
    case duplicateObject(ObjectID)
    case typeMismatch(key: PropertyKey, expected: PropertyType, got: PropertyType)
    case cycle(ObjectID)
    case empty

    public var description: String {
        switch self {
        case let .objectNotFound(id): "Object \(id) does not exist"
        case let .duplicateObject(id): "Object \(id) already exists"
        case let .typeMismatch(key, expected, got): "\(key) expects \(expected.rawValue), got \(got.rawValue)"
        case let .cycle(id): "Moving \(id) there would put it inside itself"
        case .empty: "Nothing to do"
        }
    }
}
