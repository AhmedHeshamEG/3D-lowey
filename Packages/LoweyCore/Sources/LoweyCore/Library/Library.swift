import Foundation

public enum AssetFormat: String, Codable, Sendable, CaseIterable {
    case usdz, gltf, glb, obj

    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "usdz", "usd", "usdc", "usda": self = .usdz
        case "gltf": self = .gltf
        case "glb": self = .glb
        case "obj": self = .obj
        default: return nil
        }
    }
}

/// Skeleton standard of a rigged model (auto-detected from bone names; used in Phase 2
/// for retargeting). `.none` = static model.
public enum RigType: String, Codable, Sendable, CaseIterable {
    case none, humanoid, quadruped, bird, custom

    public var isRigged: Bool { self != .none }
}

/// A model in the global library.
public struct LibraryAsset: Codable, Hashable, Sendable, Identifiable {
    public var id: AssetID
    public var name: String
    public var tags: [String]
    public var format: AssetFormat
    /// Main file, relative to the asset's folder in the library (`assets/<id>/`).
    public var file: String
    public var rig: RigType
    /// Names of the animation clips inside the file (walk, run, idle, …).
    public var clips: [String]
    /// Native bounds in meters (filled in after the first load).
    public var bounds: Bounds?
    public var triangleCount: Int?
    public var source: String?
    public var license: String?
    public var favorite: Bool
    public var added: Date
    public var lastUsed: Date?
    /// Kit assets: set, real size, front, surfaces (nil for imported models).
    public var kit: KitInfo?

    public init(
        id: AssetID, name: String, tags: [String] = [], format: AssetFormat, file: String,
        rig: RigType = .none, clips: [String] = [], bounds: Bounds? = nil, triangleCount: Int? = nil,
        source: String? = nil, license: String? = nil, favorite: Bool = false, added: Date = Date(), lastUsed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.tags = tags
        self.format = format
        self.file = file
        self.rig = rig
        self.clips = clips
        self.bounds = bounds
        self.triangleCount = triangleCount
        self.source = source
        self.license = license
        self.favorite = favorite
        self.added = added
        self.lastUsed = lastUsed
    }
}

/// Something built in the app (selection, group, drawn object) saved for reuse.
/// Scenes reference prefabs by id, so editing the prefab updates every instance.
public struct Prefab: Codable, Hashable, Sendable, Identifiable {
    public var id: PrefabID
    public var name: String
    public var tags: [String]
    public var fragment: SceneFragment
    public var version: Int
    public var favorite: Bool
    public var added: Date
    public var lastUsed: Date?

    public init(
        id: PrefabID, name: String, tags: [String] = [], fragment: SceneFragment, version: Int = 1,
        favorite: Bool = false, added: Date = Date(), lastUsed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.tags = tags
        self.fragment = fragment
        self.version = version
        self.favorite = favorite
        self.added = added
        self.lastUsed = lastUsed
    }
}

/// A saved look ("environment preset").
public struct SavedLook: Codable, Hashable, Sendable, Identifiable {
    public var id: SavedLookID
    public var name: String
    public var look: Look
    public var favorite: Bool
    public var added: Date
    public var lastUsed: Date?

    public init(id: SavedLookID, name: String, look: Look, favorite: Bool = false, added: Date = Date(), lastUsed: Date? = nil) {
        self.id = id
        self.name = name
        self.look = look
        self.favorite = favorite
        self.added = added
        self.lastUsed = lastUsed
    }
}

/// A saved script (JavaScript that drives the command API: generators, simulations, crowds).
public struct ScriptAsset: Codable, Hashable, Sendable, Identifiable {
    public var id: ScriptID
    public var name: String
    public var source: String
    public var tags: [String]
    public var favorite: Bool
    public var added: Date
    public var lastUsed: Date?

    public init(id: ScriptID, name: String, source: String, tags: [String] = ["script"], favorite: Bool = false, added: Date = Date(),
                lastUsed: Date? = nil) {
        self.id = id
        self.name = name
        self.source = source
        self.tags = tags
        self.favorite = favorite
        self.added = added
        self.lastUsed = lastUsed
    }
}

/// `library.json`: everything in the global library ("build once, reuse forever").
public struct LibraryManifest: Codable, Hashable, Sendable {
    public var assets: [LibraryAsset]
    public var prefabs: [Prefab]
    public var looks: [SavedLook]
    public var scripts: [ScriptAsset]
    /// The Kit's assets (shipped with the app; never saved in `library.json`).
    public var kit: [LibraryAsset] = []

    public init(assets: [LibraryAsset] = [], prefabs: [Prefab] = [], looks: [SavedLook] = [], scripts: [ScriptAsset] = []) {
        self.assets = assets
        self.prefabs = prefabs
        self.looks = looks
        self.scripts = scripts
    }

    private enum CodingKeys: String, CodingKey { case assets, prefabs, looks, scripts }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assets = try c.decodeIfPresent([LibraryAsset].self, forKey: .assets) ?? []
        prefabs = try c.decodeIfPresent([Prefab].self, forKey: .prefabs) ?? []
        looks = try c.decodeIfPresent([SavedLook].self, forKey: .looks) ?? []
        scripts = try c.decodeIfPresent([ScriptAsset].self, forKey: .scripts) ?? []
    }

    public func asset(_ id: AssetID) -> LibraryAsset? {
        id.raw.hasPrefix(KitIndex.idPrefix) ? kit.first { $0.id == id } : assets.first { $0.id == id }
    }
    public func prefab(_ id: PrefabID) -> Prefab? { prefabs.first { $0.id == id } }
    public func look(_ id: SavedLookID) -> SavedLook? { looks.first { $0.id == id } }
    public func script(_ id: ScriptID) -> ScriptAsset? { scripts.first { $0.id == id } }
}

/// One row in the library panel.
public enum LibraryItem: Hashable, Sendable, Identifiable {
    case asset(LibraryAsset)
    case prefab(Prefab)
    case look(SavedLook)
    case script(ScriptAsset)

    public var id: String {
        switch self {
        case let .asset(asset): "asset:\(asset.id.raw)"
        case let .prefab(prefab): "prefab:\(prefab.id.raw)"
        case let .look(look): "look:\(look.id.raw)"
        case let .script(script): "script:\(script.id.raw)"
        }
    }

    public var name: String {
        switch self {
        case let .asset(asset): asset.name
        case let .prefab(prefab): prefab.name
        case let .look(look): look.name
        case let .script(script): script.name
        }
    }

    public var tags: [String] {
        switch self {
        case let .asset(asset): asset.tags
        case let .prefab(prefab): prefab.tags
        case .look: ["look", "environment"]
        case let .script(script): script.tags
        }
    }

    public var favorite: Bool {
        switch self {
        case let .asset(asset): asset.favorite
        case let .prefab(prefab): prefab.favorite
        case let .look(look): look.favorite
        case let .script(script): script.favorite
        }
    }

    public var lastUsed: Date? {
        switch self {
        case let .asset(asset): asset.lastUsed
        case let .prefab(prefab): prefab.lastUsed
        case let .look(look): look.lastUsed
        case let .script(script): script.lastUsed
        }
    }

    public var added: Date {
        switch self {
        case let .asset(asset): asset.added
        case let .prefab(prefab): prefab.added
        case let .look(look): look.added
        case let .script(script): script.added
        }
    }

    /// Thumbnail file name inside the library's `thumbnails/` folder.
    public var thumbnailName: String {
        switch self {
        case let .asset(asset): "\(asset.id.raw).png"
        case let .prefab(prefab): "\(prefab.id.raw).png"
        case let .look(look): "\(look.id.raw).png"
        case let .script(script): "\(script.id.raw).png"
        }
    }
}

public enum LibraryFilter: String, Sendable, CaseIterable {
    case sets, all, favorites, recent, models, prefabs, looks, scripts

    public var displayName: String {
        switch self {
        case .sets: "Sets"
        case .all: "All"
        case .favorites: "Favorites"
        case .recent: "Recent"
        case .models: "Models"
        case .prefabs: "Built"
        case .looks: "Looks"
        case .scripts: "Scripts"
        }
    }
}

/// Search-first library: rank by how well the query matches name and tags.
public enum LibrarySearch {
    public static func items(in manifest: LibraryManifest, filter: LibraryFilter) -> [LibraryItem] {
        let kit = manifest.kit.filter { $0.kit?.clipsOnly != true }
        let all: [LibraryItem] = (manifest.assets + kit).map(LibraryItem.asset)
            + manifest.prefabs.map(LibraryItem.prefab)
            + manifest.looks.map(LibraryItem.look)
            + manifest.scripts.map(LibraryItem.script)
        switch filter {
        case .sets: return kit.map(LibraryItem.asset)
        case .all: return all.sorted { $0.added > $1.added }
        case .favorites: return all.filter(\.favorite).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recent:
            return all.filter { $0.lastUsed != nil }
                .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
                .prefix(24).map { $0 }
        case .models: return (manifest.assets + kit).map(LibraryItem.asset).sorted { $0.added > $1.added }
        case .prefabs: return manifest.prefabs.map(LibraryItem.prefab).sorted { $0.added > $1.added }
        case .looks: return manifest.looks.map(LibraryItem.look).sorted { $0.added > $1.added }
        case .scripts: return manifest.scripts.map(LibraryItem.script).sorted { $0.added > $1.added }
        }
    }

    public static func search(_ query: String, in manifest: LibraryManifest, filter: LibraryFilter = .all) -> [LibraryItem] {
        let candidates = items(in: manifest, filter: filter)
        let terms = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard !terms.isEmpty else { return candidates }
        let scored: [(LibraryItem, Double)] = candidates.compactMap { item in
            var total = 0.0
            for term in terms {
                let best = score(term: term, item: item)
                if best <= 0 { return nil } // every term must match something
                total += best
            }
            if item.favorite { total += 0.5 }
            return (item, total)
        }
        return scored.sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
        }.map(\.0)
    }

    static func score(term: String, item: LibraryItem) -> Double {
        let name = item.name.lowercased()
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var best = 0.0
        if name == term { best = max(best, 10) }
        if name.hasPrefix(term) { best = max(best, 8) }
        if words.contains(where: { $0.hasPrefix(term) }) { best = max(best, 6) }
        for tag in item.tags.map({ $0.lowercased() }) {
            if tag == term { best = max(best, 5) }
            if tag.hasPrefix(term) { best = max(best, 4) }
        }
        if name.contains(term) { best = max(best, 3) }
        if best == 0, isSubsequence(term, of: name), term.count >= 3 { best = 1 }
        return best
    }

    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var iterator = haystack.makeIterator()
        for character in needle {
            var found = false
            while let next = iterator.next() {
                if next == character {
                    found = true
                    break
                }
            }
            if !found { return false }
        }
        return true
    }
}

/// Detects the skeleton standard from joint names (Mixamo, Quaternius, Blender-style, generic).
public enum RigClassifier {
    public static func classify(jointNames: [String]) -> RigType {
        guard !jointNames.isEmpty else { return .none }
        let names = jointNames.map { $0.lowercased() }
        func has(_ fragments: String...) -> Bool {
            names.contains { name in fragments.contains { name.contains($0) } }
        }
        let wings = has("wing")
        let beak = has("beak")
        let arms = has("arm", "hand", "shoulder", "clavicle")
        let legs = has("leg", "thigh", "knee", "foot", "shin", "calf")
        let spine = has("spine", "hips", "pelvis", "root", "body")
        let head = has("head", "neck")
        // "rear" only as a word ("forearm" contains r-e-a-r: a Mixamo arm is not a hind leg).
        let rear = names.contains { name in
            name.hasPrefix("rear") || ["_rear", ".rear", " rear", "-rear", ":rear", "rearleg", "rear_leg"].contains { name.contains($0) }
        }
        let frontBack = rear || has("front", "back_leg", "backleg", "hind", "_fl", "_fr", "_bl", "_br", "paw")
        let tail = has("tail")

        if wings || beak { return .bird }
        if frontBack || (tail && legs && !arms) { return .quadruped }
        if arms, legs, spine || head { return .humanoid }
        return .custom
    }
}
