import Foundation

/// MCP v2 replies that are pure data (the bridge serves them; the tests check them on Linux).

/// `find_assets`: a Kit or library model with what placing it needs to know.
public struct FoundAsset: Codable, Hashable, Sendable {
    /// Use this in `add` ("asset": id): it names exactly one model.
    public var id: String
    public var name: String
    /// Kit Set ("Room & Desk"), or "Library" for your own models.
    public var set: String
    public var category: String?
    public var tags: [String]
    /// Real size in metres [width, height, depth].
    public var size: [Double]?
    /// Heights (m) of the surfaces things can be put `on` (a desk's top, a shelf's boards).
    public var surfaces: [Double]
    /// Which way its front faces in its own space.
    public var front: [Double]?
    public var rigged: Bool
    public var clips: [String]?

    /// Models matching `query` (all when empty), optionally in one Set, Kit first.
    public static func find(_ query: String, set: String? = nil, in manifest: LibraryManifest, limit: Int = 12) -> [FoundAsset] {
        let items = query.trimmingCharacters(in: .whitespaces).isEmpty ? LibrarySearch.items(in: manifest, filter: .models)
            : LibrarySearch.search(query, in: manifest)
        let assets = items.compactMap { item -> LibraryAsset? in
            guard case let .asset(asset) = item, asset.kit?.clipsOnly != true else { return nil }
            guard let set else { return asset }
            return (asset.kit?.set ?? "Library").caseInsensitiveCompare(set) == .orderedSame ? asset : nil
        }
        let ranked = assets.enumerated().sorted { lhs, rhs in
            (lhs.element.isKit ? 0 : 1, lhs.offset) < (rhs.element.isKit ? 0 : 1, rhs.offset)
        }.map(\.element)
        return ranked.prefix(max(limit, 1)).map(FoundAsset.init)
    }

    public init(_ asset: LibraryAsset) {
        id = asset.id.raw
        name = asset.name
        set = asset.kit?.set ?? "Library"
        category = asset.kit?.category
        tags = asset.tags
        let size = asset.kit?.realSize ?? asset.bounds?.size
        self.size = size.map { SceneSummary.r($0) }
        surfaces = (asset.kit?.surfaces ?? []).map { SceneSummary.r($0.height) }
        front = asset.kit.map { SceneSummary.r($0.front) }
        rigged = asset.rig.isRigged
        clips = asset.clips.isEmpty ? nil : asset.clips
    }
}

/// `read_project`: the project at a glance (summary first), then what a director needs to plan with.
public struct ProjectReading: Codable, Hashable, Sendable {
    public struct SceneLine: Codable, Hashable, Sendable {
        public var name: String
        /// Length and frame rate (nil for scenes that aren't open: they aren't loaded).
        public var seconds: Double?
        public var fps: Int?
        public var look: String?
        public var open: Bool
    }

    public struct Shot: Codable, Hashable, Sendable {
        public var camera: String
        /// When the edit cuts to it (seconds), and the word spoken there.
        public var at: [Double]
        public var words: [String]
        public var focalLength: Double
    }

    public var summary: String
    public var project: String
    public var look: String
    public var mood: String?
    public var palette: [String]
    public var scenes: [SceneLine]
    public var shots: [Shot]
    public var cast: [String]
    /// The open scene's transcript (text), and how many timed words it has (GET the transcript for the timings).
    public var transcript: String?
    public var words: Int
    /// Kit Sets the open scene uses.
    public var kitSets: [String]
    public var objects: Int

    public init(_ document: Document, scenes: [(name: String, seconds: Double?, fps: Int?, look: String?)] = [], library: LibraryManifest = LibraryManifest()) {
        let scene = document.scene
        let timeline = scene.timeline
        let words = timeline.words
        project = document.project.name
        let lookID = document.effectiveLook.presetID
        look = lookID
        mood = document.effectiveLook.lightingPreset?.rawValue
        palette = document.palette.swatches.map(\.color.hex)
        let open = SceneLine(name: scene.name, seconds: timeline.duration, fps: timeline.fps, look: lookID, open: true)
        self.scenes = scenes.isEmpty ? [open] : scenes.map { line in
            line.name == scene.name ? open : SceneLine(name: line.name, seconds: line.seconds, fps: line.fps, look: line.look, open: false)
        }
        let cameras = scene.orderedIDs().compactMap { id -> SceneObject? in scene.objects[id].flatMap { $0.kind == .camera ? $0 : nil } }
        shots = cameras.map { camera in
            var times = timeline.cuts.filter { $0.camera == camera.id }.map(\.time)
            if times.isEmpty, scene.activeCamera == camera.id { times = [0] }
            return Shot(camera: camera.name, at: times.map(SceneSummary.r),
                        words: times.compactMap { WordSnap.word(at: $0 + 0.05, in: words, lookback: 0.3)?.text },
                        focalLength: SceneSummary.r(CameraLens(camera).focalLength))
        }
        cast = scene.roots.filter { CharacterOutline.isCharacter($0, in: scene) }.compactMap { scene.objects[$0]?.name }
        transcript = words.isEmpty ? nil : words.map(\.text).joined(separator: " ")
        self.words = words.count
        kitSets = Set(scene.objects.values.compactMap { $0.kind.assetID.flatMap { library.asset($0)?.kit?.set } }).sorted()
        objects = scene.objects.count
        let cutCount = timeline.cuts.count
        summary = "“\(document.project.name)”, scene “\(scene.name)”: \(String(format: "%.1f", timeline.duration)) s at \(timeline.fps) fps in the "
            + "\(lookID) Look; \(cameras.count) camera\(cameras.count == 1 ? "" : "s") (\(cutCount) cut\(cutCount == 1 ? "" : "s")), "
            + "\(cast.count) character\(cast.count == 1 ? "" : "s"), \(objects) objects"
            + (words.isEmpty ? "; no voiceover transcript yet." : "; \(words.count) spoken words.")
    }
}
