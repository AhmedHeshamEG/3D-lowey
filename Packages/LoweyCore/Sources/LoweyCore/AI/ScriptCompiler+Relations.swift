import Foundation

// MARK: - Scene Script v3: relations, real sizes, palette slots

extension ScriptState {
    /// `{"do": "place", "target": "Lamp", "relation": "on", "reference": "Desk", "offset": [0.2, 0, 0]}`: the solver
    /// puts it there (grounded, apart from what's already there) and says what it did.
    mutating func relate(_ action: JSONValue) throws {
        let ids = try targets(action["target"])
        guard let relationName = string(action, "relation") else {
            throw fail("place needs “relation” (\(Relation.names.joined(separator: ", ")))")
        }
        guard let relation = Relation(name: relationName, radius: number(action, "radius"), spacing: number(action, "spacing"),
                                      columns: number(action, "columns").map { Int($0) }, seed: UInt64(number(action, "seed") ?? 1)) else {
            throw fail("unknown relation “\(relationName)” (\(Relation.names.joined(separator: ", ")))")
        }
        let reference = try action["reference"].map { try target($0) }
        let solver = RelationSolver(scene: scene, library: context.library)
        let placements: [Placement]
        do {
            placements = try solver.place(ids, relation, reference: reference, offset: vec3(action["offset"]) ?? .zero)
        } catch let error as PlacementError {
            throw fail(error.description)
        }
        try run(solver.command(for: placements), label: placements.map(\.note).joined(separator: "; "))
    }

    /// `{"do": "add", "asset": "desk lamp", "name": "Lamp", "relation": "on", "reference": "Desk"}`: a Kit or library
    /// model found by search, at its real size, then placed by relation when one is given.
    mutating func addAsset(_ action: JSONValue, query: String) throws {
        // An id ("kit.office-desk") names exactly one asset; anything else is a search.
        let exact = context.library.asset(AssetID(raw: query)).map { [$0] } ?? []
        let results = exact + LibrarySearch.search(query, in: context.library).compactMap { item -> LibraryAsset? in
            if case let .asset(asset) = item, asset.kit?.clipsOnly != true { return asset }
            return nil
        }
        guard let asset = results.first else {
            let suggestions = LibrarySearch.items(in: context.library, filter: .sets).prefix(24).map(\.name)
            throw fail("nothing in the Kit or library matches “\(query)” (some of what there is: \(suggestions.joined(separator: ", ")))")
        }
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: asset.name), kind: .asset(asset.id))
        if let look = string(action, "look") { object[.lookPreset] = .enumeration(look) }
        object = try operations.placeOnGround(object, at: point(action["at"]) ?? context.focus)
        try insert(object, action: action, verb: "Add")
        if action["relation"] != nil {
            var placed = action.objectValue ?? [:]
            placed["target"] = .string(object.id.raw)
            try relate(.object(placed))
        }
    }

    /// `{"do": "scaleTo", "target": "Tree", "meters": 6, "axis": "height"}`: real-world size (height by default).
    mutating func scaleTo(_ action: JSONValue) throws {
        let ids = try targets(action["target"])
        guard let meters = number(action, "meters") ?? number(action, "size"), meters > 0 else { throw fail("scaleTo needs “meters”") }
        let axis = string(action, "axis") ?? "height"
        let bounds = SceneBounds(library: context.library)
        var changes: [PropertyChange] = []
        for id in ids {
            guard let object = scene.objects[id], let box = bounds.worldBounds(of: id, in: scene) else { continue }
            let current: Double = switch axis {
            case "width": box.size.x
            case "depth": box.size.z
            case "longest": box.size.maxComponent
            default: box.size.y
            }
            guard current > 1e-6 else { continue }
            changes.append(PropertyChange(object: id, key: .scale, value: .vec3(object.transform.scale * (meters / current))))
        }
        try run(.setProperties(changes), label: "Scale \(ids.count) to \(meters) m (\(axis))")
    }

    /// `{"do": "recolor", "target": "Sofa", "slot": 2}`: tinted with a palette slot (the project's colours).
    mutating func recolor(_ action: JSONValue) throws {
        let ids = try targets(action["target"])
        let slots = document.palette.swatches.count
        guard let slot = number(action, "slot") else { throw fail("recolor needs “slot” (0–\(max(slots - 1, 0)))") }
        let index = min(max(Int(slot), 0), max(slots - 1, 0))
        try run(.setProperties(ids.map { PropertyChange(object: $0, key: .color, value: .color(.palette(index))) }),
                label: "Palette \(index + 1) on \(ids.count) object(s)")
    }
}
