import Foundation

/// JSON form of commands: `{"op": "<name>", ...fields}`. This is the Scene Script
/// vocabulary (see `/schemas/scene-script.schema.json`).
extension EditCommand: Codable {
    private enum Key: String, CodingKey {
        case op, fragment, parent, index, ids, entries, changes, id, name, kind, look, scope, camera, timeline, label, commands, tracks
        case dabs, looks, flipbooks, scene, brushes, paint, tiles
    }

    private enum Op: String, Codable {
        case insert, delete, restore, setProperties, rename, setKind, reparent, setLook, renameScene
        case setActiveCamera, setTimeline, setTracks, batch, setShadowPaint, setCustomLooks, setFlipbooks, replaceScene
        case setBrushes, setPaint, paintTiles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let op = try c.decode(Op.self, forKey: .op)
        switch op {
        case .insert:
            self = try .insert(
                c.decode(SceneFragment.self, forKey: .fragment),
                parent: c.decodeIfPresent(ObjectID.self, forKey: .parent),
                index: c.decodeIfPresent(Int.self, forKey: .index)
            )
        case .delete:
            self = try .delete(c.decode([ObjectID].self, forKey: .ids))
        case .restore:
            self = try .restore(c.decode([RestoreEntry].self, forKey: .entries))
        case .setProperties:
            self = try .setProperties(c.decode([PropertyChange].self, forKey: .changes))
        case .rename:
            self = try .rename(c.decode(ObjectID.self, forKey: .id), c.decode(String.self, forKey: .name))
        case .setKind:
            self = try .setKind(c.decode(ObjectID.self, forKey: .id), c.decode(ObjectKind.self, forKey: .kind))
        case .reparent:
            self = try .reparent(c.decode([ReparentEntry].self, forKey: .entries))
        case .setLook:
            self = try .setLook(c.decodeIfPresent(Look.self, forKey: .look), scope: c.decode(LookScope.self, forKey: .scope))
        case .renameScene:
            self = try .renameScene(c.decode(String.self, forKey: .name))
        case .setActiveCamera:
            self = try .setActiveCamera(c.decodeIfPresent(ObjectID.self, forKey: .camera))
        case .setTimeline:
            self = try .setTimeline(c.decode(Timeline.self, forKey: .timeline))
        case .setTracks:
            self = try .setTracks(c.decode([TrackEdit].self, forKey: .tracks))
        case .batch:
            self = try .batch(c.decode(String.self, forKey: .label), c.decode([EditCommand].self, forKey: .commands))
        case .setShadowPaint, .setCustomLooks, .setFlipbooks, .replaceScene, .setBrushes:
            self = try Self.decodeWholeValue(op, from: c)
        case .setPaint:
            self = try .setPaint(c.decode(ObjectID.self, forKey: .id), c.decodeIfPresent(ObjectPaint.self, forKey: .paint))
        case .paintTiles:
            self = try .paintTiles(c.decode(ObjectID.self, forKey: .id), c.decode([PaintTileChange].self, forKey: .tiles))
        }
    }

    /// The commands that replace one whole value (a painting, the project's Looks, flipbooks, the scene).
    private static func decodeWholeValue(_ op: Op, from c: KeyedDecodingContainer<Key>) throws -> EditCommand {
        switch op {
        case .setShadowPaint:
            try .setShadowPaint(c.decode(ObjectID.self, forKey: .id), c.decodeIfPresent([ShadowDab].self, forKey: .dabs) ?? [])
        case .setCustomLooks:
            try .setCustomLooks(c.decodeIfPresent([LookPreset].self, forKey: .looks) ?? [])
        case .setFlipbooks:
            try .setFlipbooks(c.decode([FlipbookEdit].self, forKey: .flipbooks))
        case .setBrushes:
            try .setBrushes(c.decodeIfPresent([String: Brush].self, forKey: .brushes) ?? [:])
        default:
            try .replaceScene(c.decode(Scene.self, forKey: .scene))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .insert(fragment, parent, index):
            try c.encode(Op.insert, forKey: .op)
            try c.encode(fragment, forKey: .fragment)
            try c.encodeIfPresent(parent, forKey: .parent)
            try c.encodeIfPresent(index, forKey: .index)
        case let .delete(ids):
            try c.encode(Op.delete, forKey: .op)
            try c.encode(ids, forKey: .ids)
        case let .restore(entries):
            try c.encode(Op.restore, forKey: .op)
            try c.encode(entries, forKey: .entries)
        case let .setProperties(changes):
            try c.encode(Op.setProperties, forKey: .op)
            try c.encode(changes, forKey: .changes)
        case let .rename(id, name):
            try c.encode(Op.rename, forKey: .op)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
        case let .setKind(id, kind):
            try c.encode(Op.setKind, forKey: .op)
            try c.encode(id, forKey: .id)
            try c.encode(kind, forKey: .kind)
        case let .reparent(entries):
            try c.encode(Op.reparent, forKey: .op)
            try c.encode(entries, forKey: .entries)
        case let .setLook(look, scope):
            try c.encode(Op.setLook, forKey: .op)
            try c.encodeIfPresent(look, forKey: .look)
            try c.encode(scope, forKey: .scope)
        case let .renameScene(name):
            try c.encode(Op.renameScene, forKey: .op)
            try c.encode(name, forKey: .name)
        case let .setActiveCamera(camera):
            try c.encode(Op.setActiveCamera, forKey: .op)
            try c.encodeIfPresent(camera, forKey: .camera)
        case let .setTimeline(timeline):
            try c.encode(Op.setTimeline, forKey: .op)
            try c.encode(timeline, forKey: .timeline)
        case let .setTracks(edits):
            try c.encode(Op.setTracks, forKey: .op)
            try c.encode(edits, forKey: .tracks)
        case let .batch(label, commands):
            try c.encode(Op.batch, forKey: .op)
            try c.encode(label, forKey: .label)
            try c.encode(commands, forKey: .commands)
        case .setShadowPaint, .setCustomLooks, .setFlipbooks, .replaceScene, .setBrushes:
            try encodeWholeValue(into: &c)
        case let .setPaint(id, paint):
            try c.encode(Op.setPaint, forKey: .op)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(paint, forKey: .paint)
        case let .paintTiles(id, changes):
            try c.encode(Op.paintTiles, forKey: .op)
            try c.encode(id, forKey: .id)
            try c.encode(changes, forKey: .tiles)
        }
    }

    private func encodeWholeValue(into c: inout KeyedEncodingContainer<Key>) throws {
        switch self {
        case let .setShadowPaint(id, dabs):
            try c.encode(Op.setShadowPaint, forKey: .op)
            try c.encode(id, forKey: .id)
            try c.encode(dabs, forKey: .dabs)
        case let .setCustomLooks(looks):
            try c.encode(Op.setCustomLooks, forKey: .op)
            try c.encode(looks, forKey: .looks)
        case let .setFlipbooks(edits):
            try c.encode(Op.setFlipbooks, forKey: .op)
            try c.encode(edits, forKey: .flipbooks)
        case let .setBrushes(brushes):
            try c.encode(Op.setBrushes, forKey: .op)
            try c.encode(brushes, forKey: .brushes)
        case let .replaceScene(scene):
            try c.encode(Op.replaceScene, forKey: .op)
            try c.encode(scene, forKey: .scene)
        default:
            break
        }
    }
}

/// A Scene Script: a named list of commands and/or friendly actions (v2), applied as one undoable step.
/// Commands are the raw vocabulary; actions are compiled by `ScriptCompiler` (names, spoken words, presets…).
public struct SceneScript: Codable, Hashable, Sendable {
    public static let currentVersion = 3

    public var version: Int
    public var title: String
    public var commands: [EditCommand]
    /// v2 actions (`{"do": "add", …}`) — see `ScriptCompiler`.
    public var actions: [JSONValue]

    public init(title: String, commands: [EditCommand] = [], actions: [JSONValue] = [], version: Int = SceneScript.currentVersion) {
        self.version = version
        self.title = title
        self.commands = commands
        self.actions = actions
    }

    /// The single command that applies the raw commands (one undo step). Scripts with actions go through `ScriptCompiler`.
    public var asCommand: EditCommand { .batch(title, commands) }

    private enum CodingKeys: String, CodingKey {
        case version, title, commands, actions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Script"
        commands = try c.decodeIfPresent([EditCommand].self, forKey: .commands) ?? []
        actions = try c.decodeIfPresent([JSONValue].self, forKey: .actions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(title, forKey: .title)
        if !commands.isEmpty || actions.isEmpty { try c.encode(commands, forKey: .commands) }
        if !actions.isEmpty { try c.encode(actions, forKey: .actions) }
    }
}
