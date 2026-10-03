import Foundation

// MARK: - Scene Script v3: the director's verbs (frame a shot, light it, say what a thing should do)

extension ScriptState {
    /// `{"do": "frameShot", "subject": "Hesham", "shotType": "closeUp", "composition": "leftThird", "lens": 85,
    /// "camera": "Shot 2", "at": {"word": "Nobody"}}`: the camera solver places and aims the camera (a new one
    /// when it doesn't exist yet); with `at`, the edit cuts to it there.
    mutating func frameShot(_ action: JSONValue) throws {
        let subjectID = try target(action["subject"] ?? action["target"])
        guard let subject = shotSubject(subjectID) else { throw fail("can't frame “\(scene.objects[subjectID]?.name ?? subjectID.raw)”") }
        let typeName = string(action, "shotType") ?? string(action, "shot_type") ?? string(action, "type") ?? "medium"
        guard let type = ShotType(rawValue: typeName) ?? ShotType.allCases.first(where: { $0.title.lowercased() == typeName.lowercased() }) else {
            throw fail("unknown shot type “\(typeName)” (\(ShotType.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let compositionName = string(action, "composition") ?? "center"
        guard let composition = Composition(rawValue: compositionName) ?? Composition(rawValue: compositionName.replacingOccurrences(of: "_", with: "")) else {
            throw fail("unknown composition “\(compositionName)” (\(Composition.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let other = try action["other"].map { try target($0) }.flatMap(shotSubject)
        let side: Double = string(action, "side") == "left" ? -1 : 1
        let aspect = number(action, "aspect") ?? 16.0 / 9.0
        let solution = FrameShot.solve(subject, type: type, composition: composition, focalLength: number(action, "lens") ?? number(action, "focalLength"),
                                       other: other, side: side, aspect: aspect)
        let cameraName = string(action, "camera") ?? "\(type.title) on \(scene.objects[subjectID]?.name ?? "subject")"
        let existing = scene.objects.values.first { $0.kind == .camera && $0.name.caseInsensitiveCompare(cameraName) == .orderedSame }
        let camera: ObjectID
        if let existing {
            camera = existing.id
        } else {
            let made = SceneObject(id: context.ids.next(), name: ObjectFactory.uniqueName(cameraName, in: scene), kind: .camera)
            try run(operations.add(made), label: nil)
            remember(action, made.id, name: cameraName)
            camera = made.id
        }
        let parentWorld = scene.objects[camera]?.parent.map { scene.worldTransform(of: $0) } ?? .identity
        let local = Transform.relative(world: Transform(position: solution.position, rotation: solution.rotation), toParent: parentWorld)
        try run(.setProperties([
            PropertyChange(object: camera, key: .position, value: .vec3(local.position)),
            PropertyChange(object: camera, key: .rotation, value: .quat(local.rotation)),
            PropertyChange(object: camera, key: .fieldOfView, value: .float(solution.fieldOfView)),
            PropertyChange(object: camera, key: .focusDistance, value: .float(solution.focusDistance))
        ]), label: "\(type.title), \(composition.title.lowercased()), \(Int(solution.focalLength.rounded())) mm on “\(scene.objects[subjectID]?.name ?? "")”")
        if action["at"] != nil {
            try cut(.object(["camera": .string(camera.raw), "at": action["at"] ?? .number(0)]))
        } else if bool(action, "active") ?? true {
            try run(.setActiveCamera(camera), label: nil)
        }
    }

    /// What the solver needs to know about a subject: its box, which way it faces, whether it's a character.
    func shotSubject(_ id: ObjectID) -> ShotSubject? {
        guard let object = scene.objects[id], let bounds = SceneBounds(library: context.library).worldBounds(of: id, in: scene) else { return nil }
        let local = object.kind.assetID.flatMap { context.library.asset($0)?.kit?.front } ?? Vec3(0, 0, 1)
        var front = scene.worldTransform(of: id).rotation.act(local)
        front.y = 0
        let isCharacter = CharacterOutline.isCharacter(id, in: scene)
            || object.kind.assetID.flatMap { context.library.asset($0)?.rig.isRigged } == true
        return ShotSubject(bounds: bounds, front: front.length > 1e-6 ? front.normalized : Vec3(0, 0, 1), isCharacter: isCharacter)
    }

    /// `{"do": "lighting", "recipe": "key-warm-world-cool", "subject": "Hesham", "intensity": 1.2}`: the recipe's sun
    /// and lamps, placed for the shot camera (the recipe's earlier lamps are replaced, not piled up).
    mutating func lighting(_ action: JSONValue) throws {
        let recipeName = string(action, "recipe") ?? ""
        guard let recipe = LightRecipe(rawValue: recipeName) else {
            throw fail("unknown lighting recipe “\(recipeName)” (\(LightRecipe.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let camera = timeline.cutCamera(at: context.now) ?? scene.activeCamera
        let eye = camera.map { scene.worldTransform(of: $0).position } ?? scene.viewpoint.eye
        let subjectID = try action["subject"].map { try target($0) }
        let box = subjectID.flatMap { SceneBounds(library: context.library).worldBounds(of: $0, in: scene) }
        let subject = box?.center ?? camera.map { id in
            scene.worldTransform(of: id).position + scene.worldTransform(of: id).rotation
                .act(Vec3(0, 0, -1)) * (scene.objects[id]?[.focusDistance]?.floatValue ?? 5)
        } ?? scene.viewpoint.target
        let intensity = number(action, "intensity") ?? 1
        var look = document.effectiveLook
        if recipe == .moonlit || recipe == .noirSingleSource { look = look.applying(.night) }
        look.lighting = recipe.lighting(from: look.lighting, eye: eye, subject: subject, intensity: intensity)
        try run(.setLook(look, scope: scene.look != nil ? .scene : .project), label: "Lighting: \(recipe.rawValue) — \(recipe.reason)")
        let old = scene.objects.values.filter { object in
            if case .light = object.kind { return LightRecipe.lampNames.contains(object.name) }
            return false
        }.map(\.id)
        if !old.isEmpty { try run(operations.delete(old, in: scene), label: nil) }
        let size = box.map { max($0.size.y, $0.size.x, $0.size.z) } ?? 1.7
        for lamp in recipe.lamps {
            var color = lamp.color
            if let warmth = number(action, "warmth") { color = Self.warmed(color, by: warmth) }
            let at = LightRecipe.position(of: lamp, eye: eye, subject: subject, size: size)
            try light(.object([
                "type": .string("point"), "name": .string(lamp.name), "at": .array([.number(at.x), .number(at.y), .number(at.z)]),
                "color": .string(color.hex), "intensity": .number(lamp.intensity * intensity), "range": .number(lamp.range * max(size, 0.5))
            ]))
        }
    }

    /// Shifts a colour warmer (positive) or cooler (negative).
    static func warmed(_ color: RGBA, by amount: Double) -> RGBA {
        let shift = min(max(amount, -1), 1) * 0.12
        return RGBA(min(max(color.r + shift, 0), 1), color.g, min(max(color.b - shift, 0), 1), color.a)
    }
}

// MARK: - Intent: what a thing should do, resolved to presets, clips, expressions and keys

extension ScriptState {
    /// The intent vocabulary of `animate`.
    static let intents = ["enter", "exit", "emphasise", "react", "walk_to", "look_at", "talk", "idle"]

    /// `{"do": "intent", "target": "Hesham", "what": "react", "how": "surprised", "at": {"word": "Nobody"}}` and the
    /// rest of the vocabulary. Characters act (clips, expressions, lip sync); props move (presets).
    mutating func intent(_ action: JSONValue) throws {
        let ids = try targets(action["target"] ?? action["targets"])
        let what = (string(action, "what") ?? "").lowercased().replacingOccurrences(of: "emphasize", with: "emphasise")
            .replacingOccurrences(of: "-", with: "_")
        let at = action["at"] ?? action["on_word"].map { JSONValue.object(["word": $0]) } ?? .number(context.now)
        if let rate = string(action, "frameRate") ?? string(action, "frame_rate") {
            guard let stepping = Stepping(name: rate) else { throw fail("frame rates are ones, twos, threes or fours") }
            try run(.setProperties(ids.map { PropertyChange(object: $0, key: .stepping, value: .enumeration(stepping.name)) }),
                    label: "On \(stepping.name)")
        }
        for id in ids {
            try act(what, id, action: action, at: at)
        }
    }

    /// One target doing one intent.
    mutating func act(_ what: String, _ id: ObjectID, action: JSONValue, at: JSONValue) throws {
        let character = CharacterOutline.isCharacter(id, in: scene)
        let name = JSONValue.string(id.raw)
        switch what {
        case "enter":
            try perform(Self.step("preset", ["target": name, "preset": .string(character ? "dropIn" : "popIn"), "at": at]))
            if character { try perform(Self.oneShot(name, "Wave", at: at, duration: 1.6)) }
        case "exit":
            try perform(Self.step("preset", ["target": name, "preset": .string(character ? "fadeOut" : "popOut"), "at": at]))
        case "emphasise":
            let strength = JSONValue.number(number(action, "strength") ?? 1)
            try perform(Self.step("preset", ["target": name, "preset": .string("pulse"), "at": at, "strength": strength]))
            if character { try perform(Self.oneShot(name, "Point", at: at, duration: 1.2)) }
        case "react":
            try react(id, character: character, at: at, how: string(action, "how"))
        case "walk_to":
            try walk(id, to: action["to"] ?? action["reference"], at: at, duration: number(action, "duration"))
        case "look_at":
            try lookAt(id, target: action["to"] ?? action["reference"], at: at)
        case "talk":
            guard character else { throw fail("only characters talk") }
            if !timeline.words.isEmpty {
                try perform(Self.step("lipSync", action["words"].map { ["character": name, "words": $0] } ?? ["character": name]))
            }
            try perform(Self.step("clip", ["character": name, "clip": .string("Talk"), "at": at, "duration": action["duration"] ?? .number(2)]))
        case "idle":
            try perform(character ? Self.step("clip", ["character": name, "clip": .string("Idle"), "at": at])
                : Self.step("preset", ["target": name, "preset": .string("float"), "at": at, "duration": action["duration"] ?? .number(4)]))
        default:
            throw fail("animate “what” is one of \(Self.intents.joined(separator: ", "))")
        }
    }

    /// An action of `verb` with `fields`.
    static func step(_ verb: String, _ fields: [String: JSONValue]) -> JSONValue {
        .object(fields.merging(["do": .string(verb)]) { _, verb in verb })
    }

    /// A clip played once.
    static func oneShot(_ character: JSONValue, _ clip: String, at: JSONValue, duration: Double) -> JSONValue {
        step("clip", ["character": character, "clip": .string(clip), "at": at, "duration": .number(duration), "loop": .bool(false)])
    }

    mutating func react(_ id: ObjectID, character: Bool, at: JSONValue, how: String?) throws {
        let name = JSONValue.string(id.raw)
        guard character else {
            try perform(Self.step("preset", ["target": name, "preset": .string("shake"), "at": at, "duration": .number(0.5)]))
            return
        }
        let expression = how.flatMap(FaceExpression.init(rawValue:)) ?? .surprised
        try perform(Self.step("expression", ["character": name, "name": .string(expression.rawValue), "at": at]))
        let clip = switch expression {
        case .happy, .laugh: "Celebrate"
        case .thinking, .sad: "Shrug"
        default: "Nod"
        }
        try perform(Self.oneShot(name, clip, at: at, duration: 1.2))
    }

    /// Walks to a point or next to a thing: position keys (eased, an arc in the middle) and the Walk clip, then Idle.
    mutating func walk(_ id: ObjectID, to destination: JSONValue?, at: JSONValue, duration: Double?) throws {
        guard let destination, var goal = try point(destination) else { throw fail("walk_to needs “to” (a name or [x, y, z])") }
        let start = try time(at)
        let from = scene.worldTransform(of: id).position
        goal.y = from.y
        if destination.stringValue != nil, let box = try SceneBounds(library: context.library).worldBounds(of: target(destination), in: scene) {
            // Stop in front of the thing, not inside it.
            let away = (from - box.center).withY(0)
            let reach = max(box.size.x, box.size.z) / 2 + 0.45
            goal = box.center.withY(from.y) + (away.length > 1e-6 ? away.normalized : Vec3(0, 0, 1)) * reach
        }
        let distance = (goal - from).length
        let time = duration ?? max(distance / 1.2, 0.6)
        let side = Vec3.unitY.cross(goal - from).normalized * min(distance * 0.08, 0.4)
        let middle = (from + goal) * 0.5 + side
        let heading = Quat(angle: atan2(goal.x - from.x, goal.z - from.z), axis: .unitY)
        let name = JSONValue.string(id.raw)
        try perform(.object(["do": .string("key"), "target": name, "property": .string("position"), "keys": .array([
            .object(["t": .number(start), "value": Self.json(from), "easing": .string("easeIn")]),
            .object(["t": .number(start + time / 2), "value": Self.json(middle), "easing": .string("linear")]),
            .object(["t": .number(start + time), "value": Self.json(goal), "easing": .string("easeOut")])
        ])]))
        try addKeys([id], .rotation, [(start, .quat(heading), .easeInOut)])
        try perform(.object(["do": .string("clip"), "character": name, "clip": .string("Walk"), "at": .number(start), "duration": .number(time)]))
        try perform(.object(["do": .string("clip"), "character": name, "clip": .string("Idle"), "at": .number(start + time)]))
    }

    /// Turns to face something from `at` on (a look-at behaviour), the head leading.
    mutating func lookAt(_ id: ObjectID, target destination: JSONValue?, at: JSONValue) throws {
        guard let destination else { throw fail("look_at needs “to”") }
        let other = try target(destination)
        var copy = timeline
        try copy.behaviors.append(Behavior(id: context.ids.next(ObjectID.self).raw, target: id, kind: .lookAt(other), start: time(at)))
        try run(.setTimeline(copy), label: "“\(scene.objects[id]?.name ?? "")” looks at “\(scene.objects[other]?.name ?? "")”")
    }

    static func json(_ vector: Vec3) -> JSONValue { .array([.number(vector.x), .number(vector.y), .number(vector.z)]) }
}

private extension Vec3 {
    func withY(_ y: Double) -> Vec3 { Vec3(x, y, z) }
}
