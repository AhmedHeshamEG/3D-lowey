import Foundation

// MARK: - Making things

extension ScriptState {
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
        object = try operations.placeOnGround(object, at: point(action["at"]) ?? context.focus)
        try insert(object, action: action, verb: "Place")
    }

    mutating func text(_ action: JSONValue) throws {
        guard let words = string(action, "text") else { throw fail("text needs “text”") }
        var recipe = TextRecipe(text: words, style: string(action, "style").flatMap(TextRecipe.Style.init(rawValue:)) ?? .blocky)
        if let size = number(action, "size") { recipe.size = size }
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: "Text"), kind: .text(recipe))
        object[.color] = .color(.palette(0))
        object = try operations.placeOnGround(object, at: point(action["at"]) ?? context.focus)
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

    /// A blob character (the house style): {"do": "blob", "likeness": "Isaac Newton"} or {"recipe": {...}}, or both
    /// (the recipe's fields override the likeness). Optional: name, label (text on the hat), at, facing.
    mutating func blob(_ action: JSONValue) throws {
        var recipe = BlobRecipe()
        if let who = string(action, "likeness") ?? string(action, "person") {
            guard let known = Likeness.recipe(for: who) else {
                throw fail("unknown likeness “\(who)” (\(Likeness.people.keys.sorted().joined(separator: ", "))); describe them with “recipe” instead")
            }
            recipe = known
        }
        if let raw = action["recipe"]?.objectValue {
            // Overlay the given fields on the likeness (or the defaults).
            var merged = try LoweyJSON.decode(JSONValue.self, from: LoweyJSON.encode(recipe)).objectValue ?? [:]
            for (key, value) in raw {
                merged[key] = value
            }
            recipe = try LoweyJSON.decode(BlobRecipe.self, from: LoweyJSON.encode(JSONValue.object(merged)))
        }
        if let given = string(action, "name") { recipe.name = given }
        if let label = string(action, "label") { recipe.hatLabel = label }
        let build = BlobCharacter.build(recipe, ids: &context.ids)
        var fragment = build.fragment
        guard let root = fragment.roots.first, let index = fragment.objects.firstIndex(where: { $0.id == root }) else { return }
        fragment.objects[index].name = ObjectFactory.uniqueName(recipe.name, in: scene)
        fragment.objects[index].transform.position = try point(action["at"]) ?? context.focus
        if let facing = number(action, "facing") { fragment.objects[index].transform.rotation = Quat(angle: facing * .pi / 180, axis: .unitY) }
        try run(.insert(fragment, parent: nil, index: nil), label: "Character “\(fragment.objects[index].name)”")
        var withFloat = timeline
        withFloat.behaviors += build.behaviors
        try run(.setTimeline(withFloat), label: nil)
        remember(action, root, name: fragment.objects[index].name)
    }

    mutating func light(_ action: JSONValue) throws {
        let type: LightType = switch string(action, "type") {
        case "spot": .spot
        case "sun", "directional": .directional
        default: .point
        }
        var factory = ObjectFactory(ids: context.ids)
        var object = try factory.light(type, at: point(action["at"]) ?? context.focus + Vec3(0, 2, 0))
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
}
