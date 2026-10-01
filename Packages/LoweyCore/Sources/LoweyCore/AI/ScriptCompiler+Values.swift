import Foundation

// MARK: - Values

extension ScriptState {
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

    /// Generators name their group themselves; the script's name wins.
    mutating func nameGroup(_ group: ObjectID, _ action: JSONValue, fallback: String) throws {
        if let wanted = string(action, "name"), scene.objects[group]?.name != wanted {
            try run(.rename(group, wanted), label: nil)
        }
        remember(action, group, name: string(action, "name") ?? fallback)
    }

    mutating func remember(_ action: JSONValue, _ id: ObjectID, name: String) {
        created[string(action, "name") ?? name] = id
        created[name] = id
    }
}
