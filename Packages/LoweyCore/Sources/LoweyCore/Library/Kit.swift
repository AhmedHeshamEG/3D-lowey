import Foundation

/// A flat area of a Kit asset other things can stand on (a desk's top, a shelf), in the asset's own space (metres,
/// pivot at the base centre, facing +Z).
public struct KitSurface: Hashable, Sendable {
    public var height: Double
    public var minX: Double
    public var minZ: Double
    public var maxX: Double
    public var maxZ: Double

    public init(height: Double, minX: Double, minZ: Double, maxX: Double, maxZ: Double) {
        self.height = height
        self.minX = minX
        self.minZ = minZ
        self.maxX = maxX
        self.maxZ = maxZ
    }

    public var center: Vec3 { Vec3((minX + maxX) / 2, height, (minZ + maxZ) / 2) }
    public var width: Double { maxX - minX }
    public var depth: Double { maxZ - minZ }
}

extension KitSurface: Codable {
    private enum CodingKeys: String, CodingKey { case height, min, max }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let low = try c.decode([Double].self, forKey: .min)
        let high = try c.decode([Double].self, forKey: .max)
        try self.init(height: c.decode(Double.self, forKey: .height), minX: low.first ?? 0, minZ: low.last ?? 0, maxX: high.first ?? 0,
                      maxZ: high.last ?? 0)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(height, forKey: .height)
        try c.encode([minX, minZ], forKey: .min)
        try c.encode([maxX, maxZ], forKey: .max)
    }
}

/// What the Kit knows about one of its assets: where it belongs, its real size, which way it faces and what can be
/// put on it. This is what places "a lamp on the desk" by relation.
public struct KitInfo: Codable, Hashable, Sendable {
    public var set: String
    public var category: String
    public var realSize: Vec3
    public var front: Vec3
    public var surfaces: [KitSurface]
    /// A source of clips only (an animation library), not something to place.
    public var clipsOnly: Bool

    public init(set: String, category: String, realSize: Vec3, front: Vec3 = Vec3(0, 0, 1), surfaces: [KitSurface] = [], clipsOnly: Bool = false) {
        self.set = set
        self.category = category
        self.realSize = realSize
        self.front = front
        self.surfaces = surfaces
        self.clipsOnly = clipsOnly
    }
}

/// A Set of the Kit (Room & Desk, City Street…) and its categories, in browsing order.
public struct KitSet: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var categories: [String]

    public var id: String { name }
}

/// The Kit as the app ships it: `Kit/kit.json` (the Sets and every asset's folder) and, per asset, a
/// `<id>.loweyasset` folder with `model.glb` and `asset.json` (see `Tools/fetch-kit.py`).
public struct KitIndex: Sendable {
    public var sets: [KitSet]
    /// Library entries for the Kit's assets: ids `kit.<id>`, files relative to the Kit folder.
    public var assets: [LibraryAsset]

    public init(sets: [KitSet] = [], assets: [LibraryAsset] = []) {
        self.sets = sets
        self.assets = assets
    }

    public static let idPrefix = "kit."

    /// Reads the Kit from its folder (an empty Kit when there is none).
    public static func load(from root: URL) throws -> KitIndex {
        let indexURL = root.appendingPathComponent("kit.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return KitIndex() }
        let index = try JSONDecoder().decode(IndexFile.self, from: Data(contentsOf: indexURL))
        var assets: [LibraryAsset] = []
        for entry in index.assets {
            let metaURL = root.appendingPathComponent(entry.path).appendingPathComponent("asset.json")
            let meta = try JSONDecoder().decode(AssetFile.self, from: Data(contentsOf: metaURL))
            assets.append(meta.libraryAsset(folder: entry.path))
        }
        return KitIndex(sets: index.sets, assets: assets)
    }

    /// Assets of a Set, by category, in the Set's category order (clip libraries left out).
    public func browse(_ set: String) -> [(category: String, assets: [LibraryAsset])] {
        guard let kitSet = sets.first(where: { $0.name == set }) else { return [] }
        return kitSet.categories.compactMap { category in
            let members = assets.filter { $0.kit?.set == set && $0.kit?.category == category && $0.kit?.clipsOnly != true }
            return members.isEmpty ? nil : (category, members)
        }
    }

    struct IndexFile: Decodable {
        struct Entry: Decodable {
            var id: String
            var set: String
            var path: String
        }

        var sets: [KitSet]
        var assets: [Entry]
    }

    struct AssetFile: Decodable {
        var id: String
        var name: String
        var set: String
        var category: String
        var tags: [String]
        var realSizeMeters: [Double]
        var front: [Double]
        var topSurfaces: [KitSurface]
        var triangles: Int?
        var source: String?
        var license: String?
        var rig: String?
        var clips: [String]?
        var clipsOnly: Bool?
        var file: String

        func libraryAsset(folder: String) -> LibraryAsset {
            let size = Vec3(realSizeMeters.first ?? 1, realSizeMeters.count > 1 ? realSizeMeters[1] : 1, realSizeMeters.last ?? 1)
            let rigType: RigType = switch rig {
            case "humanoid": .humanoid
            case nil: .none
            default: .custom
            }
            let frontVector = front.count == 3 ? Vec3(front[0], front[1], front[2]) : Vec3(0, 0, 1)
            var asset = LibraryAsset(id: AssetID(raw: KitIndex.idPrefix + id), name: name, tags: tags, format: .glb, file: "\(folder)/\(file)",
                                     rig: rigType, clips: clips ?? [], bounds: Bounds(min: Vec3(-size.x / 2, 0, -size.z / 2),
                                                                                      max: Vec3(size.x / 2, size.y, size.z / 2)),
                                     triangleCount: triangles, source: source, license: license, added: Date(timeIntervalSinceReferenceDate: 0))
            asset.kit = KitInfo(set: set, category: category, realSize: size, front: frontVector, surfaces: topSurfaces, clipsOnly: clipsOnly ?? false)
            return asset
        }
    }
}

public extension LibraryAsset {
    /// Ships with the app (the Kit), as opposed to imported.
    var isKit: Bool { id.raw.hasPrefix(KitIndex.idPrefix) }
}

public extension LibraryItem {
    /// One of the Kit's assets (can't be renamed away or removed: it ships with the app).
    var isKit: Bool {
        if case let .asset(asset) = self { return asset.isKit }
        return false
    }
}
