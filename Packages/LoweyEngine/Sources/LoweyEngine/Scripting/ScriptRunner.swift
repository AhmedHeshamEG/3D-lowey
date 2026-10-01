import Foundation
import JavaScriptCore
import LoweyCore

/// What a script run produced: one undoable command (or nothing), its log, and an error if it failed.
public struct ScriptOutcome: Sendable {
    public var command: EditCommand?
    public var log: [String]
    public var error: String?
    /// Objects the script created (the editor selects them afterwards).
    public var created: [ObjectID]

    public init(command: EditCommand? = nil, log: [String] = [], error: String? = nil, created: [ObjectID] = []) {
        self.command = command
        self.log = log
        self.error = error
        self.created = created
    }
}

/// Runs JavaScript against a copy of the document. Scripts speak the same command language as the
/// UI: everything they do comes back as ONE command the editor applies (and undoes) like any other.
///
/// Sandbox: a fresh JavaScriptCore context per run with no file, network or timer APIs — only the
/// `lowey` / `scene` objects below. Runs off the main thread with a time limit.
///
/// ```js
/// const id = lowey.add("cube", { name: "Box", position: [0, 0, 0], scale: 2, color: "#ff8800" })
/// lowey.key(id, "position", 1.0, [0, 2, 0], "easeOut")
/// lowey.preset([id], "popIn", 0, { duration: 0.4 })
/// ```
public enum ScriptRunner {
    public static func run(
        _ source: String, name: String, document: Document, selection: [ObjectID], time: Double, timeLimit: TimeInterval = 10
    ) async -> ScriptOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<ScriptOutcome, Never>) in
            let once = ResumeOnce(continuation)
            let thread = Thread {
                let outcome = runSynchronously(source, name: name, document: document, selection: selection, time: time, timeLimit: timeLimit)
                once.resume(outcome)
            }
            thread.stackSize = 16 << 20
            thread.start()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeLimit + 2) {
                once.resume(ScriptOutcome(error: "The script took longer than \(Int(timeLimit)) seconds and was stopped."))
            }
        }
    }

    /// Runs on the calling thread (tests, and the worker thread above).
    public static func runSynchronously(
        _ source: String, name: String, document: Document, selection: [ObjectID], time: Double, timeLimit: TimeInterval = 10
    ) -> ScriptOutcome {
        let host = ScriptHost(document: document, deadline: Date().addingTimeInterval(timeLimit))
        guard let context = JSContext() else { return ScriptOutcome(error: "JavaScript isn't available") }
        context.exceptionHandler = { _, exception in
            guard let exception else { return }
            let line = exception.objectForKeyedSubscript("line")?.toInt32() ?? 0
            let message = exception.toString() ?? "error"
            host.failure = line > 0 ? "Line \(line): \(message)" : message
        }
        host.install(in: context, selection: selection, time: time)
        context.evaluateScript(ScriptHost.prelude)
        context.evaluateScript(source, withSourceURL: URL(string: "lowey-script.js"))
        if let failure = host.failure {
            return ScriptOutcome(log: host.log, error: failure)
        }
        let command: EditCommand? = host.commands.isEmpty ? nil : .batch(name, host.commands)
        return ScriptOutcome(command: command, log: host.log, created: host.created)
    }
}

/// Resumes a continuation exactly once (the script finishing and the timeout race).
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ScriptOutcome, Never>?

    init(_ continuation: CheckedContinuation<ScriptOutcome, Never>) {
        self.continuation = continuation
    }

    func resume(_ outcome: ScriptOutcome) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: outcome)
    }
}

/// The state behind the JavaScript API. Confined to the one thread running the script.
final class ScriptHost: @unchecked Sendable {
    var document: Document
    var commands: [EditCommand] = []
    var log: [String] = []
    var created: [ObjectID] = []
    var failure: String?
    var ids = IDFactory.random
    let deadline: Date

    init(document: Document, deadline: Date) {
        self.document = document
        self.deadline = deadline
    }

    /// Deterministic random numbers for scripts (xorshift), so a script builds the same world every run.
    static let prelude = """
    lowey.random = function (seed) {
      let s = (seed >>> 0) || 1;
      return function () { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
    };
    """

    private var scene: Scene { document.scene }

    func perform(_ command: EditCommand?) throws {
        guard let command else { return }
        _ = try command.apply(to: &document)
        commands.append(command)
    }

    // MARK: API

    func install(in context: JSContext, selection: [ObjectID], time: Double) {
        guard let lowey = JSValue(newObjectIn: context), let sceneObject = JSValue(newObjectIn: context) else { return }
        func define(_ target: JSValue, _ name: String, _ body: @escaping ([JSValue]) throws -> Any?) {
            let block: @convention(block) () -> Any? = { [unowned self] in
                let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []
                guard let context = JSContext.current() else { return nil }
                do {
                    if Date() > deadline { throw ScriptAPIError("the script took too long") }
                    return try body(arguments)
                } catch {
                    context.exception = JSValue(newErrorFromMessage: "\(name): \(error)", in: context)
                    return nil
                }
            }
            target.setObject(block, forKeyedSubscript: name as NSString)
        }

        define(lowey, "add") { args in try self.add(args) }
        define(lowey, "group") { args in try self.group(args) }
        define(lowey, "light") { args in try self.light(args) }
        define(lowey, "set") { args in try self.set(args) }
        define(lowey, "key") { args in try self.key(args) }
        define(lowey, "preset") { args in try self.preset(args) }
        define(lowey, "behavior") { args in try self.behavior(args) }
        define(lowey, "flock") { args in try self.flock(args) }
        define(lowey, "crowdWalk") { args in try self.crowdWalk(args) }
        define(lowey, "physics") { args in try self.physics(args) }
        define(lowey, "remove") { args in
            let id = try self.objectID(args, 0)
            try self.perform(.delete([id]))
            return nil
        }
        define(lowey, "log") { args in
            self.log.append(args.map { $0.toString() ?? "" }.joined(separator: " "))
            return nil
        }
        define(sceneObject, "objects") { _ in self.scene.orderedIDs().compactMap { self.describe($0) } }
        define(sceneObject, "find") { args in
            let name = args.first?.toString() ?? ""
            return self.scene.orderedIDs().first { self.scene.objects[$0]?.name == name }?.raw
        }
        define(sceneObject, "get") { args in try self.describe(self.objectID(args, 0)) }
        context.setObject(lowey, forKeyedSubscript: "lowey" as NSString)
        context.setObject(sceneObject, forKeyedSubscript: "scene" as NSString)
        context.setObject(selection.map(\.raw), forKeyedSubscript: "selection" as NSString)
        context.setObject(time, forKeyedSubscript: "time" as NSString)
        context.setObject(scene.timeline.fps, forKeyedSubscript: "fps" as NSString)
        context.setObject(scene.timeline.duration, forKeyedSubscript: "duration" as NSString)
    }

    private func describe(_ id: ObjectID) -> [String: Any]? {
        guard let object = scene.objects[id] else { return nil }
        let world = scene.worldTransform(of: id)
        let euler = object.transform.rotation.eulerDegrees
        return [
            "id": id.raw, "name": object.name, "type": object.kind.typeName,
            "position": [object.transform.position.x, object.transform.position.y, object.transform.position.z],
            "worldPosition": [world.position.x, world.position.y, world.position.z],
            "rotation": [euler.x, euler.y, euler.z],
            "scale": [object.transform.scale.x, object.transform.scale.y, object.transform.scale.z],
            "parent": object.parent?.raw as Any, "children": object.children.map(\.raw)
        ]
    }

    private func objectID(_ args: [JSValue], _ index: Int) throws -> ObjectID {
        guard index < args.count, let raw = args[index].toString(), scene.objects[ObjectID(raw: raw)] != nil else {
            throw ScriptAPIError("argument \(index + 1) must be an object id")
        }
        return ObjectID(raw: raw)
    }

    private func objectIDs(_ value: JSValue?) throws -> [ObjectID] {
        guard let value, !value.isUndefined, !value.isNull else { return [] }
        let raws: [String] = value.isArray ? (value.toArray() ?? []).compactMap { $0 as? String } : [value.toString()].compactMap { $0 }
        let ids = raws.map(ObjectID.init(raw:)).filter { scene.objects[$0] != nil }
        guard !ids.isEmpty else { throw ScriptAPIError("expected object ids") }
        return ids
    }

    private func options(_ args: [JSValue], _ index: Int) -> [String: Any] {
        guard index < args.count, args[index].isObject, !args[index].isArray else { return [:] }
        return (args[index].toDictionary() as? [String: Any]) ?? [:]
    }

    static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    static func vec3(_ value: Any?) -> Vec3? {
        if let number = number(value) { return Vec3(number, number, number) }
        guard let array = value as? [Any], array.count == 3 else { return nil }
        let numbers = array.compactMap(number)
        return numbers.count == 3 ? Vec3(numbers[0], numbers[1], numbers[2]) : nil
    }

    static func color(_ value: Any?) -> ColorValue? {
        if let slot = number(value) { return .palette(Int(slot)) }
        if let hex = value as? String, let rgba = RGBA(hex: hex) { return .rgba(rgba) }
        return nil
    }

    /// JavaScript value → typed property value (arrays for vectors, degrees for rotations, "#hex" or a
    /// palette slot for colours).
    static func propertyValue(_ raw: Any?, for key: PropertyKey) throws -> PropertyValue {
        switch key.spec?.type {
        case .vec3?:
            guard let vector = vec3(raw) else { throw ScriptAPIError("\(key) needs [x, y, z]") }
            return .vec3(vector)
        case .quat?:
            if let array = raw as? [Any], array.count == 4 {
                let n = array.compactMap(number)
                if n.count == 4 { return .quat(Quat(x: n[0], y: n[1], z: n[2], w: n[3]).normalized) }
            }
            guard let euler = vec3(raw) else { throw ScriptAPIError("\(key) needs [x°, y°, z°]") }
            return .quat(Quat(eulerDegrees: euler))
        case .float?, .int?:
            guard let value = number(raw) else { throw ScriptAPIError("\(key) needs a number") }
            return key.spec?.type == .int ? .int(Int(value)) : .float(value)
        case .bool?:
            guard let value = raw as? Bool ?? (raw as? NSNumber)?.boolValue else { throw ScriptAPIError("\(key) needs true/false") }
            return .bool(value)
        case .color?:
            guard let color = color(raw) else { throw ScriptAPIError("\(key) needs \"#rrggbb\" or a palette slot") }
            return .color(color)
        case .enumeration?, .string?:
            return .enumeration(raw as? String ?? String(describing: raw ?? ""))
        case .asset?:
            return .asset(AssetID(raw: raw as? String ?? ""))
        case nil:
            if let bool = raw as? Bool { return .bool(bool) }
            if let value = number(raw) { return .float(value) }
            if let vector = vec3(raw) { return .vec3(vector) }
            return .string(raw as? String ?? "")
        }
    }

    // MARK: Building

    private func place(_ object: SceneObject, options: [String: Any]) throws -> String {
        var object = object
        if let name = options["name"] as? String { object.name = name }
        var transform = object.transform
        if let position = Self.vec3(options["position"]) { transform.position = position }
        if let rotation = Self.vec3(options["rotation"]) { transform.rotation = Quat(eulerDegrees: rotation) }
        if let scale = Self.vec3(options["scale"]) { transform.scale = scale }
        object.transform = transform
        if let color = Self.color(options["color"]), object.kind.hasSurface { object[.color] = .color(color) }
        if let glow = Self.number(options["glow"]), glow > 0 {
            object[.emissiveIntensity] = .float(glow)
            if let color = object.color { object[.emissive] = .color(color) }
        }
        var parent: ObjectID?
        if let raw = options["parent"] as? String {
            guard scene.objects[ObjectID(raw: raw)] != nil else { throw ScriptAPIError("no parent \(raw)") }
            parent = ObjectID(raw: raw)
        }
        try perform(.insert(SceneFragment(object: object), parent: parent, index: nil))
        created.append(object.id)
        return object.id.raw
    }

    private func add(_ args: [JSValue]) throws -> Any? {
        let shapeName = args.first?.toString() ?? "cube"
        guard let shape = PrimitiveShape(rawValue: shapeName) else {
            throw ScriptAPIError("unknown shape \(shapeName) (cube, sphere, cylinder, cone, plane, torus, ramp)")
        }
        var factory = ObjectFactory(ids: ids)
        let object = factory.primitive(shape)
        ids = factory.ids
        return try place(object, options: options(args, 1))
    }

    private func group(_ args: [JSValue]) throws -> Any? {
        var factory = ObjectFactory(ids: ids)
        let object = factory.group(named: args.first?.toString() ?? "Group")
        ids = factory.ids
        return try place(object, options: options(args, 1))
    }

    private func light(_ args: [JSValue]) throws -> Any? {
        let typeName = args.first?.toString() ?? "point"
        guard let type = LightType(rawValue: typeName) else { throw ScriptAPIError("unknown light \(typeName) (point, spot, directional)") }
        let opts = options(args, 1)
        var factory = ObjectFactory(ids: ids)
        var object = factory.light(type, at: Self.vec3(opts["position"]) ?? Vec3(0, 2, 0))
        ids = factory.ids
        if let hex = opts["color"] as? String, let rgba = RGBA(hex: hex) { object[.lightColor] = .color(.rgba(rgba)) }
        if let intensity = Self.number(opts["intensity"]) { object[.lightIntensity] = .float(intensity) }
        if let range = Self.number(opts["range"]) { object[.lightRange] = .float(range) }
        var rest = opts
        rest["position"] = nil
        rest["color"] = nil
        return try place(object, options: rest)
    }

    private func set(_ args: [JSValue]) throws -> Any? {
        let id = try objectID(args, 0)
        guard args.count >= 3, let keyName = args[1].toString() else { throw ScriptAPIError("use set(id, property, value)") }
        let key = PropertyKey(keyName)
        try perform(.setProperties([PropertyChange(object: id, key: key, value: Self.propertyValue(args[2].toObject(), for: key))]))
        return nil
    }

    private func key(_ args: [JSValue]) throws -> Any? {
        let id = try objectID(args, 0)
        guard args.count >= 4, let keyName = args[1].toString() else { throw ScriptAPIError("use key(id, property, time, value, easing?)") }
        let key = PropertyKey(keyName)
        let time = args[2].toDouble()
        let value = try Self.propertyValue(args[3].toObject(), for: key)
        var easing = Easing.easeInOut
        if args.count > 4, let name = args[4].toString(), !args[4].isUndefined {
            guard let parsed = try? LoweyJSON.decode(Easing.self, from: Data("\"\(name)\"".utf8)) else {
                throw ScriptAPIError("unknown easing \(name)")
            }
            easing = parsed
        }
        var keys = KeyOperations(ids: ids)
        let previous = Animator.keyedScene(document, at: time).objects[id]?.properties[key] ?? PropertyDefaults.value(for: key)
        let edit = keys.setKey(id, key, value: value, at: time, previous: previous, easing: easing, in: scene.timeline)
        ids = keys.ids
        try perform(.setTracks([edit]))
        return nil
    }

    private func preset(_ args: [JSValue]) throws -> Any? {
        let targets = try objectIDs(args.first)
        guard args.count >= 2, let name = args[1].toString(), let preset = AnimationPreset(rawValue: name) else {
            throw ScriptAPIError("unknown preset (\(AnimationPreset.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let time = args.count > 2 && args[2].isNumber ? args[2].toDouble() : 0
        let opts = options(args, 3)
        var presetOptions = PresetOptions(preset)
        if let duration = Self.number(opts["duration"]) { presetOptions.duration = duration }
        if let amplitude = Self.number(opts["amplitude"]) { presetOptions.amplitude = amplitude }
        if let direction = Self.vec3(opts["direction"]) { presetOptions.direction = direction }
        var stagger = StaggerSettings()
        if let delay = Self.number(opts["delay"]) { stagger.delay = delay }
        if let random = Self.number(opts["randomTiming"]) { stagger.randomTiming = random }
        if let random = Self.number(opts["randomAmplitude"]) { stagger.randomAmplitude = random }
        if let seed = Self.number(opts["seed"]) { stagger.seed = UInt64(max(seed, 0)) }
        switch opts["order"] as? String {
        case "x"?: stagger.order = .axis(.x, reversed: false)
        case "-x"?: stagger.order = .axis(.x, reversed: true)
        case "y"?: stagger.order = .axis(.y, reversed: false)
        case "z"?: stagger.order = .axis(.z, reversed: false)
        case "-z"?: stagger.order = .axis(.z, reversed: true)
        case "distance"?: stagger.order = .distance(from: Self.vec3(opts["from"]) ?? .zero)
        default: stagger.order = .selection
        }
        var builder = PresetBuilder(ids: ids)
        let current = Animator.keyedScene(document, at: time)
        try perform(builder.apply(preset, to: targets, at: time, options: presetOptions, stagger: stagger, current: current, timeline: scene.timeline))
        ids = builder.ids
        return nil
    }

    private func behavior(_ args: [JSValue]) throws -> Any? {
        let id = try objectID(args, 0)
        guard args.count >= 2, let kindObject = args[1].toObject(), JSONSerialization.isValidJSONObject(kindObject) else {
            throw ScriptAPIError("use behavior(id, { type: \"windSway\", angle: 5 }, { start, end })")
        }
        let kind = try LoweyJSON.decode(BehaviorKind.self, from: JSONSerialization.data(withJSONObject: kindObject))
        let opts = options(args, 2)
        var timeline = scene.timeline
        let behaviorID = (ids.next() as TrackID).raw
        timeline.behaviors.append(Behavior(id: behaviorID, target: id, kind: kind, start: Self.number(opts["start"]) ?? 0,
                                           end: Self.number(opts["end"])))
        try perform(.setTimeline(timeline))
        return behaviorID
    }

    private func flock(_ args: [JSValue]) throws -> Any? {
        let birds = try objectIDs(args.first)
        let opts = options(args, 1)
        var settings = Simulation.FlockSettings()
        if let duration = Self.number(opts["duration"]) { settings.duration = duration }
        if let center = Self.vec3(opts["center"]) { settings.center = center }
        if let extent = Self.vec3(opts["extent"]) { settings.extent = extent }
        if let speed = Self.number(opts["speed"]) { settings.speed = speed }
        if let seed = Self.number(opts["seed"]) { settings.seed = UInt64(max(seed, 0)) }
        try perform(Simulation.flock(birds, settings: settings, at: Self.number(opts["start"]) ?? 0, fps: scene.timeline.fps,
                                     current: scene, timeline: scene.timeline, ids: &ids))
        return nil
    }

    private func crowdWalk(_ args: [JSValue]) throws -> Any? {
        let agents = try objectIDs(args.first)
        guard args.count >= 2, let raw = args[1].toArray() else { throw ScriptAPIError("use crowdWalk(ids, [[x, y, z], …], { speed, start })") }
        let targets = raw.compactMap(Self.vec3)
        guard targets.count >= agents.count else { throw ScriptAPIError("one target per walker") }
        let opts = options(args, 2)
        try perform(Simulation.crowdWalk(agents, to: targets, speed: Self.number(opts["speed"]) ?? 1.3, at: Self.number(opts["start"]) ?? 0,
                                         fps: scene.timeline.fps, current: scene, timeline: scene.timeline, ids: &ids))
        return nil
    }

    private func physics(_ args: [JSValue]) throws -> Any? {
        let objects = try objectIDs(args.first)
        let opts = options(args, 1)
        var settings = PhysicsSettings()
        if let kind = (opts["kind"] as? String).flatMap(PhysicsKind.init(rawValue:)) { settings.kind = kind }
        if let duration = Self.number(opts["duration"]) { settings.duration = duration }
        if let strength = Self.number(opts["strength"]) { settings.strength = strength }
        if let bounce = Self.number(opts["bounce"]) { settings.bounce = bounce }
        settings.center = Self.vec3(opts["center"])
        try perform(Simulation.physics(objects, settings: settings, at: Self.number(opts["start"]) ?? 0, fps: scene.timeline.fps,
                                       bounds: SceneBounds(), current: scene, timeline: scene.timeline, ids: &ids))
        return nil
    }
}

struct ScriptAPIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
