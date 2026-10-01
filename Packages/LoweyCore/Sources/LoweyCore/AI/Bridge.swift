import Foundation

// What the AI sees of a project through the bridge: compact, token-efficient summaries of the scene, the transcript
// and the library. The bridge itself (pairing, local network only, HTTP, Bonjour) is hmm-kit's HmmBridge.

// MARK: - What the AI sees (compact, token-efficient)

public struct SceneSummary: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Sendable {
        public var name: String
        public var kind: String
        public var at: [Double]
        public var size: [Double]?
        public var parent: String?
        public var animated: Bool?
    }

    public struct Camera: Codable, Hashable, Sendable {
        public var name: String
        public var at: [Double]
        public var looking: [Double]
        public var focalLength: Double
    }

    public var scene: String
    public var seconds: Double
    public var fps: Int
    public var mood: String?
    public var post: Bool
    public var objects: [Item]
    public var cameras: [Camera]
    public var cuts: [String]
    public var markers: [String]
    public var effects: [String]
    public var transcript: String?

    static func r(_ value: Double) -> Double { (value * 100).rounded() / 100 }
    static func r(_ vector: Vec3) -> [Double] { [r(vector.x), r(vector.y), r(vector.z)] }

    /// Top-level objects and their direct children (a scene of 300 objects stays readable). `bounds` measures them.
    public init(_ document: Document, bounds: SceneBounds = SceneBounds(), depth: Int = 2) {
        let scene = document.scene
        let timeline = scene.timeline
        self.scene = scene.name
        seconds = timeline.duration
        fps = timeline.fps
        mood = document.effectiveLook.lightingPreset?.rawValue
        post = !document.effectiveLook.post.isNeutral
        let animated = timeline.animatedObjects
        var items: [Item] = []
        func visit(_ id: ObjectID, level: Int) {
            guard let object = scene.objects[id], level <= depth else { return }
            if object.kind != .camera {
                let box = bounds.worldBounds(of: id, in: scene)
                items.append(Item(
                    name: object.name, kind: Self.kind(object.kind), at: Self.r(scene.worldTransform(of: id).position),
                    size: box.map { Self.r($0.size) }, parent: object.parent.flatMap { scene.objects[$0]?.name },
                    animated: animated.contains(id) ? true : nil
                ))
            }
            // Characters and prefabs are summarised as one thing.
            guard object[.rigStandard] == nil else { return }
            for child in object.children {
                visit(child, level: level + 1)
            }
        }
        for root in scene.roots {
            visit(root, level: 1)
        }
        objects = items
        cameras = scene.cameras.compactMap { id in
            guard let object = scene.objects[id] else { return nil }
            let world = scene.worldTransform(of: id)
            return Camera(name: object.name, at: Self.r(world.position), looking: Self.r(world.rotation.act(Vec3(0, 0, -1))),
                          focalLength: Self.r(CameraLens(object).focalLength))
        }
        cuts = timeline.cuts.map { "\(Self.r($0.time))s → \(scene.objects[$0.camera]?.name ?? "?")\($0.transition.map { " (\($0.kind.rawValue))" } ?? "")" }
        markers = timeline.markers.map { "\(Self.r($0.time))s \($0.name)" }
        effects = timeline.effects.map { "\(Self.r($0.start))s \($0.kind.rawValue)" }
        let words = timeline.words
        transcript = words.isEmpty ? nil : words.map(\.text).joined(separator: " ")
    }

    static func kind(_ kind: ObjectKind) -> String {
        switch kind {
        case let .primitive(shape): shape.rawValue
        case let .light(type): "\(type.rawValue) light"
        case let .overlay(recipe): "overlay:\(recipe.shape.rawValue)"
        case let .particles(recipe): "particles:\(recipe.preset.rawValue)"
        case let .text(recipe): "text:\(recipe.text)"
        default: kind.typeName
        }
    }
}

/// Spoken words with their times (for "sync to the voiceover").
public struct TranscriptSummary: Codable, Hashable, Sendable {
    public struct Word: Codable, Hashable, Sendable {
        public var i: Int
        public var w: String
        public var t: Double
        public var e: Double
    }

    public var language: String?
    public var words: [Word]

    public init(_ timeline: Timeline) {
        language = timeline.transcripts.first?.language
        words = timeline.words.enumerated().map { index, word in
            Word(i: index, w: word.text, t: SceneSummary.r(word.start), e: SceneSummary.r(word.end))
        }
    }
}

/// Library items for the AI (search results).
public struct AssetSummary: Codable, Hashable, Sendable {
    public var name: String
    public var kind: String
    public var tags: [String]
    public var rig: String?
    public var clips: [String]?
    public var size: [Double]?

    public static func search(_ query: String, in manifest: LibraryManifest, limit: Int = 40) -> [AssetSummary] {
        let items = query.isEmpty ? manifest.assets.map(LibraryItem.asset) + manifest.prefabs.map(LibraryItem.prefab)
            : LibrarySearch.search(query, in: manifest)
        return items.prefix(limit).compactMap { item in
            switch item {
            case let .asset(asset):
                AssetSummary(name: asset.name, kind: "model", tags: asset.tags, rig: asset.rig.isRigged ? asset.rig.rawValue : nil,
                             clips: asset.clips.isEmpty ? nil : asset.clips, size: asset.bounds.map { SceneSummary.r($0.size) })
            case let .prefab(prefab):
                AssetSummary(name: prefab.name, kind: "prefab", tags: prefab.tags, rig: nil, clips: nil, size: nil)
            default:
                nil
            }
        }
    }
}
