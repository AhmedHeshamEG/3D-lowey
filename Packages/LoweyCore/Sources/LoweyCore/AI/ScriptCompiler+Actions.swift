import Foundation

// MARK: - Actions

extension ScriptState {
    typealias Handler = @Sendable (inout ScriptState, JSONValue) throws -> Void

    /// Every verb (and its aliases) → what it does.
    static let handlers: [String: Handler] = [
        "add": { try $0.add($1) },
        "place": { try $0.place($1) },
        "text": { try $0.text($1) },
        "overlay": { try $0.overlay($1) },
        "particles": { try $0.particles($1) },
        "character": { try $0.character($1) },
        "blob": { try $0.blob($1) },
        "person": { try $0.blob($1) },
        "expression": { try $0.expression($1) },
        "light": { try $0.light($1) },
        "camera": { try $0.camera($1) },
        "set": { try $0.set($1) },
        "transform": { try $0.transform($1) },
        "key": { try $0.keys($1) },
        "keys": { try $0.keys($1) },
        "preset": { try $0.preset($1) },
        "animate": { try $0.preset($1) },
        "cameraMove": { try $0.cameraMove($1) },
        "move": { try $0.cameraMove($1) },
        "cut": { try $0.cut($1) },
        "look": { try $0.look($1) },
        "effect": { try $0.effect($1) },
        "clip": { try $0.clip($1) },
        "lipSync": { try $0.lipSync($1) },
        "marker": { try $0.marker($1) },
        "captions": { try $0.captions($1) },
        "delete": { try $0.delete($1) },
        "rename": { try $0.rename($1) },
        "group": { try $0.group($1) },
        "array": { try $0.array($1) },
        "scatter": { try $0.scatter($1) },
        "length": { try $0.length($1) },
        "duration": { try $0.length($1) },
        "command": { try $0.rawCommand($1) }
    ]

    mutating func perform(_ action: JSONValue) throws {
        guard let verb = string(action, "do") ?? string(action, "action") else { throw fail("each action needs “do”") }
        guard let handler = Self.handlers[verb] else { throw fail("unknown action “\(verb)”") }
        try handler(&self, action)
    }

    mutating func expression(_ action: JSONValue) throws {
        let character = try target(action["character"] ?? action["target"])
        let name = string(action, "name") ?? string(action, "expression") ?? ""
        guard let expression = FaceExpression(rawValue: name) else {
            throw fail("unknown expression “\(name)” (\(FaceExpression.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let at = try time(action["at"])
        try run(.setTimeline(expression.keyed(on: character, at: at, in: timeline, ids: &context.ids)),
                label: "\(expression.title) at \(format(at))")
    }

    mutating func marker(_ action: JSONValue) throws {
        let at = try time(action["at"])
        let label = string(action, "name") ?? "Marker"
        var copy = timeline
        copy.markers.append(Marker(id: context.ids.next(ObjectID.self).raw, time: at, name: label))
        try run(.setTimeline(copy), label: "Marker “\(label)” at \(format(at))")
    }

    mutating func captions(_ action: JSONValue) throws {
        var copy = timeline
        var settings = copy.captions ?? CaptionSettings()
        settings.enabled = bool(action, "enabled") ?? true
        if let style = string(action, "style").flatMap(CaptionSettings.Style.init(rawValue:)) { settings.style = style }
        if let position = string(action, "position").flatMap(CaptionSettings.Position.init(rawValue:)) { settings.position = position }
        copy.captions = settings
        try run(.setTimeline(copy), label: "Captions \(settings.enabled ? "on" : "off")")
    }

    mutating func delete(_ action: JSONValue) throws {
        let ids = try targets(action["target"])
        try run(operations.delete(ids, in: scene), label: "Delete \(ids.count) object\(ids.count == 1 ? "" : "s")")
    }

    mutating func rename(_ action: JSONValue) throws {
        let id = try target(action["target"])
        guard let new = string(action, "name") else { throw fail("rename needs “name”") }
        try run(.rename(id, new), label: "Rename to “\(new)”")
        created[new] = id
    }

    mutating func group(_ action: JSONValue) throws {
        let ids = try targets(action["target"])
        let groupName = string(action, "name") ?? "Group"
        guard let (command, group) = withOperations({ $0.group(ids, in: $1, name: groupName) }) else { throw fail("nothing to group") }
        try run(command, label: "Group \(ids.count) objects")
        remember(action, group, name: groupName)
    }

    mutating func array(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let count = Int(number(action, "count") ?? 5)
        let layout: ArrayLayout = if let radius = number(action, "radius") {
            .circle(count: count, radius: radius, faceCenter: bool(action, "faceCenter") ?? true)
        } else {
            .line(count: count, step: vec3(action["step"]) ?? Vec3(1.5, 0, 0))
        }
        guard let (command, group) = withOperations({ $0.array(id, layout: layout, in: $1) }) else { throw fail("can't array that") }
        try run(command, label: "Array of \(count)")
        try nameGroup(group, action, fallback: "Array")
    }

    mutating func scatter(_ action: JSONValue) throws {
        let id = try target(action["target"])
        var settings = ScatterSettings(count: Int(number(action, "count") ?? 20), radius: number(action, "radius") ?? 5)
        settings.seed = UInt64(number(action, "seed") ?? 1)
        let center = try point(action["at"]) ?? context.focus
        guard let (command, group) = withOperations({ $0.scatter(id, center: center, settings: settings, in: $1) })
        else { throw fail("can't scatter that") }
        try run(command, label: "Scatter \(settings.count)")
        try nameGroup(group, action, fallback: "Scatter")
    }

    mutating func length(_ action: JSONValue) throws {
        var copy = timeline
        if let seconds = number(action, "seconds") ?? number(action, "value") { copy.duration = max(seconds, 1) }
        if let fps = number(action, "fps"), Timeline.frameRates.contains(Int(fps)) { copy.fps = Int(fps) }
        try run(.setTimeline(copy), label: "Timeline \(format(copy.duration)) at \(copy.fps) fps")
    }

    mutating func rawCommand(_ action: JSONValue) throws {
        guard let raw = action["command"] else { throw fail("“command” needs a command") }
        let command = try LoweyJSON.decode(EditCommand.self, from: LoweyJSON.encode(raw))
        try run(command, label: command.label)
    }
}
