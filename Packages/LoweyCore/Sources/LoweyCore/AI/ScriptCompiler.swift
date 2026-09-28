import Foundation

/// Scene Script v2 "actions": an AI-friendly (and hand-writable) language on top of the command system.
/// Objects are named, not id'd; times can be seconds, a spoken word or a marker; everything compiles to ordinary
/// `EditCommand`s against the current document and applies as ONE undo step. See `/schemas/scene-script.schema.json`.
///
///     {"do": "add", "shape": "cube", "name": "Paper", "at": [0, 0.8, 0], "size": [0.3, 0.01, 0.4], "color": "palette:0"}
///     {"do": "preset", "target": "Screen*", "preset": "popIn", "at": {"word": "Nobody"}, "stagger": 0.08}
///     {"do": "cameraMove", "move": "pushIn", "subject": "Paper", "at": {"word": "message"}, "duration": 2}
public struct ScriptContext: Sendable {
    public var library: LibraryManifest
    /// The playhead ("now").
    public var now: Double
    /// Where new things go when no position is given (the middle of the view).
    public var focus: Vec3
    public var ids: IDFactory

    public init(library: LibraryManifest = LibraryManifest(), now: Double = 0, focus: Vec3 = .zero, ids: IDFactory = .random) {
        self.library = library
        self.now = now
        self.focus = focus
        self.ids = ids
    }
}

public struct ScriptResult: Sendable {
    /// Everything as one command (nil when the script changes nothing).
    public var command: EditCommand?
    /// One human-readable line per action.
    public var report: [String]
    /// Names given in the script → the objects they became.
    public var created: [String: ObjectID]
    /// The document after the script (for previews).
    public var document: Document
}

public struct ScriptError: Error, Equatable, CustomStringConvertible {
    /// 0-based action index.
    public var action: Int
    public var message: String

    public var description: String { "Action \(action + 1): \(message)" }
}

public enum ScriptCompiler {
    public static func compile(_ script: SceneScript, document: Document, context: ScriptContext) throws -> ScriptResult {
        var state = State(document: document, context: context)
        for (index, command) in script.commands.enumerated() {
            do {
                try state.run(command, label: nil)
            } catch {
                throw ScriptError(action: index, message: "command failed: \(error)")
            }
        }
        for (index, action) in script.actions.enumerated() {
            do {
                try state.perform(action)
            } catch let error as ScriptError {
                throw ScriptError(action: index + script.commands.count, message: error.message)
            } catch {
                throw ScriptError(action: index + script.commands.count, message: String(describing: error))
            }
        }
        let command: EditCommand? = state.commands.isEmpty ? nil : .batch(script.title, state.commands)
        return ScriptResult(command: command, report: state.report, created: state.created, document: state.document)
    }

    /// Compiles and describes the change without applying it (the AI proposes, you decide).
    public static func preview(_ script: SceneScript, document: Document, context: ScriptContext) throws -> ScriptPreview {
        let result = try compile(script, document: document, context: context)
        return ScriptPreview(before: document, after: result.document, report: result.report)
    }
}

/// What a script would change, in plain words.
public struct ScriptPreview: Sendable {
    public var added: [String]
    public var removed: [String]
    public var changed: [String]
    public var keyedTracks: Int
    public var timelineChanges: [String]
    public var lookChanged: Bool
    public var report: [String]

    public init(before: Document, after: Document, report: [String]) {
        let old = before.scene.objects
        let new = after.scene.objects
        added = new.keys.filter { old[$0] == nil }.compactMap { new[$0]?.name }.sorted()
        removed = old.keys.filter { new[$0] == nil }.compactMap { old[$0]?.name }.sorted()
        changed = new.keys.filter { old[$0] != nil && old[$0] != new[$0] }.compactMap { new[$0]?.name }.sorted()
        let oldTracks = Dictionary(before.scene.timeline.tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        keyedTracks = after.scene.timeline.tracks.filter { oldTracks[$0.id] != $0 }.count
        var timeline: [String] = []
        let a = before.scene.timeline
        let b = after.scene.timeline
        if a.cuts != b.cuts { timeline.append("camera cuts: \(a.cuts.count) → \(b.cuts.count)") }
        if a.effects != b.effects { timeline.append("screen effects: \(a.effects.count) → \(b.effects.count)") }
        if a.markers != b.markers { timeline.append("markers: \(a.markers.count) → \(b.markers.count)") }
        if a.clipTracks != b.clipTracks { timeline.append("character clips changed") }
        if a.captions != b.captions { timeline.append("captions changed") }
        if a.duration != b.duration { timeline.append("length \(a.duration) s → \(b.duration) s") }
        timelineChanges = timeline
        lookChanged = before.effectiveLook != after.effectiveLook
        self.report = report
    }

    public var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && changed.isEmpty && keyedTracks == 0 && timelineChanges.isEmpty && !lookChanged
    }

    public var lines: [String] {
        var lines: [String] = []
        if !added.isEmpty { lines.append("Adds \(added.count): \(added.prefix(8).joined(separator: ", "))\(added.count > 8 ? "…" : "")") }
        if !removed.isEmpty { lines.append("Removes \(removed.count): \(removed.prefix(8).joined(separator: ", "))") }
        if !changed.isEmpty { lines.append("Changes \(changed.count): \(changed.prefix(8).joined(separator: ", "))\(changed.count > 8 ? "…" : "")") }
        if keyedTracks > 0 { lines.append("Animates \(keyedTracks) propert\(keyedTracks == 1 ? "y" : "ies")") }
        lines += timelineChanges.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        if lookChanged { lines.append("Changes the look") }
        return lines
    }
}

// MARK: - Scene Script v2

public extension SceneScript {
    /// Version with `actions` (v1 scripts only had raw commands; both still load).
    static let actionsVersion = 2
}

// MARK: - Compiler state

private struct State {
    var document: Document
    var context: ScriptContext
    var commands: [EditCommand] = []
    var report: [String] = []
    var created: [String: ObjectID] = [:]
    var operations: Operations

    init(document: Document, context: ScriptContext) {
        self.document = document
        self.context = context
        operations = Operations(ids: context.ids, library: context.library)
    }

    var scene: Scene { document.scene }
    var timeline: Timeline { document.scene.timeline }

    mutating func run(_ command: EditCommand?, label: String?) throws {
        guard let command else { return }
        var working = document
        _ = try command.apply(to: &working)
        document = working
        commands.append(command)
        if let label { report.append(label) }
    }

    func fail(_ message: String) -> ScriptError { ScriptError(action: 0, message: message) }

    // MARK: Values

    func string(_ action: JSONValue, _ key: String) -> String? { action[key]?.stringValue }
    func number(_ action: JSONValue, _ key: String) -> Double? { action[key]?.numberValue }
    func bool(_ action: JSONValue, _ key: String) -> Bool? {
        if case let .bool(value)? = action[key] { return value }
        return nil
    }

    func vec3(_ value: JSONValue?) -> Vec3? {
        if let number = value?.numberValue { return Vec3(number, number, number) }
        guard let array = value?.arrayValue?.compactMap(\.numberValue) else { return nil }
        switch array.count {
        case 3: return Vec3(array[0], array[1], array[2])
        case 2: return Vec3(array[0], array[1], 0)
        default: return nil
        }
    }

    func color(_ value: JSONValue?) throws -> ColorValue? {
        guard let text = value?.stringValue else { return nil }
        if text.hasPrefix("palette:"), let slot = Int(text.dropFirst(8)) { return .palette(slot) }
        guard let rgba = RGBA(hex: text) else { throw fail("“\(text)” isn't a colour (use #RRGGBB or palette:N)") }
        return .rgba(rgba)
    }

    /// Seconds from a number, "now", "start", "end", {"word": …}, {"marker": …}.
    func time(_ value: JSONValue?, default fallback: Double? = nil) throws -> Double {
        guard let value else {
            if let fallback { return fallback }
            return context.now
        }
        if let number = value.numberValue { return max(number, 0) }
        if let text = value.stringValue {
            switch text {
            case "now", "playhead": return context.now
            case "start": return 0
            case "end": return timeline.duration
            default:
                if let number = Double(text) { return number }
                return try wordTime(text, occurrence: 1, edge: "start")
            }
        }
        if let word = value["word"]?.stringValue {
            let occurrence = Int(value["occurrence"]?.numberValue ?? 1)
            let edge = value["edge"]?.stringValue ?? "start"
            return try wordTime(word, occurrence: occurrence, edge: edge) + (value["offset"]?.numberValue ?? 0)
        }
        if let name = value["marker"]?.stringValue {
            guard let marker = timeline.markers.first(where: { $0.name.lowercased() == name.lowercased() }) else {
                throw fail("no marker called “\(name)”")
            }
            return marker.time + (value["offset"]?.numberValue ?? 0)
        }
        throw fail("can't read a time from \(value)")
    }

    func wordTime(_ phrase: String, occurrence: Int, edge: String) throws -> Double {
        let words = timeline.words
        guard !words.isEmpty else { throw fail("no transcript yet — transcribe the voiceover, or use seconds") }
        let matches = WordSnap.find(phrase, in: words)
        guard !matches.isEmpty else {
            throw fail("“\(phrase)” isn't in the transcript (heard: \(words.prefix(12).map(\.text).joined(separator: " "))…)")
        }
        let match = matches[min(max(occurrence, 1), matches.count) - 1]
        return edge == "end" ? words[match.upperBound].end : words[match.lowerBound].start
    }

    /// Objects named by a target: a name (case-insensitive), "Name*" (prefix), an id, or a list of those.
    func targets(_ value: JSONValue?) throws -> [ObjectID] {
        guard let value else { throw fail("missing “target”") }
        if let list = value.arrayValue { return try list.flatMap { try targets($0) } }
        guard let text = value.stringValue else { throw fail("a target is a name or a list of names") }
        if let id = created[text] { return [id] }
        if scene.objects[ObjectID(raw: text)] != nil { return [ObjectID(raw: text)] }
        let ordered = scene.orderedIDs()
        if text.hasSuffix("*") {
            let prefix = text.dropLast().lowercased()
            let found = ordered.filter { scene.objects[$0]?.name.lowercased().hasPrefix(prefix) == true }
            guard !found.isEmpty else { throw fail("nothing is named like “\(text)”") }
            return found
        }
        if let match = ordered.first(where: { scene.objects[$0]?.name.lowercased() == text.lowercased() }) { return [match] }
        let names = ordered.prefix(40).compactMap { scene.objects[$0]?.name }
        throw fail("no object called “\(text)” (there are: \(names.joined(separator: ", ")))")
    }

    func target(_ value: JSONValue?) throws -> ObjectID {
        guard let first = try targets(value).first else { throw fail("missing “target”") }
        return first
    }

    /// A point: coordinates, or where an object is.
    func point(_ value: JSONValue?) throws -> Vec3? {
        guard let value else { return nil }
        if let vector = vec3(value) { return vector }
        let id = try target(value)
        return SceneBounds(library: context.library).worldBounds(of: id, in: scene)?.center ?? scene.worldTransform(of: id).position
    }

    func rotation(_ value: JSONValue?) -> Quat? {
        vec3(value).map { Quat(eulerDegrees: $0) }
    }

    /// A property value from friendly JSON (a number, [x,y,z], "#hex", true) or the typed form ({"float": 1}).
    func propertyValue(_ key: PropertyKey, _ value: JSONValue?) throws -> PropertyValue {
        guard let value else { throw fail("missing “value”") }
        if case let .object(dictionary) = value, dictionary.count == 1,
           let decoded = try? LoweyJSON.decode(PropertyValue.self, from: LoweyJSON.encode(value)) {
            return decoded
        }
        let type = key.spec?.type
        switch type {
        case .vec3?:
            guard let vector = vec3(value) else { throw fail("\(key) needs [x, y, z]") }
            return .vec3(vector)
        case .quat?:
            guard let angles = vec3(value) else { throw fail("\(key) needs [x°, y°, z°]") }
            return .quat(Quat(eulerDegrees: angles))
        case .color?:
            guard let color = try color(value) else { throw fail("\(key) needs a colour") }
            return .color(color)
        case .bool?:
            if case let .bool(flag) = value { return .bool(flag) }
            throw fail("\(key) needs true or false")
        case .enumeration?:
            guard let text = value.stringValue else { throw fail("\(key) needs a word") }
            return .enumeration(text)
        case .int?:
            guard let number = value.numberValue else { throw fail("\(key) needs a number") }
            return .int(Int(number))
        default:
            if let number = value.numberValue { return .float(number) }
            if let text = value.stringValue { return .string(text) }
            if case let .bool(flag) = value { return .bool(flag) }
            if let vector = vec3(value) { return .vec3(vector) }
            throw fail("can't use \(value) for \(key)")
        }
    }

    func easing(_ value: JSONValue?) -> Easing {
        guard let value else { return .easeInOut }
        if let easing = try? LoweyJSON.decode(Easing.self, from: LoweyJSON.encode(value)) { return easing }
        return .easeInOut
    }

    mutating func name(_ action: JSONValue, fallback: String) -> String {
        ObjectFactory.uniqueName(string(action, "name") ?? fallback, in: scene)
    }

    mutating func remember(_ action: JSONValue, _ id: ObjectID, name: String) {
        created[string(action, "name") ?? name] = id
        created[name] = id
    }

    // MARK: Actions

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func perform(_ action: JSONValue) throws {
        guard let verb = string(action, "do") ?? string(action, "action") else { throw fail("each action needs “do”") }
        switch verb {
        case "add":
            try add(action)
        case "place":
            try place(action)
        case "text":
            try text(action)
        case "overlay":
            try overlay(action)
        case "particles":
            try particles(action)
        case "character":
            try character(action)
        case "light":
            try light(action)
        case "camera":
            try camera(action)
        case "set":
            try set(action)
        case "transform":
            try transform(action)
        case "key", "keys":
            try keys(action)
        case "preset", "animate":
            try preset(action)
        case "cameraMove", "move":
            try cameraMove(action)
        case "cut":
            try cut(action)
        case "look":
            try look(action)
        case "effect":
            try effect(action)
        case "clip":
            try clip(action)
        case "lipSync":
            try lipSync(action)
        case "marker":
            let at = try time(action["at"])
            let label = string(action, "name") ?? "Marker"
            var copy = timeline
            copy.markers.append(Marker(id: context.ids.next(ObjectID.self).raw, time: at, name: label))
            try run(.setTimeline(copy), label: "Marker “\(label)” at \(format(at))")
        case "captions":
            var copy = timeline
            var settings = copy.captions ?? CaptionSettings()
            settings.enabled = bool(action, "enabled") ?? true
            if let style = string(action, "style").flatMap(CaptionSettings.Style.init(rawValue:)) { settings.style = style }
            if let position = string(action, "position").flatMap(CaptionSettings.Position.init(rawValue:)) { settings.position = position }
            copy.captions = settings
            try run(.setTimeline(copy), label: "Captions \(settings.enabled ? "on" : "off")")
        case "delete":
            let ids = try targets(action["target"])
            try run(operations.delete(ids, in: scene), label: "Delete \(ids.count) object\(ids.count == 1 ? "" : "s")")
        case "rename":
            let id = try target(action["target"])
            guard let new = string(action, "name") else { throw fail("rename needs “name”") }
            try run(.rename(id, new), label: "Rename to “\(new)”")
            created[new] = id
        case "group":
            let ids = try targets(action["target"])
            guard let (command, group) = operations.group(ids, in: scene, name: string(action, "name") ?? "Group") else { throw fail("nothing to group") }
            try run(command, label: "Group \(ids.count) objects")
            remember(action, group, name: string(action, "name") ?? "Group")
        case "array":
            let id = try target(action["target"])
            let count = Int(number(action, "count") ?? 5)
            let layout: ArrayLayout = if let radius = number(action, "radius") {
                .circle(count: count, radius: radius, faceCenter: bool(action, "faceCenter") ?? true)
            } else {
                .line(count: count, step: vec3(action["step"]) ?? Vec3(1.5, 0, 0))
            }
            guard let (command, group) = operations.array(id, layout: layout, in: scene) else { throw fail("can't array that") }
            try run(command, label: "Array of \(count)")
            remember(action, group, name: string(action, "name") ?? "Array")
        case "scatter":
            let id = try target(action["target"])
            var settings = ScatterSettings(count: Int(number(action, "count") ?? 20), radius: number(action, "radius") ?? 5)
            settings.seed = UInt64(number(action, "seed") ?? 1)
            let center = try point(action["at"]) ?? context.focus
            guard let (command, group) = operations.scatter(id, center: center, settings: settings, in: scene) else { throw fail("can't scatter that") }
            try run(command, label: "Scatter \(settings.count)")
            remember(action, group, name: string(action, "name") ?? "Scatter")
        case "length", "duration":
            var copy = timeline
            if let seconds = number(action, "seconds") ?? number(action, "value") { copy.duration = max(seconds, 1) }
            if let fps = number(action, "fps"), Timeline.frameRates.contains(Int(fps)) { copy.fps = Int(fps) }
            try run(.setTimeline(copy), label: "Timeline \(format(copy.duration)) at \(copy.fps) fps")
        case "command":
            guard let raw = action["command"] else { throw fail("“command” needs a command") }
            let command = try LoweyJSON.decode(EditCommand.self, from: LoweyJSON.encode(raw))
            try run(command, label: command.label)
        default:
            throw fail("unknown action “\(verb)”")
        }
    }

    func format(_ seconds: Double) -> String { String(format: "%.2f s", seconds) }

    mutating func insert(_ object: SceneObject, action: JSONValue, verb: String) throws {
        var object = object
        let parent = try action["parent"].map { try target($0) }
        if let rotation = rotation(action["rotation"]) { object.transform.rotation = rotation }
        if let color = try color(action["color"]) { object[.color] = .color(color) }
        if let glow = number(action, "glow") {
            object[.emissiveIntensity] = .float(glow)
            if object[.emissive] == nil, let color = object[.color] { object[.emissive] = color }
        }
        try run(operations.add(object, parent: parent), label: "\(verb) “\(object.name)”")
        remember(action, object.id, name: object.name)
    }

    mutating func add(_ action: JSONValue) throws {
        let shapeName = string(action, "shape") ?? "cube"
        var object: SceneObject
        if shapeName == "group" {
            object = SceneObject(id: context.ids.next(), name: name(action, fallback: "Group"), kind: .group)
        } else {
            guard let shape = PrimitiveShape(rawValue: shapeName) else {
                throw fail("unknown shape “\(shapeName)” (\(PrimitiveShape.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            object = SceneObject(id: context.ids.next(), name: name(action, fallback: shape.displayName), kind: .primitive(shape))
            object[.color] = .color(.rgba(.blockout))
        }
        if let size = vec3(action["size"]) { object.transform.scale = size }
        let at = try point(action["at"]) ?? context.focus
        // Given a height (or told not to), it goes exactly there; otherwise it stands on the ground.
        let exact = bool(action, "onGround") == false || (action["at"].flatMap(vec3) != nil && at.y != 0)
        if exact {
            object.transform.position = at
        } else {
            object = operations.placeOnGround(object, at: at)
        }
        try insert(object, action: action, verb: "Add")
    }

    mutating func place(_ action: JSONValue) throws {
        guard let query = string(action, "asset") ?? string(action, "query") else { throw fail("place needs “asset” (a library search)") }
        let results = LibrarySearch.search(query, in: context.library).filter {
            switch $0 {
            case .asset, .prefab: true
            default: false
            }
        }
        var object: SceneObject
        switch results.first {
        case let .asset(asset)?:
            object = SceneObject(id: context.ids.next(), name: name(action, fallback: asset.name), kind: .asset(asset.id))
        case let .prefab(prefab)?:
            object = SceneObject(id: context.ids.next(), name: name(action, fallback: prefab.name), kind: .prefab(prefab.id))
        default:
            let names = context.library.assets.prefix(30).map(\.name) + context.library.prefabs.prefix(10).map(\.name)
            throw fail("nothing in the library matches “\(query)”. Library: \(names.joined(separator: ", "))")
        }
        if let scale = vec3(action["scale"]) { object.transform.scale = scale }
        object = operations.placeOnGround(object, at: try point(action["at"]) ?? context.focus)
        try insert(object, action: action, verb: "Place")
    }

    mutating func text(_ action: JSONValue) throws {
        guard let words = string(action, "text") else { throw fail("text needs “text”") }
        var recipe = TextRecipe(text: words, style: string(action, "style").flatMap(TextRecipe.Style.init(rawValue:)) ?? .blocky)
        if let size = number(action, "size") { recipe.size = size }
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: "Text"), kind: .text(recipe))
        object[.color] = .color(.palette(0))
        object = operations.placeOnGround(object, at: try point(action["at"]) ?? context.focus)
        try insert(object, action: action, verb: "Add text")
    }

    mutating func overlay(_ action: JSONValue) throws {
        let shapeName = string(action, "shape") ?? "title"
        guard let shape = OverlayRecipe.Shape(rawValue: shapeName) else {
            throw fail("unknown overlay “\(shapeName)” (\(OverlayRecipe.Shape.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        var recipe = OverlayRecipe.default(shape)
        if let words = string(action, "text") { recipe.text = words }
        if let follow = action["follow"] { recipe.anchor = try target(follow) }
        let at = vec3(action["at"]) ?? Vec3(0, shape == .title ? 0.55 : 0, 0)
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: shape.title), kind: .overlay(recipe),
                                 transform: Transform(position: Vec3(at.x, at.y, Double(scene.objects.values.filter(\.kind.isOverlay).count))))
        if let size = number(action, "size") { object.transform.scale = Vec3(size, size, 1) }
        try insert(object, action: action, verb: "Overlay")
    }

    mutating func particles(_ action: JSONValue) throws {
        guard let preset = string(action, "preset").flatMap(ParticleRecipe.Preset.init(rawValue:)) else {
            throw fail("particles need “preset” (\(ParticleRecipe.Preset.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        var recipe = ParticleRecipe.preset(preset, seed: UInt64(number(action, "seed") ?? 1))
        if recipe.burst { recipe.burstTime = try time(action["time"] ?? action["when"]) }
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: preset.title), kind: .particles(recipe))
        object.transform.position = try point(action["at"]) ?? context.focus
        if let amount = number(action, "amount") { object.transform.scale = Vec3(amount, amount, amount) }
        try insert(object, action: action, verb: "Add \(preset.title.lowercased())")
    }

    mutating func character(_ action: JSONValue) throws {
        var recipe = CharacterRecipe()
        if let raw = action["recipe"] { recipe = try LoweyJSON.decode(CharacterRecipe.self, from: LoweyJSON.encode(raw)) }
        if let given = string(action, "name") { recipe.name = given }
        var fragment = CharacterBuilder.build(recipe, ids: &context.ids)
        guard let root = fragment.roots.first, let index = fragment.objects.firstIndex(where: { $0.id == root }) else { return }
        fragment.objects[index].name = ObjectFactory.uniqueName(recipe.name, in: scene)
        fragment.objects[index].transform.position = try point(action["at"]) ?? context.focus
        if let facing = number(action, "facing") { fragment.objects[index].transform.rotation = Quat(angle: facing * .pi / 180, axis: .unitY) }
        try run(.insert(fragment, parent: nil, index: nil), label: "Character “\(fragment.objects[index].name)”")
        remember(action, root, name: fragment.objects[index].name)
    }

    mutating func light(_ action: JSONValue) throws {
        let type: LightType = switch string(action, "type") {
        case "spot": .spot
        case "sun", "directional": .directional
        default: .point
        }
        var factory = ObjectFactory(ids: context.ids)
        var object = factory.light(type, at: try point(action["at"]) ?? context.focus + Vec3(0, 2, 0))
        context.ids = factory.ids
        object.name = name(action, fallback: object.name)
        if let color = try color(action["color"]) { object[.lightColor] = .color(color) }
        if let intensity = number(action, "intensity") { object[.lightIntensity] = .float(intensity) }
        if let range = number(action, "range") { object[.lightRange] = .float(range) }
        try insert(object, action: action, verb: "Light")
    }

    mutating func camera(_ action: JSONValue) throws {
        let from = try point(action["from"] ?? action["at"]) ?? (context.focus + Vec3(0, 1.6, 6))
        let look = try point(action["lookAt"]) ?? context.focus
        let direction = (look - from).normalized
        let yaw = atan2(-direction.x, -direction.z)
        let pitch = asin(max(-1, min(1, direction.y)))
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: "Camera"), kind: .camera,
                                 transform: Transform(position: from, rotation: (Quat(angle: yaw, axis: .unitY) * Quat(angle: pitch, axis: .unitX)).normalized))
        if let focal = number(action, "focalLength") { object[.fieldOfView] = .float(CameraLens.fieldOfView(focalLength: focal)) }
        object[.fieldOfView] = object[.fieldOfView] ?? .float(number(action, "fov") ?? 45)
        object[.focusDistance] = .float(from.distance(to: look))
        if let aperture = number(action, "aperture") { object[.aperture] = .float(aperture) }
        try insert(object, action: action, verb: "Camera")
        if bool(action, "active") ?? (scene.activeCamera == nil) {
            try run(.setActiveCamera(object.id), label: nil)
        }
    }

    mutating func set(_ action: JSONValue) throws {
        guard let keyName = string(action, "property") else { throw fail("set needs “property”") }
        let key = PropertyKey(keyName)
        let value = try propertyValue(key, action["value"])
        let ids = try targets(action["target"])
        if action["at"] != nil {
            let at = try time(action["at"])
            try addKeys(ids, key, [(at, value, easing(action["easing"]))])
        } else {
            try run(.setProperties(ids.map { PropertyChange(object: $0, key: key, value: value) }), label: "Set \(keyName) on \(ids.count) object(s)")
        }
    }

    mutating func transform(_ action: JSONValue) throws {
        let ids = try targets(action["target"])
        var changes: [(ObjectID, PropertyKey, PropertyValue)] = []
        let relative = bool(action, "relative") ?? false
        for id in ids {
            guard let object = scene.objects[id] else { continue }
            if let position = vec3(action["position"]) {
                changes.append((id, .position, .vec3(relative ? object.transform.position + position : position)))
            }
            if let rotation = rotation(action["rotation"]) {
                changes.append((id, .rotation, .quat(relative ? (object.transform.rotation * rotation).normalized : rotation)))
            }
            if let scale = vec3(action["scale"]) {
                let current = object.transform.scale
                changes.append((id, .scale, .vec3(relative ? Vec3(current.x * scale.x, current.y * scale.y, current.z * scale.z) : scale)))
            }
        }
        guard !changes.isEmpty else { throw fail("transform needs position, rotation or scale") }
        if action["at"] != nil {
            let at = try time(action["at"])
            var keys = KeyOperations(ids: context.ids)
            var working = timeline
            var edits: [TrackEdit] = []
            for (id, property, value) in changes {
                let edit = keys.setKey(id, property, value: value, at: at, previous: scene.objects[id]?[property], easing: easing(action["easing"]), in: working)
                if let track = edit.track { working.tracks.removeAll { $0.id == track.id }; working.tracks.append(track) }
                edits.removeAll { $0.id == edit.id }
                edits.append(edit)
            }
            context.ids = keys.ids
            try run(.setTracks(edits), label: "Key transform at \(format(at))")
        } else {
            try run(.setProperties(changes.map { PropertyChange(object: $0.0, key: $0.1, value: $0.2) }), label: "Transform \(ids.count) object(s)")
        }
    }

    mutating func addKeys(_ ids: [ObjectID], _ property: PropertyKey, _ values: [(Double, PropertyValue, Easing)]) throws {
        var keys = KeyOperations(ids: context.ids)
        var edits: [TrackEdit] = []
        for id in ids {
            var track = timeline.track(for: id, property) ?? Track(id: keys.ids.next(), target: id, property: property)
            for (at, value, easing) in values {
                track.setKey(Keyframe(time: at, value: value, easing: easing))
            }
            edits.append(TrackEdit(track))
        }
        context.ids = keys.ids
        try run(.setTracks(edits), label: "\(values.count) key\(values.count == 1 ? "" : "s") on \(property) × \(ids.count)")
    }

    mutating func keys(_ action: JSONValue) throws {
        guard let keyName = string(action, "property") else { throw fail("keys need “property”") }
        let property = PropertyKey(keyName)
        guard let list = action["keys"]?.arrayValue, !list.isEmpty else { throw fail("keys need a “keys” list of {t, value}") }
        let values = try list.map { entry in (try time(entry["t"] ?? entry["at"]), try propertyValue(property, entry["value"]), easing(entry["easing"])) }
        try addKeys(try targets(action["target"]), property, values)
    }

    mutating func preset(_ action: JSONValue) throws {
        guard let preset = string(action, "preset").flatMap(AnimationPreset.init(rawValue:)) else {
            throw fail("unknown preset (\(AnimationPreset.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let ids = try targets(action["target"])
        let at = try time(action["at"])
        var options = PresetOptions(preset)
        if let duration = number(action, "duration") { options.duration = duration }
        if let strength = number(action, "strength") { options.amplitude = PresetBuilder.scaledAmplitude(preset, options.amplitude, by: strength) }
        var stagger = StaggerSettings(delay: number(action, "stagger") ?? 0.08)
        switch string(action, "order") {
        case "leftToRight": stagger.order = .axis(.x, reversed: false)
        case "rightToLeft": stagger.order = .axis(.x, reversed: true)
        case "wave": stagger.order = .distance(from: try point(action["from"]) ?? context.focus)
        default: break
        }
        stagger.randomTiming = number(action, "random") ?? 0
        var builder = PresetBuilder(ids: context.ids)
        let current = Animator.keyedScene(document, at: at)
        let command = builder.apply(preset, to: ids, at: at, options: options, stagger: stagger, current: current, timeline: timeline)
        context.ids = builder.ids
        try run(command, label: "\(preset.title) × \(ids.count) at \(format(at))")
    }

    func shotCamera(_ value: JSONValue?) throws -> ObjectID {
        if let value { return try target(value) }
        if let active = timeline.cutCamera(at: context.now) ?? scene.activeCamera { return active }
        if let first = scene.cameras.first { return first }
        throw fail("no camera yet — add one with {\"do\": \"camera\", …}")
    }

    mutating func cameraMove(_ action: JSONValue) throws {
        guard let move = string(action, "move").flatMap(CameraMove.init(rawValue:)) else {
            throw fail("unknown move (\(CameraMove.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let camera = try shotCamera(action["camera"])
        let at = try time(action["at"])
        let subject = try point(action["subject"]) ?? context.focus
        let options = CameraMoveOptions(duration: number(action, "duration") ?? move.defaultDuration, strength: number(action, "strength") ?? 1)
        let current = Animator.keyedScene(document, at: at)
        let command = CameraMoves.apply(move, camera: camera, subject: subject, at: at, options: options, current: current, timeline: timeline,
                                        ids: &context.ids)
        guard command != nil else { throw fail("that camera can't do \(move.title)") }
        try run(command, label: "\(move.title) at \(format(at))")
    }

    mutating func cut(_ action: JSONValue) throws {
        let camera = try target(action["camera"] ?? action["target"])
        guard scene.objects[camera]?.kind == .camera else { throw fail("cuts go to cameras") }
        let at = try time(action["at"])
        var copy = timeline
        copy.cuts.removeAll { abs($0.time - at) < 0.5 / Double(max(copy.fps, 1)) }
        let transition = string(action, "transition").flatMap(TransitionSpec.Kind.init(rawValue:)).flatMap { kind in
            kind == .cut ? nil : TransitionSpec(kind: kind, duration: number(action, "duration") ?? 0.6)
        }
        copy.cuts.append(CameraCut(time: at, camera: camera, transition: transition))
        copy.cuts.sort { $0.time < $1.time }
        try run(.setTimeline(copy), label: "Cut to \(scene.objects[camera]?.name ?? "camera") at \(format(at))")
    }

    mutating func look(_ action: JSONValue) throws {
        let sceneOnly = bool(action, "sceneOnly") ?? (scene.look != nil)
        var look = document.effectiveLook
        if let mood = string(action, "mood").flatMap(LightingPreset.init(rawValue:)) { look = look.applying(mood) }
        if let post = string(action, "post").flatMap(PostSettings.Preset.init(rawValue:)) { look.post = post.settings }
        if let shading = string(action, "shading").flatMap(ShadingStyle.init(rawValue:)) { look.shading = shading }
        if let fog = action["fog"] {
            if case let .bool(on) = fog { look.fog.enabled = on }
            if let distance = fog.numberValue {
                look.fog.enabled = true
                look.fog.distance = distance
            }
        }
        if let colors = action["palette"]?.arrayValue?.compactMap(\.stringValue) {
            look.palette.swatches = colors.enumerated().compactMap { index, hex in
                RGBA(hex: hex).map { Palette.Swatch(name: "Colour \(index + 1)", color: $0) }
            }
        }
        if let bloom = number(action, "bloom") { look.post.bloom = bloom }
        if let grain = number(action, "grain") { look.post.grain = grain }
        try run(.setLook(look, scope: sceneOnly ? .scene : .project), label: "Look")
    }

    mutating func effect(_ action: JSONValue) throws {
        guard let kind = string(action, "kind").flatMap(ScreenEffect.Kind.init(rawValue:)) else {
            throw fail("unknown effect (\(ScreenEffect.Kind.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        var copy = timeline
        var effect = ScreenEffect(id: context.ids.next(ObjectID.self).raw, kind: kind, start: try time(action["at"]), duration: number(action, "duration"),
                                  strength: number(action, "strength") ?? 1)
        if let color = try color(action["color"]) { effect.color = color.resolved(in: document.palette) }
        copy.effects.append(effect)
        try run(.setTimeline(copy), label: "\(kind.title) at \(format(effect.start))")
    }

    mutating func clip(_ action: JSONValue) throws {
        let character = try target(action["character"] ?? action["target"])
        guard let name = string(action, "clip") else { throw fail("clip needs “clip” (\(BuiltinClips.names.joined(separator: ", ")))") }
        let at = try time(action["at"])
        let asset = string(action, "from").map { AssetID(raw: $0) } ?? BuiltinClips.assetID
        var copy = timeline
        var track = copy.clipTracks.first { $0.target == character } ?? ClipTrack(id: context.ids.next(ObjectID.self).raw, target: character)
        track.segments = track.segments.filter { $0.start < at - 1e-6 }.map { segment in
            var trimmed = segment
            if trimmed.end > at { trimmed.duration = max(at - trimmed.start + 0.3, 0.1) }
            return trimmed
        }
        let duration = number(action, "duration") ?? max(copy.duration - at, 1)
        track.segments.append(ClipSegment(id: context.ids.next(ObjectID.self).raw, clip: ClipRef(asset: asset, name: name), start: at, duration: duration,
                                          loop: bool(action, "loop") ?? true, blend: track.segments.isEmpty ? 0 : 0.3))
        copy.clipTracks.removeAll { $0.target == character }
        copy.clipTracks.append(track)
        try run(.setTimeline(copy), label: "\(scene.objects[character]?.name ?? "Character") plays \(name) at \(format(at))")
    }

    mutating func lipSync(_ action: JSONValue) throws {
        let character = try target(action["character"] ?? action["target"])
        var words = timeline.words
        guard !words.isEmpty else { throw fail("no transcript yet — transcribe the voiceover first") }
        if let phrase = string(action, "words"), let match = WordSnap.find(phrase, in: words).first { words = Array(words[match]) }
        let language = timeline.transcripts.first?.language ?? "en-US"
        let shapes = LipSync.shapes(for: words, language: language)
        guard let first = words.first, let last = words.last else { return }
        let command = LipSync.keys(shapes, character: character, range: TimeRange(start: first.start, end: last.end + 0.2), timeline: timeline,
                                   ids: &context.ids)
        try run(command, label: "Lip sync: \(shapes.count) mouth shapes")
    }
}
